-- skills_migration.sql
-- Feature 3: Skill/role tags + required-skill shifts
--
-- New `employee_skills` table: a company-wide skill tag (e.g.
-- "bartender", "certified forklift") that can be attached to
-- employees. A shift can optionally note a required skill.
--
-- Advisory only: if a manager assigns someone without the required
-- tag, warn — don't block (same fail-open philosophy as the
-- existing availability check).

-- 1. Company-wide skill tags (manager-managed).
create table if not exists public.employee_skills (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  label text not null,
  created_at timestamptz not null default now(),
  unique (company_id, label)
);

-- 2. Which employees have which skill.
create table if not exists public.employee_skill_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  skill_id uuid not null references public.employee_skills(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, skill_id)
);

-- 3. Optional required-skill on a shift.
alter table public.shifts
  add column if not exists required_skill_id uuid references public.employee_skills(id) on delete set null;

-- RLS: skills are visible to any company member (same as shifts).
create policy "employee_skills_select_company_member"
  on public.employee_skills
  for select
  using (public.is_company_member(company_id));

-- RLS: only managers can add/remove company-wide skill tags.
create policy "employee_skills_insert_manager"
  on public.employee_skills
  for insert
  with check (public.is_company_manager(company_id));

create policy "employee_skills_delete_manager"
  on public.employee_skills
  for delete
  using (public.is_company_manager(company_id));

-- RLS: skill assignments visible to any company member.
create policy "employee_skill_assignments_select_company_member"
  on public.employee_skill_assignments
  for select
  using (public.is_company_member(company_id));

-- RLS: managers can assign/unassign skills to employees.
create policy "employee_skill_assignments_insert_manager"
  on public.employee_skill_assignments
  for insert
  with check (public.is_company_manager(company_id));

create policy "employee_skill_assignments_delete_manager"
  on public.employee_skill_assignments
  for delete
  using (public.is_company_manager(company_id));