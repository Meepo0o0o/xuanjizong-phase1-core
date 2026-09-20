-- Migration 003 — PM change-impact governance and runtime deployment drift
-- Phase 1 only

create table if not exists system_changes (
  change_id text primary key,
  phase text not null default 'Phase 1',
  title text not null,
  change_class text not null check (
    change_class in ('LOCAL_BEHAVIOR','INTERFACE','DATA_MODEL','RUNTIME','ARCHITECTURE','GOVERNANCE')
  ),
  requirement_text text not null,
  rationale text,
  status text not null default 'IMPACT_ANALYSIS' check (
    status in ('IMPACT_ANALYSIS','APPROVED','IMPLEMENTING','VERIFYING','BLOCKED','COMPLETE','SUPERSEDED')
  ),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists change_impacts (
  change_id text not null references system_changes(change_id) on delete cascade,
  component_key text not null,
  component_type text not null,
  impact_summary text not null,
  required_action text,
  verification_method text,
  status text not null default 'PENDING' check (
    status in ('PENDING','NOT_APPLICABLE','IMPLEMENTED','VERIFIED','BLOCKED','DRIFT')
  ),
  verification_evidence text,
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  primary key (change_id, component_key)
);

create table if not exists runtime_desired_state (
  worker_key text primary key,
  task_title text not null,
  expected_task_id text,
  contract_version text not null,
  canonical_backend text not null,
  authoritative_store text not null,
  schedule_spec text not null,
  timezone text not null,
  legacy_sheet_access text not null check (
    legacy_sheet_access in ('FORBIDDEN','FORENSIC_READ_ONLY','ALLOWED')
  ),
  heartbeat_required boolean not null default true,
  source_change_id text references system_changes(change_id),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists runtime_actual_observations (
  observation_id uuid primary key default gen_random_uuid(),
  worker_key text not null references runtime_desired_state(worker_key) on delete cascade,
  observed_at timestamptz not null default now(),
  observed_task_id text,
  observed_contract_version text,
  observed_backend text,
  observed_authoritative_store text,
  observed_legacy_sheet_access text,
  heartbeat_observed boolean,
  observation_source text not null,
  evidence_summary text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists runtime_actual_observations_worker_idx
  on runtime_actual_observations(worker_key, observed_at desc);

create or replace view latest_runtime_actual as
select distinct on (worker_key)
  observation_id,
  worker_key,
  observed_at,
  observed_task_id,
  observed_contract_version,
  observed_backend,
  observed_authoritative_store,
  observed_legacy_sheet_access,
  heartbeat_observed,
  observation_source,
  evidence_summary,
  metadata
from runtime_actual_observations
order by worker_key, observed_at desc;

create or replace view runtime_deployment_drift as
select
  d.worker_key,
  d.task_title,
  d.expected_task_id,
  d.contract_version as desired_contract_version,
  d.canonical_backend as desired_backend,
  d.authoritative_store as desired_authoritative_store,
  d.legacy_sheet_access as desired_legacy_sheet_access,
  d.heartbeat_required,
  a.observed_at,
  a.observed_task_id,
  a.observed_contract_version,
  a.observed_backend,
  a.observed_authoritative_store,
  a.observed_legacy_sheet_access,
  a.heartbeat_observed,
  a.observation_source,
  a.evidence_summary,
  case
    when a.worker_key is null then 'UNVERIFIED'
    when d.expected_task_id is not null
         and a.observed_task_id is not null
         and d.expected_task_id is distinct from a.observed_task_id then 'DRIFT'
    when a.observed_contract_version is null then 'UNVERIFIED'
    when d.contract_version is distinct from a.observed_contract_version then 'DRIFT'
    when a.observed_backend is null then 'UNVERIFIED'
    when d.canonical_backend is distinct from a.observed_backend then 'DRIFT'
    when a.observed_authoritative_store is null then 'UNVERIFIED'
    when d.authoritative_store is distinct from a.observed_authoritative_store then 'DRIFT'
    when a.observed_legacy_sheet_access is null then 'UNVERIFIED'
    when d.legacy_sheet_access is distinct from a.observed_legacy_sheet_access then 'DRIFT'
    when d.heartbeat_required and coalesce(a.heartbeat_observed,false) = false then 'DRIFT'
    else 'VERIFIED'
  end as deployment_status
from runtime_desired_state d
left join latest_runtime_actual a using (worker_key);

create or replace view change_gate_status as
select
  c.change_id,
  c.phase,
  c.title,
  c.change_class,
  c.status as change_status,
  count(i.component_key) as impact_count,
  count(*) filter (where i.status = 'VERIFIED') as verified_count,
  count(*) filter (where i.status = 'NOT_APPLICABLE') as not_applicable_count,
  count(*) filter (where i.status in ('PENDING','IMPLEMENTED','BLOCKED','DRIFT')) as open_or_failed_count,
  case
    when count(i.component_key) = 0 then 'BLOCKED_NO_IMPACT_ANALYSIS'
    when count(*) filter (where i.status in ('PENDING','IMPLEMENTED','BLOCKED','DRIFT')) > 0 then 'BLOCKED'
    else 'READY_FOR_ACCEPTANCE'
  end as gate_status
from system_changes c
left join change_impacts i on i.change_id = c.change_id
group by c.change_id, c.phase, c.title, c.change_class, c.status;

alter table system_changes enable row level security;
alter table change_impacts enable row level security;
alter table runtime_desired_state enable row level security;
alter table runtime_actual_observations enable row level security;

comment on view runtime_deployment_drift is
'Desired-vs-observed runtime contract comparison. UNVERIFIED is not equivalent to KEEP or VERIFIED.';

comment on view change_gate_status is
'PM Change Impact Gate. Material changes remain blocked until every impact is VERIFIED or explicitly NOT_APPLICABLE.';
