-- Migration 004 — runtime drift evaluation precedence
-- Known hard mismatches must classify DRIFT even when some observation fields remain unknown.

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
    when a.observed_contract_version is not null
         and d.contract_version is distinct from a.observed_contract_version then 'DRIFT'
    when a.observed_backend is not null
         and d.canonical_backend is distinct from a.observed_backend then 'DRIFT'
    when a.observed_authoritative_store is not null
         and d.authoritative_store is distinct from a.observed_authoritative_store then 'DRIFT'
    when a.observed_legacy_sheet_access is not null
         and d.legacy_sheet_access is distinct from a.observed_legacy_sheet_access then 'DRIFT'
    when d.heartbeat_required
         and a.heartbeat_observed is not null
         and a.heartbeat_observed = false then 'DRIFT'
    when a.observed_contract_version is null
      or a.observed_backend is null
      or a.observed_authoritative_store is null
      or a.observed_legacy_sheet_access is null
      or (d.heartbeat_required and a.heartbeat_observed is null) then 'UNVERIFIED'
    else 'VERIFIED'
  end as deployment_status
from runtime_desired_state d
left join latest_runtime_actual a using (worker_key);

comment on view runtime_deployment_drift is
'Desired-vs-observed runtime contract comparison. Any known hard mismatch is DRIFT; missing evidence is UNVERIFIED.';
