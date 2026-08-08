-- hire_date_migration.sql
-- Feature 6: Open-shift claim priority (seniority-first vs.
-- first-come-first-served).
--
-- Adds a nullable `hire_date` to `company_members` — the proper
-- seniority signal, confirmed with the human rather than using
-- `created_at` (time since joining Knight Shift) as a proxy, which
-- would be wrong for someone who worked at the company for years
-- before adopting this app.
--
-- Also adds a manager-configurable `open_shift_priority` column to
-- `companies` (off/default = first-come-first-served).

alter table public.company_members
  add column if not exists hire_date date;

alter table public.companies
  add column if not exists open_shift_priority text not null default 'first_come';