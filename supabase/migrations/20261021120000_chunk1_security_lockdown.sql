-- =====================================================================
-- Knight Shift — Chunk 1: security lockdown
-- =====================================================================
-- What this does, in plain English:
--   1. Removes 6 leftover database "views" that let anyone with the
--      public app key read every company's payroll and staff lists.
--   2. Makes "create a company" and "accept an invite" single,
--      server-checked steps, so nobody can join a company they weren't
--      invited to. Invite emails are stored in lowercase.
--   3. One membership per person per company, linked to their profile
--      (this also fixes the employee list, which failed outright),
--      and allows the "accountant" role.
--   4. Only Stripe (through the webhook) can change billing fields.
--   5. Clock-in and clock-out times are stamped by the server, in the
--      company's time zone. Employees can no longer edit their punches;
--      managers still can. One open punch per person per company.
--   6. Every user gets a profile row (name + email), now and at sign-up.
--
-- Safe to run more than once. Runs as one transaction: if anything
-- fails, nothing changes. Ends with a short report of what it did.
-- =====================================================================

begin;

create temp table if not exists chunk1_report (n serial, step text, result text) on commit preserve rows;
truncate chunk1_report;

-- Facts recorded BEFORE any change, for the audit write-up.
insert into chunk1_report (step, result)
select 'before: app users could read auth.users',
       case when has_table_privilege('authenticated', 'auth.users', 'SELECT') then 'yes' else 'no' end;

-- ---------------------------------------------------------------------
-- 1. Remove the leftover views (the app never used them).
--    The *_legacy tables stay as a backup; RLS already blocks them.
-- ---------------------------------------------------------------------
do $$
declare v text; dropped int := 0;
begin
  foreach v in array array['employees','schedules','payroll_items',
                           'backup_employees','backup_payroll_items','backup_schedules'] loop
    if exists (select 1 from pg_views where schemaname = 'public' and viewname = v) then
      execute format('drop view public.%I', v);
      dropped := dropped + 1;
    end if;
  end loop;
  insert into chunk1_report (step, result) values ('1. leftover views removed', dropped::text);
end $$;

-- ---------------------------------------------------------------------
-- 6 (first, because step 3 links members to profiles).
--    Profiles for every user: backfill now, and create one at sign-up.
-- ---------------------------------------------------------------------
do $$
declare added int; filled int;
begin
  insert into public.profiles (id, email, full_name)
  select u.id, lower(u.email), nullif(trim(u.raw_user_meta_data ->> 'full_name'), '')
  from auth.users u
  where not exists (select 1 from public.profiles p where p.id = u.id);
  get diagnostics added = row_count;

  update public.profiles p
     set email = lower(u.email)
    from auth.users u
   where u.id = p.id and (p.email is null or p.email <> lower(u.email));
  get diagnostics filled = row_count;

  insert into chunk1_report (step, result)
  values ('6. profiles created for existing users', added::text),
         ('6. profile emails filled in or corrected', filled::text);
end $$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, lower(new.email), nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''))
  on conflict (id) do update
    set email = excluded.email,
        full_name = coalesce(public.profiles.full_name, excluded.full_name);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = lower(new.email) where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.handle_user_email_change();

-- ---------------------------------------------------------------------
-- 3. Memberships: clean up, one per person per company, linked to the
--    person's profile, and the accountant role allowed.
-- ---------------------------------------------------------------------
do $$
declare orphans int; dupes int;
begin
  -- Rows pointing at nobody (no user, no company, or a deleted user).
  delete from public.company_members m
   where m.user_id is null
      or m.company_id is null
      or not exists (select 1 from public.profiles p where p.id = m.user_id);
  get diagnostics orphans = row_count;

  -- Duplicate rows for the same person in the same company: keep the oldest.
  delete from public.company_members m
   using (
     select id, row_number() over (partition by company_id, user_id
                                   order by created_at nulls last, id) as rn
       from public.company_members
   ) d
   where m.id = d.id and d.rn > 1;
  get diagnostics dupes = row_count;

  insert into chunk1_report (step, result)
  values ('3. membership rows removed: no matching user', orphans::text),
         ('3. membership rows removed: duplicates', dupes::text);
end $$;

