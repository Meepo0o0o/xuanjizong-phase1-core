-- 013_runtime_stage_commit_api.sql
-- Atomic stage-result persistence boundary for unattended Phase 1 workers.
-- Business judgment stays in worker contracts; this function only persists a
-- caller-supplied structured result, evidence graph, assets, and state transition.

create or replace function public.runtime_commit_stage_result(
  p_run_id text,
  p_opportunity_id uuid,
  p_idempotency_key text,
  p_actor text,
  p_event_type text,
  p_expected_stage workflow_stage,
  p_expected_disposition machine_disposition,
  p_stage workflow_stage,
  p_to_stage workflow_stage,
  p_to_disposition machine_disposition,
  p_analysis jsonb,
  p_evidence jsonb default '[]'::jsonb,
  p_interpretations jsonb default '[]'::jsonb,
  p_assets jsonb default '[]'::jsonb,
  p_reason text default null,
  p_event_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_run public.research_runs%rowtype;
  v_opp public.opportunities%rowtype;
  v_existing_event public.workflow_events%rowtype;
  v_analysis public.stage_analyses%rowtype;
  v_analysis_id uuid;
  v_event_id uuid;

  v_source jsonb;
  v_claim jsonb;
  v_interpretation jsonb;
  v_claim_ref jsonb;
  v_impact jsonb;
  v_asset jsonb;

  v_source_id uuid;
  v_claim_id uuid;
  v_interpretation_id uuid;
  v_asset_id uuid;
  v_claim_key text;
  v_ref_key text;
  v_claim_map jsonb := '{}'::jsonb;

  v_source_count integer := 0;
  v_claim_count integer := 0;
  v_interpretation_count integer := 0;
  v_impact_count integer := 0;
  v_asset_count integer := 0;
begin
  if nullif(btrim(p_run_id), '') is null
     or nullif(btrim(p_idempotency_key), '') is null
     or nullif(btrim(p_actor), '') is null
     or nullif(btrim(p_event_type), '') is null then
    raise exception 'run_id, idempotency_key, actor and event_type are required';
  end if;

  if p_analysis is null or jsonb_typeof(p_analysis) <> 'object' then
    raise exception 'analysis payload must be a JSON object';
  end if;

  if jsonb_typeof(coalesce(p_evidence, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_interpretations, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_assets, '[]'::jsonb)) <> 'array' then
    raise exception 'evidence, interpretations and assets must be JSON arrays';
  end if;

  -- Serialize identical logical operations before checking replay state.
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key, 0));

  select *
    into v_existing_event
  from public.workflow_events
  where idempotency_key = p_idempotency_key;

  if found then
    if v_existing_event.opportunity_id is distinct from p_opportunity_id
       or v_existing_event.to_stage is distinct from p_to_stage
       or v_existing_event.to_disposition is distinct from p_to_disposition
       or v_existing_event.event_type is distinct from p_event_type
       or v_existing_event.payload->>'analysis_stage' is distinct from p_stage::text then
      raise exception 'idempotency_key % already represents a different stage result', p_idempotency_key;
    end if;

    if nullif(v_existing_event.payload->>'analysis_id', '') is null then
      raise exception 'idempotency_key % was used by a non-stage transition', p_idempotency_key;
    end if;

    return jsonb_build_object(
      'replayed', true,
      'analysis_id', v_existing_event.payload->>'analysis_id',
      'event_id', v_existing_event.event_id,
      'stage', p_stage::text
    );
  end if;

  select *
    into v_run
  from public.research_runs
  where run_id = p_run_id
  for update;

  if not found then
    raise exception 'unknown run_id: %', p_run_id;
  end if;

  if v_run.status <> 'RUNNING' then
    raise exception 'run_id % is not RUNNING', p_run_id;
  end if;

  if v_run.worker_key is distinct from p_actor then
    raise exception 'run_id % belongs to worker_key %, not %', p_run_id, v_run.worker_key, p_actor;
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

  v_analysis := jsonb_populate_record(null::public.stage_analyses, p_analysis);
  v_analysis.analysis_id := gen_random_uuid();
  v_analysis.opportunity_id := p_opportunity_id;
  v_analysis.research_run_id := v_run.research_run_id;
  v_analysis.stage := p_stage;
  v_analysis.execution_fit := coalesce(v_analysis.execution_fit, 'UNKNOWN'::fit_level);
  v_analysis.asset_fit := coalesce(v_analysis.asset_fit, 'UNKNOWN'::fit_level);
  v_analysis.competitive_fit := coalesce(v_analysis.competitive_fit, 'UNKNOWN'::fit_level);
  v_analysis.translation_cost := coalesce(v_analysis.translation_cost, 'UNKNOWN'::translation_cost_level);
  v_analysis.substitution_case_status := coalesce(v_analysis.substitution_case_status, 'UNKNOWN'::substitution_case_status);
  v_analysis.standard_winner_archetypes := coalesce(v_analysis.standard_winner_archetypes, '[]'::jsonb);
  v_analysis.blocking_reasons := coalesce(v_analysis.blocking_reasons, '[]'::jsonb);
  v_analysis.residual_unknowns := coalesce(v_analysis.residual_unknowns, '[]'::jsonb);
  v_analysis.decision_changing_evidence := coalesce(v_analysis.decision_changing_evidence, '[]'::jsonb);
  v_analysis.decision_sequence := coalesce(v_analysis.decision_sequence, '[]'::jsonb);
  v_analysis.review_ready := coalesce(v_analysis.review_ready, false);
  v_analysis.created_at := coalesce(v_analysis.created_at, now());
  v_analysis.metadata := coalesce(v_analysis.metadata, '{}'::jsonb);

  if v_analysis.machine_disposition is not null
     and v_analysis.machine_disposition is distinct from p_to_disposition then
    raise exception 'analysis machine_disposition % conflicts with transition disposition %',
      v_analysis.machine_disposition, p_to_disposition;
  end if;
  v_analysis.machine_disposition := p_to_disposition;

  insert into public.stage_analyses
  select (v_analysis).*;

  v_analysis_id := v_analysis.analysis_id;

  -- Evidence payload: sources with nested claims. Claim keys are local to this
  -- stage commit and are used by interpretations/assets below.
  for v_source in
    select value from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb))
  loop
    if nullif(btrim(v_source->>'url'), '') is null
       or nullif(btrim(v_source->>'source_type'), '') is null then
      raise exception 'each evidence source requires url and source_type';
    end if;

    v_source_id := null;

    if nullif(v_source->>'content_hash', '') is not null then
      select source_id
        into v_source_id
      from public.sources
      where coalesce(canonical_url, url) =
            coalesce(nullif(v_source->>'canonical_url', ''), v_source->>'url')
        and content_hash = v_source->>'content_hash'
      order by retrieved_at desc
      limit 1;
    end if;

    if v_source_id is null then
      insert into public.sources(
        url, canonical_url, publisher, source_type, authority, title,
        published_at, retrieved_at, content_hash, artifact_uri, metadata
      )
      values (
        v_source->>'url',
        nullif(v_source->>'canonical_url', ''),
        nullif(v_source->>'publisher', ''),
        v_source->>'source_type',
        coalesce(nullif(v_source->>'authority', '')::source_authority, 'UNVERIFIED'::source_authority),
        nullif(v_source->>'title', ''),
        nullif(v_source->>'published_at', '')::timestamptz,
        coalesce(nullif(v_source->>'retrieved_at', '')::timestamptz, now()),
        nullif(v_source->>'content_hash', ''),
        nullif(v_source->>'artifact_uri', ''),
        case when jsonb_typeof(v_source->'metadata') = 'object' then v_source->'metadata' else '{}'::jsonb end
      )
      returning source_id into v_source_id;
    end if;

    v_source_count := v_source_count + 1;

    for v_claim in
      select value
      from jsonb_array_elements(
        case when jsonb_typeof(v_source->'claims') = 'array' then v_source->'claims' else '[]'::jsonb end
      )
    loop
      v_claim_key := nullif(btrim(v_claim->>'claim_key'), '');

      if v_claim_key is null
         or nullif(btrim(v_claim->>'claim_type'), '') is null
         or nullif(btrim(v_claim->>'claim_text'), '') is null then
        raise exception 'each claim requires claim_key, claim_type and claim_text';
      end if;

      if v_claim_map ? v_claim_key then
        raise exception 'duplicate claim_key in payload: %', v_claim_key;
      end if;

      insert into public.claims(
        source_id, company_id, opportunity_id, claim_type, claim_text,
        evidence_strength, published_context, valid_from, valid_to, metadata
      )
      values (
        v_source_id,
        v_opp.company_id,
        p_opportunity_id,
        v_claim->>'claim_type',
        v_claim->>'claim_text',
        nullif(v_claim->>'evidence_strength', ''),
        nullif(v_claim->>'published_context', ''),
        nullif(v_claim->>'valid_from', '')::timestamptz,
        nullif(v_claim->>'valid_to', '')::timestamptz,
        case when jsonb_typeof(v_claim->'metadata') = 'object' then v_claim->'metadata' else '{}'::jsonb end
      )
      returning claim_id into v_claim_id;

      v_claim_map := v_claim_map || jsonb_build_object(v_claim_key, v_claim_id::text);
      v_claim_count := v_claim_count + 1;
    end loop;
  end loop;

  for v_interpretation in
    select value from jsonb_array_elements(coalesce(p_interpretations, '[]'::jsonb))
  loop
    if nullif(btrim(v_interpretation->>'interpretation_type'), '') is null
       or nullif(btrim(v_interpretation->>'interpretation_text'), '') is null then
      raise exception 'each interpretation requires interpretation_type and interpretation_text';
    end if;

    insert into public.interpretations(
      analysis_id, interpretation_type, interpretation_text,
      confidence, created_at, metadata
    )
    values (
      v_analysis_id,
      v_interpretation->>'interpretation_type',
      v_interpretation->>'interpretation_text',
      nullif(v_interpretation->>'confidence', ''),
      coalesce(nullif(v_interpretation->>'created_at', '')::timestamptz, now()),
      case when jsonb_typeof(v_interpretation->'metadata') = 'object' then v_interpretation->'metadata' else '{}'::jsonb end
    )
    returning interpretation_id into v_interpretation_id;

    v_interpretation_count := v_interpretation_count + 1;

    for v_claim_ref in
      select value
      from jsonb_array_elements(
        case when jsonb_typeof(v_interpretation->'claim_refs') = 'array'
             then v_interpretation->'claim_refs' else '[]'::jsonb end
      )
    loop
      v_ref_key := nullif(btrim(v_claim_ref->>'claim_key'), '');
      if v_ref_key is null or not (v_claim_map ? v_ref_key) then
        raise exception 'interpretation references unknown claim_key: %', v_ref_key;
      end if;

      insert into public.interpretation_claims(
        interpretation_id, claim_id, relationship, note
      )
      values (
        v_interpretation_id,
        (v_claim_map->>v_ref_key)::uuid,
        coalesce(nullif(v_claim_ref->>'relationship', '')::evidence_relation, 'SUPPORTS'::evidence_relation),
        nullif(v_claim_ref->>'note', '')
      );
    end loop;

    for v_impact in
      select value
      from jsonb_array_elements(
        case when jsonb_typeof(v_interpretation->'impacts') = 'array'
             then v_interpretation->'impacts' else '[]'::jsonb end
      )
    loop
      if nullif(btrim(v_impact->>'impact_type'), '') is null
         or nullif(btrim(v_impact->>'impact_text'), '') is null then
        raise exception 'each decision impact requires impact_type and impact_text';
      end if;

      insert into public.decision_impacts(
        analysis_id, interpretation_id, impact_type, impact_text,
        direction, severity, decision_changing, created_at, metadata
      )
      values (
        v_analysis_id,
        v_interpretation_id,
        v_impact->>'impact_type',
        v_impact->>'impact_text',
        nullif(v_impact->>'direction', ''),
        nullif(v_impact->>'severity', ''),
        coalesce((v_impact->>'decision_changing')::boolean, false),
        coalesce(nullif(v_impact->>'created_at', '')::timestamptz, now()),
        case when jsonb_typeof(v_impact->'metadata') = 'object' then v_impact->'metadata' else '{}'::jsonb end
      );

      v_impact_count := v_impact_count + 1;
    end loop;
  end loop;

  for v_asset in
    select value from jsonb_array_elements(coalesce(p_assets, '[]'::jsonb))
  loop
    if nullif(btrim(v_asset->>'asset_name'), '') is null
       or nullif(btrim(v_asset->>'asset_class'), '') is null then
      raise exception 'each production asset requires asset_name and asset_class';
    end if;

    insert into public.production_assets(
      opportunity_id, analysis_id, asset_name, asset_class, rationale,
      user_evidence, coverage_status, evidence_quality, learnability_hireability
    )
    values (
      p_opportunity_id,
      v_analysis_id,
      v_asset->>'asset_name',
      (v_asset->>'asset_class')::asset_requirement_strength,
      nullif(v_asset->>'rationale', ''),
      nullif(v_asset->>'user_evidence', ''),
      nullif(v_asset->>'coverage_status', ''),
      nullif(v_asset->>'evidence_quality', ''),
      nullif(v_asset->>'learnability_hireability', '')
    )
    returning production_asset_id into v_asset_id;

    v_asset_count := v_asset_count + 1;

    for v_claim_ref in
      select value
      from jsonb_array_elements(
        case when jsonb_typeof(v_asset->'claim_refs') = 'array'
             then v_asset->'claim_refs' else '[]'::jsonb end
      )
    loop
      v_ref_key := nullif(btrim(v_claim_ref->>'claim_key'), '');
      if v_ref_key is null or not (v_claim_map ? v_ref_key) then
        raise exception 'production asset references unknown claim_key: %', v_ref_key;
      end if;

      insert into public.production_asset_claims(
        production_asset_id, claim_id, relationship
      )
      values (
        v_asset_id,
        (v_claim_map->>v_ref_key)::uuid,
        coalesce(nullif(v_claim_ref->>'relationship', '')::evidence_relation, 'SUPPORTS'::evidence_relation)
      );
    end loop;
  end loop;

  v_event_id := public.runtime_transition_opportunity(
    p_opportunity_id,
    v_run.research_run_id,
    p_idempotency_key,
    p_actor,
    p_event_type,
    p_expected_stage,
    p_expected_disposition,
    p_to_stage,
    p_to_disposition,
    p_reason,
    coalesce(p_event_payload, '{}'::jsonb)
      || jsonb_build_object(
           'analysis_id', v_analysis_id::text,
           'analysis_stage', p_stage::text
         )
  );

  return jsonb_build_object(
    'replayed', false,
    'analysis_id', v_analysis_id,
    'event_id', v_event_id,
    'stage', p_stage::text,
    'source_count', v_source_count,
    'claim_count', v_claim_count,
    'interpretation_count', v_interpretation_count,
    'impact_count', v_impact_count,
    'asset_count', v_asset_count
  );
