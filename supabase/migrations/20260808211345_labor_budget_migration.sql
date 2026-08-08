-- labor_budget_migration.sql
-- Feature 2: Labor budget & overtime-risk alerts while building the
-- schedule.
--
-- Adds a manager-configurable weekly labor budget ($) to `companies`.
-- Advisory only — never blocks shift creation. The overtime-risk
-- projection itself is computed client-side (reusing OvertimeService
-- / PayrollAnalyticsService logic), so no new tables are needed for
-- that half.

alter table public.companies
  add column if not exists labor_budget_enabled boolean not null default false,
  add column if not exists labor_budget_amount numeric(10,2) not null default 0;