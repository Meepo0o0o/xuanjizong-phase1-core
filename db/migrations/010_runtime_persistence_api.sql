-- 010_runtime_persistence_api.sql
-- Shared Phase 1 runtime persistence boundary.
-- Engineering foundation only: no business-ranking or screening logic lives here.

create or replace function public.runtime_begin_run(
  p_run_id text,
  p_worker text,
  p_worker_key text,
  p_schema_version text,
  p_runtime_version text,
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
     or nullif(btrim(p_schema_version), '') is null
     or nullif(btrim(p_runtime_version), '') is null
     or nullif(btrim(p_environment), '') is null then
    raise exception 'runtime_begin_run requires non-empty run/runtime identity';
  end if;

  if p_input_count is not null and p_input_count < 0 then
    raise exception 'input_count must be nonnegative';
  end if;

  insert into public.research_runs(
    run_id, worker, worker_key, schema_version, runtime_version,
    task_id, task_title, runtime_backend, environment,
    input_count, status, started_at, input_context
  )
  values (
    p_run_id, p_worker, p_worker_key, p_schema_version, p_runtime_version,
    p_task_id, p_task_title, p_runtime_backend, p_environment,
    coalesce(p_input_count, 0), 'RUNNING', now(), coalesce(p_input_context, '{}'::jsonb)
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
     or v_existing.schema_version is distinct from p_schema_version
     or v_existing.runtime_version is distinct from p_runtime_version
     or v_existing.environment is distinct from p_environment
     or v_existing.task_title is distinct from p_task_title
     or v_existing.runtime_backend is distinct from p_runtime_backend then
    raise exception 'run_id % already exists with different runtime identity', p_run_id;
  end if;

  return v_existing.research_run_id;
end;
$$;

create or replace function public.runtime_finish_run(
  p_run_id text,
  p_status text,
  p_output_count integer default 0,
  p_error_count integer default 0,
  p_output_summary jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_run public.research_runs%rowtype;
begin
  if p_status not in ('COMPLETE', 'FAILED', 'NO_OP') then
    raise exception 'unsupported terminal run status: %', p_status;
  end if;

  if coalesce(p_output_count, 0) < 0 or coalesce(p_error_count, 0) < 0 then
    raise exception 'run counts must be nonnegative';
  end if;

  select *
    into v_run
  from public.research_runs
  where run_id = p_run_id
  for update;

  if not found then
    raise exception 'unknown run_id: %', p_run_id;
  end if;

  if v_run.finished_at is not null then
    if v_run.status is distinct from p_status
       or v_run.output_count is distinct from coalesce(p_output_count, 0)
       or v_run.error_count is distinct from coalesce(p_error_count, 0)
       or v_run.output_summary is distinct from coalesce(p_output_summary, '{}'::jsonb) then
      raise exception 'run_id % already finished with different terminal result', p_run_id;
    end if;
    return v_run.research_run_id;
  end if;

  update public.research_runs
  set status = p_status,
      finished_at = now(),
      output_count = coalesce(p_output_count, 0),
      error_count = coalesce(p_error_count, 0),
      output_summary = coalesce(p_output_summary, '{}'::jsonb)
  where research_run_id = v_run.research_run_id;

  return v_run.research_run_id;
end;
$$;

create or replace function public.runtime_transition_opportunity(
  p_opportunity_id uuid,
  p_research_run_id uuid,
  p_idempotency_key text,
  p_actor text,
  p_event_type text,
  p_expected_stage workflow_stage,
  p_expected_disposition machine_disposition,
  p_to_stage workflow_stage,
  p_to_disposition machine_disposition,
  p_reason text default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_opp public.opportunities%rowtype;
  v_event public.workflow_events%rowtype;
  v_event_id uuid;
begin
  if nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'idempotency_key is required';
  end if;

  if nullif(btrim(p_actor), '') is null or nullif(btrim(p_event_type), '') is null then
    raise exception 'actor and event_type are required';
  end if;

  select *
    into v_event
  from public.workflow_events
  where idempotency_key = p_idempotency_key;

  if found then
    if v_event.opportunity_id is distinct from p_opportunity_id
       or v_event.to_stage is distinct from p_to_stage
       or v_event.to_disposition is distinct from p_to_disposition
       or v_event.event_type is distinct from p_event_type then
      raise exception 'idempotency_key % already represents a different transition', p_idempotency_key;
    end if;
    return v_event.event_id;
  end if;

  select *
    into v_opp
  from public.opportunities
  where opportunity_id = p_opportunity_id
  for update;

  if not found then
    raise exception 'unknown opportunity_id: %', p_opportunity_id;
  end if;

  if p_expected_stage is not null and v_opp.current_stage is distinct from p_expected_stage then
    raise exception 'stage precondition failed for %: expected %, actual %',
      p_opportunity_id, p_expected_stage, v_opp.current_stage;
  end if;

  if p_expected_disposition is not null
     and v_opp.current_machine_disposition is distinct from p_expected_disposition then
    raise exception 'disposition precondition failed for %: expected %, actual %',
      p_opportunity_id, p_expected_disposition, v_opp.current_machine_disposition;
  end if;

  insert into public.workflow_events(
    opportunity_id, research_run_id, event_type,
    from_stage, to_stage, from_disposition, to_disposition,
    actor, reason, idempotency_key, payload
  )
  values (
    p_opportunity_id, p_research_run_id, p_event_type,
    v_opp.current_stage, p_to_stage,
    v_opp.current_machine_disposition, p_to_disposition,
    p_actor, p_reason, p_idempotency_key, coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning event_id into v_event_id;

  if v_event_id is null then
    select *
      into v_event
    from public.workflow_events
    where idempotency_key = p_idempotency_key;

    if not found then
      raise exception 'idempotent transition conflict could not be read back: %', p_idempotency_key;
    end if;

    if v_event.opportunity_id is distinct from p_opportunity_id
       or v_event.to_stage is distinct from p_to_stage
       or v_event.to_disposition is distinct from p_to_disposition
       or v_event.event_type is distinct from p_event_type then
      raise exception 'idempotency_key % already represents a different transition', p_idempotency_key;
    end if;

    return v_event.event_id;
  end if;

  update public.opportunities
  set current_stage = p_to_stage,
      current_machine_disposition = p_to_disposition,
      last_seen_at = now()
  where opportunity_id = p_opportunity_id;

  return v_event_id;
end;
$$;

comment on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) is
  'Idempotently starts one canonical worker invocation and rejects runtime-identity drift for a reused run_id.';

comment on function public.runtime_finish_run(text,text,integer,integer,jsonb) is
  'Idempotently finalizes one canonical worker invocation; conflicting terminal replays fail closed.';

comment on function public.runtime_transition_opportunity(uuid,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,machine_disposition,text,jsonb) is
  'Atomic, idempotent opportunity state transition with workflow-event evidence and optimistic preconditions.';

revoke execute on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) from public;
revoke execute on function public.runtime_finish_run(text,text,integer,integer,jsonb) from public;
revoke execute on function public.runtime_transition_opportunity(uuid,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,machine_disposition,text,jsonb) from public;

do $runtime_api_roles$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) from anon';
    execute 'revoke execute on function public.runtime_finish_run(text,text,integer,integer,jsonb) from anon';
    execute 'revoke execute on function public.runtime_transition_opportunity(uuid,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,machine_disposition,text,jsonb) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) from authenticated';
    execute 'revoke execute on function public.runtime_finish_run(text,text,integer,integer,jsonb) from authenticated';
    execute 'revoke execute on function public.runtime_transition_opportunity(uuid,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,machine_disposition,text,jsonb) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) to service_role';
    execute 'grant execute on function public.runtime_finish_run(text,text,integer,integer,jsonb) to service_role';
    execute 'grant execute on function public.runtime_transition_opportunity(uuid,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,machine_disposition,text,jsonb) to service_role';
  end if;
end
$runtime_api_roles$;