end;
$$;

comment on function public.runtime_commit_stage_result(
  text,uuid,text,text,text,workflow_stage,machine_disposition,
  workflow_stage,workflow_stage,machine_disposition,
  jsonb,jsonb,jsonb,jsonb,text,jsonb
) is
  'Atomically persists one structured stage analysis, normalized evidence graph, production assets, and the idempotent opportunity transition.';

revoke execute on function public.runtime_commit_stage_result(
  text,uuid,text,text,text,workflow_stage,machine_disposition,
  workflow_stage,workflow_stage,machine_disposition,
  jsonb,jsonb,jsonb,jsonb,text,jsonb
) from public;

do $runtime_stage_commit_roles$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function public.runtime_commit_stage_result(text,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,workflow_stage,machine_disposition,jsonb,jsonb,jsonb,jsonb,text,jsonb) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function public.runtime_commit_stage_result(text,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,workflow_stage,machine_disposition,jsonb,jsonb,jsonb,jsonb,text,jsonb) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.runtime_commit_stage_result(text,uuid,text,text,text,workflow_stage,machine_disposition,workflow_stage,workflow_stage,machine_disposition,jsonb,jsonb,jsonb,jsonb,text,jsonb) to service_role';
  end if;
end
$runtime_stage_commit_roles$;
