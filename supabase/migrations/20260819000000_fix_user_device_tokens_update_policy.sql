-- 20260819000000_fix_user_device_tokens_update_policy.sql
--
-- Fixes a real bug in the original push-notifications migration
-- (20260808211346_push_notifications_migration.sql): user_device_tokens
-- had SELECT/INSERT/DELETE policies but no UPDATE policy.
--
-- Why this matters: PushNotificationService._registerToken() calls
-- .upsert(..., onConflict: 'user_id,token'). The FIRST time a given
-- (user_id, token) pair is registered, that's a clean INSERT and
-- works fine. Every time after that — which is the normal, expected,
-- repeated case (app reopened with an already-registered token) —
-- PostgREST resolves the upsert as INSERT ... ON CONFLICT DO UPDATE,
-- and Postgres RLS checks the UPDATE policy for that path, not
-- INSERT. With no UPDATE policy granted, that upsert silently fails
-- with a permission error on every re-registration.
--
-- Written as a new, separate migration (not an edit to the original
-- file) since the original was already applied — rewriting an
-- already-run migration would misrepresent this project's schema
-- history. Guarded so it's safe to run more than once, since
-- Postgres has no native CREATE POLICY IF NOT EXISTS.

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'user_device_tokens'
      and policyname = 'user_device_tokens_update_own'
  ) then
    create policy "user_device_tokens_update_own"
    on public.user_device_tokens
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
  end if;
end $$;