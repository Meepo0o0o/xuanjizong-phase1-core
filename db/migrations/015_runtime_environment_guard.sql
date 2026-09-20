-- 015_runtime_environment_guard.sql
-- Database-level environment attestation for runtime RPCs.
-- The environment value itself is deployment configuration and is intentionally
-- not seeded by this public migration.

create schema if not exists private;

revoke all on schema private from public;

do $private_schema_roles$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema private from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema private from authenticated';
  end if;
end
$private_schema_roles$;

create table if not exists private.runtime_environment_guard (
  singleton boolean primary key default true check (singleton),
  environment text not null check (environment in ('TEST','PROD')),
  configured_at timestamptz not null default now()
);

alter table private.runtime_environment_guard enable row level security;

revoke all on private.runtime_environment_guard from public;

do $environment_guard_roles$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on private.runtime_environment_guard from anon';
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on private.runtime_environment_guard from authenticated';
  end if;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant usage on schema private to service_role';
    execute 'revoke all on private.runtime_environment_guard from service_role';
    execute 'grant select on private.runtime_environment_guard to service_role';

    -- New unattended runtimes must start through the guarded v2 API.
    execute 'revoke execute on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) from service_role';
    execute 'grant execute on function public.runtime_begin_run_v2(text,text,text,text,text,text,text,text,text,text,integer,jsonb) to service_role';
  end if;
end
$environment_guard_roles$;

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
set search_path = public, private, pg_temp
as $$
declare
  v_id uuid;
  v_existing public.research_runs%rowtype;
  v_database_environment text;
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

  select environment
    into v_database_environment
  from private.runtime_environment_guard
  where singleton = true;

  if not found then
    raise exception 'runtime environment guard is not configured';
  end if;

  if v_database_environment is distinct from p_environment then
    raise exception 'runtime environment mismatch: database %, request %',
      v_database_environment, p_environment;
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

comment on table private.runtime_environment_guard is
  'Admin-configured singleton environment marker used to fail closed on TEST/PROD cross-wiring.';

comment on function public.runtime_begin_run_v2(
  text,text,text,text,text,text,text,text,text,text,integer,jsonb
) is
  'Starts one explicit-identity worker run only when the request environment matches the database environment guard.';