alter table public.company_members alter column company_id set not null;
alter table public.company_members alter column user_id set not null;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.company_members'::regclass
                    and conname = 'company_members_company_user_key') then
    alter table public.company_members
      add constraint company_members_company_user_key unique (company_id, user_id);
  end if;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.company_members'::regclass
                    and conname = 'company_members_user_id_fkey') then
    alter table public.company_members
      add constraint company_members_user_id_fkey
      foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;
end $$;

alter table public.company_members drop constraint if exists company_members_role_check;
alter table public.company_members
  add constraint company_members_role_check
  check (role = any (array['employee', 'manager', 'admin', 'accountant']));

-- Members are now only added by create_company() and accept_invite().
drop policy if exists company_members_insert on public.company_members;

-- ---------------------------------------------------------------------
-- 2. Invites: lowercase emails, no duplicates, managers-only changes.
-- ---------------------------------------------------------------------
do $$
declare lowered int; orphaned int; dupes int;
begin
  update public.company_invites
     set email = lower(trim(email))
   where email <> lower(trim(email));
  get diagnostics lowered = row_count;

  delete from public.company_invites i
   where not exists (select 1 from public.companies c where c.id = i.company_id);
  get diagnostics orphaned = row_count;

  -- Several pending invites for the same email + company: keep the newest.
  update public.company_invites i
     set status = 'revoked'
    from (
      select id, row_number() over (partition by company_id, email
                                    order by created_at desc nulls last, id) as rn
        from public.company_invites
       where status = 'pending'
    ) d
   where i.id = d.id and d.rn > 1;
  get diagnostics dupes = row_count;

  insert into chunk1_report (step, result)
  values ('2. invite emails changed to lowercase', lowered::text),
         ('2. invites removed: company no longer exists', orphaned::text),
         ('2. duplicate pending invites revoked', dupes::text);
end $$;

update public.company_invites set role = 'employee' where role is null;
update public.company_invites set status = 'pending' where status is null;
alter table public.company_invites alter column role set not null;
alter table public.company_invites alter column status set not null;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.company_invites'::regclass
                    and conname = 'company_invites_company_id_fkey') then
    alter table public.company_invites
      add constraint company_invites_company_id_fkey
      foreign key (company_id) references public.companies(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.company_invites'::regclass
                    and conname = 'company_invites_role_check') then
    alter table public.company_invites
      add constraint company_invites_role_check
      check (role = any (array['employee', 'manager', 'admin', 'accountant']));
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.company_invites'::regclass
                    and conname = 'company_invites_status_check') then
    alter table public.company_invites
      add constraint company_invites_status_check
      check (status = any (array['pending', 'accepted', 'revoked']));
  end if;
end $$;

create unique index if not exists company_invites_one_pending_per_email
  on public.company_invites (company_id, email)
  where status = 'pending';

create or replace function public.normalize_invite_email()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.email := lower(trim(new.email));
  return new;
end;
$$;

drop trigger if exists trg_normalize_invite_email on public.company_invites;
create trigger trg_normalize_invite_email
  before insert or update of email on public.company_invites
  for each row execute function public.normalize_invite_email();

-- The old rules read auth.users, which app users can't read, and let an
-- invitee edit their invite (including which company it was for).
-- New rules compare against the email in the user's sign-in token.
drop policy if exists company_invites_select on public.company_invites;
create policy company_invites_select on public.company_invites
  for select to authenticated
  using (public.is_company_manager(company_id)
         or email = lower(auth.jwt() ->> 'email'));

drop policy if exists company_invites_update on public.company_invites;
create policy company_invites_update on public.company_invites
  for update to authenticated
  using (public.is_company_manager(company_id))
  with check (public.is_company_manager(company_id));

-- insert / delete policies (managers only) are unchanged.

-- ---------------------------------------------------------------------
-- 4. Billing fields: only Stripe (service role) or the dashboard.
--    Also: each company gets a time zone (used for punch times).
-- ---------------------------------------------------------------------
alter table public.companies
  add column if not exists time_zone text not null default 'America/Los_Angeles';

