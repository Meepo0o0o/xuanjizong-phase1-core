-- 009_slim_runtime_and_archive_legacy_control_plane.sql
-- Phase 1 cleanup: keep business/runtime schema small while preserving obsolete control-plane data.
-- This migration is intentionally non-destructive to historical rows: obsolete tables move to archive schema.

-- Canonical runtime evidence lives on research_runs.
alter table public.research_runs
  add column if not exists worker_key text,
  add column if not exists runtime_version text,
  add column if not exists task_id text,
  add column if not exists task_title text,
  add column if not exists runtime_backend text,
  add column if not exists environment text,
  add column if not exists input_count integer,
  add column if not exists output_count integer,
  add column if not exists error_count integer;

alter table public.research_runs
  drop constraint if exists research_runs_input_count_nonnegative,
  add constraint research_runs_input_count_nonnegative check (input_count is null or input_count >= 0),
  drop constraint if exists research_runs_output_count_nonnegative,
  add constraint research_runs_output_count_nonnegative check (output_count is null or output_count >= 0),
  drop constraint if exists research_runs_error_count_nonnegative,
  add constraint research_runs_error_count_nonnegative check (error_count is null or error_count >= 0);

create index if not exists research_runs_worker_runtime_idx
  on public.research_runs(worker_key, started_at desc)
  where worker_key is not null;

comment on table public.research_runs is
  'Canonical per-invocation runtime evidence for Phase 1 workers. schema_version stores the worker/contract version; runtime identity is stored directly on the run.';

-- Retire obsolete PM/governance/runtime-control views. Desired state remains in GitHub;
-- actual runtime state is evidenced by research_runs and the Scheduled Task system.
drop view if exists public.pm_change_lifecycle_status cascade;
drop view if exists public.engineering_governance_health cascade;
drop view if exists public.runtime_generation_health cascade;
drop view if exists public.runtime_deployment_drift cascade;
drop view if exists public.latest_runtime_actual cascade;
drop view if exists public.change_gate_status cascade;
drop view if exists public.execution_work_order_gate cascade;
drop view if exists public.latest_execution_return cascade;
drop view if exists public.latest_pm_acceptance cascade;
drop view if exists public.missing_execution_work_orders cascade;
drop view if exists public.missing_project_changelog cascade;

-- Remove enforcement code belonging only to the retired custom PM control plane.
drop trigger if exists trg_enforce_change_complete_gate on public.system_changes;
drop trigger if exists trg_enforce_work_order_return_contract on public.execution_work_orders;
drop function if exists public.enforce_change_complete_gate();
drop function if exists public.enforce_work_order_return_contract();

-- Preserve legacy rows outside the active public schema.
create schema if not exists archive;

alter table if exists public.runtime_actual_observations set schema archive;
alter table if exists public.runtime_deployment_generations set schema archive;
alter table if exists public.runtime_desired_state set schema archive;

alter table if exists public.pm_acceptance_reviews set schema archive;
alter table if exists public.execution_returns set schema archive;
alter table if exists public.execution_work_orders set schema archive;
alter table if exists public.change_impacts set schema archive;
alter table if exists public.project_changelog_entries set schema archive;
alter table if exists public.governance_exceptions set schema archive;
alter table if exists public.engineering_governance_rules set schema archive;
alter table if exists public.system_changes set schema archive;

-- One-time migration evidence is not runtime state.
alter table if exists public.raw_import_records set schema archive;

comment on schema archive is
  'Historical/forensic objects removed from the active Phase 1 runtime schema. Do not use as runtime authority.';

revoke all on schema archive from public;

do $archive_roles$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on schema archive from anon';
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on schema archive from authenticated';
  end if;
end
$archive_roles$;
