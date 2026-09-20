-- Migration 007 — runtime deployment identity and generation governance

alter table runtime_desired_state
  add column if not exists runtime_version text;

alter table runtime_desired_state
  add column if not exists prior_runtime_version text;

alter table runtime_desired_state
  add column if not exists prior_generation_disposition text;

alter table runtime_desired_state
  add column if not exists one_active_prod_generation boolean not null default true;

alter table runtime_actual_observations
  add column if not exists observed_task_title text;

alter table runtime_actual_observations
  add column if not exists observed_runtime_version text;

alter table runtime_actual_observations
  add column if not exists observed_enabled boolean;

alter table runtime_actual_observations
  add column if not exists observed_timezone text;

alter table runtime_actual_observations
  add column if not exists observed_schedule_spec text;

create table if not exists runtime_deployment_generations (
  deployment_generation_id uuid primary key default gen_random_uuid(),
  worker_key text not null,
  environment text not null default 'PROD',
  runtime_version text not null,
  task_id text,
  task_title text not null,
  contract_version text not null,
  backend text not null,
  canonical_store text not null,
  lifecycle_state text not null default 'PLANNED' check (
    lifecycle_state in ('PLANNED','CANARY','ACTIVE','BLOCKED','FAILED','RETIRED')
  ),
  enabled boolean not null default false,
  source_change_id text references system_changes(change_id) on delete set null,
  deployment_strategy text check (
    deployment_strategy in ('PATCH_EXISTING','REDEPLOY_NEW_GENERATION','PARALLEL_CANARY')
  ),
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  retired_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  unique(worker_key, environment, runtime_version)
);

create unique index if not exists one_enabled_active_prod_generation_per_worker
on runtime_deployment_generations(worker_key, environment)
where environment='PROD' and lifecycle_state='ACTIVE' and enabled=true;

create index if not exists runtime_deployment_generations_worker_idx
on runtime_deployment_generations(worker_key, environment, created_at desc);

create or replace view runtime_generation_health as
select
  d.worker_key,
  d.task_title as desired_task_title,
  d.runtime_version as desired_runtime_version,
  d.contract_version as desired_contract_version,
  d.expected_task_id,
  d.prior_runtime_version,
  d.prior_generation_disposition,
  d.one_active_prod_generation,
  coalesce((
    select count(*)
    from runtime_deployment_generations g
    where g.worker_key=d.worker_key
      and g.environment='PROD'
      and g.lifecycle_state='ACTIVE'
      and g.enabled=true
  ),0) as active_prod_generations,
  case
    when d.runtime_version is null then 'UNVERSIONED_DESIRED_STATE'
    when coalesce((
      select count(*)
      from runtime_deployment_generations g
      where g.worker_key=d.worker_key
        and g.environment='PROD'
        and g.lifecycle_state='ACTIVE'
        and g.enabled=true
    ),0) > 1 then 'MULTIPLE_ACTIVE_PROD_GENERATIONS'
    when coalesce((
      select count(*)
      from runtime_deployment_generations g
      where g.worker_key=d.worker_key
        and g.environment='PROD'
        and g.lifecycle_state='ACTIVE'
        and g.enabled=true
    ),0) = 0 then 'NO_VERIFIED_ACTIVE_GENERATION'
    else 'ONE_ACTIVE_GENERATION'
  end as generation_status
from runtime_desired_state d;

alter table runtime_deployment_generations enable row level security;

comment on table runtime_deployment_generations is
'Canonical deployment-generation ledger. Runtime version is distinct from worker contract version. At most one enabled ACTIVE PROD generation per logical worker.';