create or replace function public.guard_company_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.time_zone) then
    raise exception 'Unknown time zone: %', new.time_zone;
  end if;

  -- App users (signed-in or anonymous) may never set billing fields.
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.subscription_status := 'trialing';
      new.subscription_tier := 'starter';
      new.trial_end := now() + interval '30 days';
      new.current_period_end := null;
      new.stripe_customer_id := null;
      new.stripe_subscription_id := null;
    elsif new.subscription_status is distinct from old.subscription_status
       or new.subscription_tier is distinct from old.subscription_tier
       or new.trial_end is distinct from old.trial_end
       or new.current_period_end is distinct from old.current_period_end
       or new.stripe_customer_id is distinct from old.stripe_customer_id
       or new.stripe_subscription_id is distinct from old.stripe_subscription_id then
      raise exception 'Billing details can only be changed through Stripe';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_company_fields on public.companies;
create trigger trg_guard_company_fields
  before insert or update on public.companies
  for each row execute function public.guard_company_fields();

-- Companies are now only created through create_company().
drop policy if exists companies_insert on public.companies;

-- ---------------------------------------------------------------------
-- 2 (cont.). The server steps the app calls.
-- ---------------------------------------------------------------------
create or replace function public.create_company(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_company_id uuid;
begin
  if v_uid is null then
    raise exception 'Please sign in first';
  end if;
  if v_name = '' then
    raise exception 'Enter a company name';
  end if;
  if length(v_name) > 100 then
    raise exception 'Company name must be 100 characters or fewer';
  end if;

  insert into public.profiles (id, email)
  select u.id, lower(u.email) from auth.users u where u.id = v_uid
  on conflict (id) do nothing;

  insert into public.companies (name) values (v_name)
  returning id into v_company_id;

  insert into public.company_members (company_id, user_id, role)
  values (v_company_id, v_uid, 'manager');

  return jsonb_build_object('company_id', v_company_id,
                            'company_name', v_name,
                            'role', 'manager');
end;
$$;

create or replace function public.list_my_invites()
returns table (invite_id uuid, company_id uuid, company_name text, role text, created_at timestamp)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.company_id, c.name, i.role, i.created_at
    from public.company_invites i
    join public.companies c on c.id = i.company_id
    join auth.users u on u.id = auth.uid()
   where i.status = 'pending'
     and i.email = lower(u.email)
     and not exists (select 1 from public.company_members m
                      where m.company_id = i.company_id and m.user_id = u.id)
   order by i.created_at desc nulls last;
$$;

create or replace function public.accept_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_invite public.company_invites%rowtype;
  v_company_name text;
  v_role text;
begin
  if v_uid is null then
    raise exception 'Please sign in first';
  end if;

  select lower(email) into v_email from auth.users where id = v_uid;

  select * into v_invite
    from public.company_invites
   where id = p_invite_id
     and status = 'pending'
     and email = v_email
   for update;

  if not found then
    raise exception 'This invite is no longer available';
  end if;

  insert into public.profiles (id, email) values (v_uid, v_email)
  on conflict (id) do nothing;

  insert into public.company_members (company_id, user_id, role, hourly_rate)
  values (v_invite.company_id, v_uid, v_invite.role,
          coalesce(v_invite.hourly_rate, 15.00))
  on conflict (company_id, user_id) do nothing;

  update public.company_invites set status = 'accepted' where id = v_invite.id;

  select c.name into v_company_name from public.companies c where c.id = v_invite.company_id;
  select m.role into v_role from public.company_members m
   where m.company_id = v_invite.company_id and m.user_id = v_uid;

  return jsonb_build_object('company_id', v_invite.company_id,
                            'company_name', v_company_name,
                            'role', v_role);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Punches: server time, one open punch, employees can't edit.
-- ---------------------------------------------------------------------
do $$
declare closed int;
begin
  -- Older duplicate open punches (left by a past bug) are closed at their
  -- own start time, i.e. zero hours, so they can be reviewed and corrected
  -- by a manager in Time Entries. The newest open punch stays open.
  update public.time_entries t
     set clock_out = t.clock_in
    from (
      select id, row_number() over (partition by user_id, company_id
                                    order by clock_in desc nulls last, id) as rn
        from public.time_entries
       where clock_out is null
    ) d
   where t.id = d.id and d.rn > 1;
  get diagnostics closed = row_count;
  insert into chunk1_report (step, result)
  values ('5. extra open punches closed at zero hours (check Time Entries)', closed::text);
end $$;

create unique index if not exists time_entries_one_open_punch
  on public.time_entries (user_id, company_id)
  where clock_out is null;

drop policy if exists time_entries_insert on public.time_entries;
drop policy if exists time_entries_update on public.time_entries;
-- time_entries_select and time_entries_manager_update stay as they are.

create or replace function public.clock_in(p_company_id uuid, p_photo_path text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tz text;
  v_row public.time_entries%rowtype;
begin
  if v_uid is null then
    raise exception 'Please sign in first';
  end if;
  if not exists (select 1 from public.company_members
                  where company_id = p_company_id and user_id = v_uid) then
    raise exception 'You are not a member of this company';
  end if;
  if exists (select 1 from public.time_entries
              where company_id = p_company_id and user_id = v_uid and clock_out is null) then
    raise exception 'You are already clocked in';
  end if;
  if p_photo_path is not null
     and p_photo_path not like (p_company_id::text || '/' || v_uid::text || '/%') then
    raise exception 'Invalid photo';
  end if;

  select time_zone into v_tz from public.companies where id = p_company_id;

  insert into public.time_entries (user_id, company_id, clock_in, clock_in_photo_path)
  values (v_uid, p_company_id, now() at time zone v_tz, p_photo_path)
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.clock_out(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tz text;
  v_row public.time_entries%rowtype;
begin
  if v_uid is null then
    raise exception 'Please sign in first';
  end if;

  select time_zone into v_tz from public.companies where id = p_company_id;

  update public.time_entries
     set clock_out = greatest(now() at time zone v_tz, clock_in)
   where company_id = p_company_id and user_id = v_uid and clock_out is null
  returning * into v_row;

  if not found then
    raise exception 'You are not clocked in';
  end if;

  return to_jsonb(v_row);
end;
$$;

-- ---------------------------------------------------------------------
-- Who may call what. Trigger helpers are never called directly.
-- ---------------------------------------------------------------------
revoke all on function public.create_company(text) from public, anon;
revoke all on function public.list_my_invites() from public, anon;
revoke all on function public.accept_invite(uuid) from public, anon;
revoke all on function public.clock_in(uuid, text) from public, anon;
revoke all on function public.clock_out(uuid) from public, anon;
grant execute on function public.create_company(text) to authenticated;
grant execute on function public.list_my_invites() to authenticated;
grant execute on function public.accept_invite(uuid) to authenticated;
grant execute on function public.clock_in(uuid, text) to authenticated;
grant execute on function public.clock_out(uuid) to authenticated;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_user_email_change() from public, anon, authenticated;
revoke all on function public.guard_company_fields() from public, anon, authenticated;
revoke all on function public.normalize_invite_email() from public, anon, authenticated;

-- Pin the search path of the two existing permission helpers.
alter function public.is_company_member(uuid) set search_path = '';
alter function public.is_company_manager(uuid) set search_path = '';

commit;

-- Tell PostgREST (the API layer) to pick up the new functions now.
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Report: what changed, and a check that everything is in place.
-- ---------------------------------------------------------------------
select step, result from (
  select n as ord, step, result from chunk1_report
  union all select 100, 'check: leftover views remaining (want 0)',
    (select count(*)::text from pg_views where schemaname = 'public'
       and viewname in ('employees','schedules','payroll_items','backup_employees',
                        'backup_payroll_items','backup_schedules'))
  union all select 101, 'check: users without a profile (want 0)',
    (select count(*)::text from auth.users u
      where not exists (select 1 from public.profiles p where p.id = u.id))
  union all select 102, 'check: new server steps installed (want 5)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('create_company','list_my_invites','accept_invite','clock_in','clock_out'))
  union all select 103, 'check: employees can edit their own punches (want no)',
    (select case when exists (select 1 from pg_policies where tablename = 'time_entries'
                               and policyname in ('time_entries_insert','time_entries_update'))
                 then 'yes' else 'no' end)
  union all select 104, 'check: invitees can edit invites (want no)',
    (select case when exists (select 1 from pg_policies where tablename = 'company_invites'
                               and policyname = 'company_invites_update'
                               and qual like '%email%') then 'yes' else 'no' end)
  union all select 105, 'check: billing guard installed (want yes)',
    (select case when exists (select 1 from pg_trigger where tgname = 'trg_guard_company_fields')
                 then 'yes' else 'no' end)
) r
order by ord;
