-- 014_runtime_identity_v2.sql
-- Make worker/run identity explicit without reintroducing a custom deployment
-- control plane. Existing schema_version/runtime_version columns remain as
-- compatibility aliases for legacy callers.

alter table public.research_runs
  add column if not exists contract_version text,
  add column if not exists release_version text,
  add column if not exists deployment_id text;

comment on column public.research_runs.contract_version is
  'Version of the worker/business contract executed by this run.';
comment on column public.research_runs.release_version is
  'Version of the approved software/prompt release executed by this run.';
comment on column public.research_runs.deployment_id is
  'Concrete deployment identity that executed this run; distinct from scheduler task identity.';
comment on column public.research_runs.schema_version is
  'Legacy compatibility alias for contract_version. New runtimes must use runtime_begin_run_v2.';
comment on column public.research_runs.runtime_version is
  'Legacy compatibility alias for release_version. New runtimes must use runtime_begin_run_v2.';

alter table public.research_runs
  add constraint research_runs_explicit_identity_all_or_none
  check (
    (contract_version is null and release_version is null and deployment_id is null)
    or
    (
      nullif(btrim(contract_version), '') is not null
      and nullif(btrim(release_version), '') is not null
      and nullif(btrim(deployment_id), '') is not null
    )
  );

create or replace function public.runtime_begin_run_v2(
  p_run_id text,
  p_worker text,
  p_worker_key text,
  p_contract_version text,
  p_release_version text,
  p_deployment_id text,
  p_task_id text,
  p_task_title text,
  p_runtime_backend text,
  p_environment text,
  p_input_count integer default 0,
  p_input_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_existing public.research_runs%rowtype;
begin
  if nullif(btrim(p_run_id), '') is null
     or nullif(btrim(p_worker_key), '') is null
     or nullif(btrim(p_contract_version), '') is null
     or nullif(btrim(p_release_version), '') is null
     or nullif(btrim(p_deployment_id), '') is null
     or nullif(btrim(p_task_id), '') is null
     or nullif(btrim(p_runtime_backend), '') is null
     or nullif(btrim(p_environment), '') is null then
    raise exception
      'runtime_begin_run_v2 requires non-empty run, worker, contract, release, deployment, task, backend and environment identity';
  end if;

  if p_input_count is not null and p_input_count < 0 then
    raise exception 'input_count must be nonnegative';
  end if;

  insert into public.research_runs(
    run_id,
    worker,
    worker_key,
    schema_version,
    runtime_version,
    contract_version,
    release_version,
    deployment_id,
    task_id,
    task_title,
    runtime_backend,
    environment,
    input_count,
    status,
    started_at,
    input_context
  )
  values (
    p_run_id,
    p_worker,
    p_worker_key,
    p_contract_version,
    p_release_version,
    p_contract_version,
    p_release_version,
    p_deployment_id,
    p_task_id,
    p_task_title,
    p_runtime_backend,
    p_environment,
    coalesce(p_input_count, 0),
    'RUNNING',
    now(),
    coalesce(p_input_context, '{}'::jsonb)
  )
  on conflict (run_id) do nothing
  returning research_run_id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  select *
    into v_existing
  from public.research_runs
  where run_id = p_run_id;

  if not found then
    raise exception 'run_id conflict could not be read back: %', p_run_id;
  end if;

  if v_existing.worker_key is distinct from p_worker_key
     or v_existing.contract_version is distinct from p_contract_version
     or v_existing.release_version is distinct from p_release_version
     or v_existing.deployment_id is distinct from p_deployment_id
     or v_existing.task_id is distinct from p_task_id
     or v_existing.runtime_backend is distinct from p_runtime_backend
     or v_existing.environment is distinct from p_environment then
    raise exception 'run_id % already exists with different explicit runtime identity', p_run_id;
  end if;

  return v_existing.research_run_id;
end;
$$;

comment on function public.runtime_begin_run_v2(
  text,text,text,text,text,text,text,text,text,text,integer,jsonb
) is
  'Idempotently starts one worker invocation using explicit worker/contract/release/deployment/task/environment identity.';

comment on function public.runtime_begin_run(
  text,text,text,text,text,text,text,text,text,integer,jsonb
) is
  'Legacy run-start API retained for compatibility. New runtimes must use runtime_begin_run_v2.';

revoke execute on function public.runtime_begin_run_v2(
  text,text,text,text,text,text,text,text,text,text,integer,jsonb
) from public;

do $runtime_identity_v2_roles$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function public.runtime_begin_run_v2(text,text,text,text,text,text,text,text,text,text,integer,jsonb) from anon';
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function public.runtime_begin_run_v2(text,text,text,text,text,text,text,text,text,text,integer,jsonb) from authenticated';
  end if;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.runtime_begin_run_v2(text,text,text,text,text,text,text,text,text,text,integer,jsonb) to service_role';
  end if;
end
$runtime_identity_v2_roles$;
