-- push_notifications_migration.sql
-- Feature 5: Real push notifications (FCM/APNs).
--
-- Adds a `user_device_tokens` table (RLS scoped to the owning user)
-- and a trigger on `notifications` insert that calls the
-- `send-push-notification` Edge Function, which delivers the actual
-- push via FCM/APNs.
--
-- The Edge Function itself is in supabase/functions/send-push-notification/
-- and requires external setup (Firebase project, service account key)
-- — see the setup guide in docs/push-notifications-setup.md.
--
-- NOTE: this trigger uses the `pg_net` extension (net.http_post) to
-- fire-and-forget the Edge Function call so a slow FCM/APNs round
-- trip never blocks the notification insert. The service role key is
-- read from the `app.settings.service_role_key` custom GUC, which
-- must be set via `ALTER DATABASE ... SET app.settings.service_role_key`
-- (or in the Supabase dashboard under Database → Settings) before
-- this trigger will work. See the setup guide.

-- 0. pg_net extension for async HTTP from triggers.
create extension if not exists pg_net;

-- 1. Device tokens, scoped to the owning user.
create table if not exists public.user_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'unknown', -- 'android' | 'ios' | 'web'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);
alter table public.user_device_tokens enable row level security;

-- RLS: a user can only see/insert/delete their own tokens.
create policy "user_device_tokens_select_own"
  on public.user_device_tokens
  for select
  using (auth.uid() = user_id);

create policy "user_device_tokens_insert_own"
  on public.user_device_tokens
  for insert
  with check (auth.uid() = user_id);

create policy "user_device_tokens_delete_own"
  on public.user_device_tokens
  for delete
  using (auth.uid() = user_id);

-- 2. Trigger: on notifications insert, call the Edge Function to
--    deliver the push. SECURITY DEFINER so the function can read the
--    notification row and the recipient's device tokens without
--    needing the caller to have SELECT on either.
create or replace function public.notify_push_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  service_role_key text;
begin
  -- Read the service role key from the custom GUC. Set it via:
  --   ALTER DATABASE postgres SET app.settings.service_role_key = '<key>';
  -- (or in the Supabase dashboard under Database → Settings).
  service_role_key := current_setting('app.settings.service_role_key', true);
  if service_role_key is null or service_role_key = '' then
    -- No key configured — skip push delivery rather than erroring
    -- the notification insert. The in-app notification still works.
    return new;
  end if;

  perform net.http_post(
    url := 'https://ithbdavewhomckokmjzy.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body := jsonb_build_object(
      'notification_id', new.id,
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_push_delivery on public.notifications;
create trigger trg_notify_push_delivery
  after insert on public.notifications
  for each row
  execute function public.notify_push_delivery();