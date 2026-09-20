-- 007_runtime_stage_commit_api.sql
-- Transactional/idempotency smoke test for runtime_commit_stage_result.
-- All fixture writes are rolled back.

begin;

insert into public.companies(company_id, canonical_name, normalized_name)
values (
  '00000000-0000-0000-0000-000000001301',
  'STAGE COMMIT API SMOKE',
  'stage-commit-api-smoke'
);

insert into public.opportunities(
  opportunity_id, candidate_key, company_id, role_title, location,
  current_stage, current_machine_disposition, is_active
) values (
  '00000000-0000-0000-0000-000000001302',
  'stage-commit-api|role|test|v1',
  '00000000-0000-0000-0000-000000001301',
  'Stage Commit API Smoke Role',
  'TEST',
  'DISCOVERY',
  'FORWARD',
  true
);

do $test$
declare
  v_run uuid;
  v_first jsonb;
  v_replay jsonb;
  v_stage workflow_stage;
  v_disp machine_disposition;
  v_n integer;
  v_failed boolean := false;
begin
  v_run := public.runtime_begin_run(
    'STAGE-COMMIT-API-SMOKE-001',
    '县衙',
    'XIANYA',
    'xianya-v2',
    'V02',
    'task-stage-commit-smoke',
    '璇玑宗｜县衙 V02 TEST',
    'PostgreSQL',
    'TEST',
    1,
    '{"fixture":true}'::jsonb
  );

  v_first := public.runtime_commit_stage_result(
    'STAGE-COMMIT-API-SMOKE-001',
    '00000000-0000-0000-0000-000000001302',
    'STAGE-COMMIT-API-SMOKE-TRANSITION-001',
    'XIANYA',
    'COUNTY_COMPLETE',
    'DISCOVERY',
    'FORWARD',
    'COUNTY_RESEARCH',
    'COUNTY_RESEARCH',
    'FORWARD',
    '{
      "employer_buying_thesis":"fixture thesis",
      "execution_fit":"MEDIUM",
      "asset_fit":"LOW",
      "competitive_fit":"LOW",
      "translation_cost":"HIGH",
      "translation_cost_rationale":"fixture translation cost",
      "prosecution_case":"fixture prosecution",
      "substitution_case_status":"NOT_EVIDENCED",
      "standard_winner_archetypes":["fixture-standard-winner"],
      "residual_unknowns":["fixture unknown"],
      "research_status":"RESEARCH_COMPLETE",
      "intelligence_completeness":"RESEARCH_COMPLETE",
      "review_ready":false,
      "metadata":{"fixture":true}
    }'::jsonb,
    '[
      {
        "url":"https://example.com/stage-commit-source",
        "canonical_url":"https://example.com/stage-commit-source",
        "publisher":"Example",
        "source_type":"official",
        "authority":"PRIMARY_OFFICIAL",
        "title":"Fixture source",
        "content_hash":"stage-commit-fixture-hash-001",
        "metadata":{"fixture":true},
        "claims":[
          {
            "claim_key":"claim-1",
            "claim_type":"ROLE_REQUIREMENT",
            "claim_text":"Fixture claim",
            "evidence_strength":"DIRECT",
            "metadata":{"fixture":true}
          }
        ]
      }
    ]'::jsonb,
    '[
      {
        "interpretation_type":"ASSET_GAP",
        "interpretation_text":"Fixture interpretation",
        "confidence":"HIGH",
        "claim_refs":[
          {"claim_key":"claim-1","relationship":"SUPPORTS"}
        ],
        "impacts":[
          {
            "impact_type":"COMPETITIVE_FIT",
            "impact_text":"Fixture negative impact",
            "direction":"NEGATIVE",
            "severity":"HIGH",
            "decision_changing":true
          }
        ]
      }
    ]'::jsonb,
    '[
      {
        "asset_name":"Fixture installed network",
        "asset_class":"MUST_BE_NATIVE",
        "rationale":"Fixture requirement",
        "coverage_status":"MISSING",
        "evidence_quality":"VERIFIED_DIRECT",
        "learnability_hireability":"LEARNABLE_NOT_REALISTICALLY_SUBSTITUTABLE",
        "claim_refs":[
          {"claim_key":"claim-1","relationship":"SUPPORTS"}
        ]
      }
    ]'::jsonb,
    'fixture stage commit',
    '{"fixture":true}'::jsonb
  );

  if coalesce((v_first->>'replayed')::boolean, true) then
    raise exception 'STAGE COMMIT API FAIL: first commit reported replay';
  end if;

  if v_first->>'analysis_id' is null or v_first->>'event_id' is null then
    raise exception 'STAGE COMMIT API FAIL: first commit did not return identifiers';
  end if;

  v_replay := public.runtime_commit_stage_result(
    'STAGE-COMMIT-API-SMOKE-001',
    '00000000-0000-0000-0000-000000001302',
    'STAGE-COMMIT-API-SMOKE-TRANSITION-001',
    'XIANYA',
    'COUNTY_COMPLETE',
    'DISCOVERY',
    'FORWARD',
    'COUNTY_RESEARCH',
    'COUNTY_RESEARCH',
    'FORWARD',
    '{"metadata":{"fixture":true}}'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb,
    'fixture replay',
    '{}'::jsonb
  );

  if not coalesce((v_replay->>'replayed')::boolean, false) then
    raise exception 'STAGE COMMIT API FAIL: replay not detected';
  end if;

  if v_first->>'analysis_id' is distinct from v_replay->>'analysis_id' then
    raise exception 'STAGE COMMIT API FAIL: replay returned a different analysis';
  end if;

  select count(*) into v_n
  from public.stage_analyses
  where opportunity_id='00000000-0000-0000-0000-000000001302'
    and stage='COUNTY_RESEARCH';
  if v_n <> 1 then
    raise exception 'STAGE COMMIT API FAIL: expected one analysis, got %', v_n;
  end if;

  select count(*) into v_n
  from public.claims
  where opportunity_id='00000000-0000-0000-0000-000000001302';
  if v_n <> 1 then
    raise exception 'STAGE COMMIT API FAIL: expected one claim, got %', v_n;
  end if;

  select count(*) into v_n
  from public.interpretations i
  join public.stage_analyses a on a.analysis_id=i.analysis_id
  where a.opportunity_id='00000000-0000-0000-0000-000000001302';
  if v_n <> 1 then
    raise exception 'STAGE COMMIT API FAIL: expected one interpretation, got %', v_n;
  end if;

  select count(*) into v_n
  from public.decision_impacts d
  join public.stage_analyses a on a.analysis_id=d.analysis_id
  where a.opportunity_id='00000000-0000-0000-0000-000000001302';
  if v_n <> 1 then
    raise exception 'STAGE COMMIT API FAIL: expected one decision impact, got %', v_n;
  end if;

  select count(*) into v_n
  from public.production_assets
  where opportunity_id='00000000-0000-0000-0000-000000001302';
  if v_n <> 1 then
    raise exception 'STAGE COMMIT API FAIL: expected one production asset, got %', v_n;
  end if;

  select current_stage, current_machine_disposition
    into v_stage, v_disp
  from public.opportunities
  where opportunity_id='00000000-0000-0000-0000-000000001302';

  if v_stage <> 'COUNTY_RESEARCH' or v_disp <> 'FORWARD' then
    raise exception 'STAGE COMMIT API FAIL: opportunity transition not committed';
  end if;

  v_failed := false;
  begin
    perform public.runtime_commit_stage_result(
      'STAGE-COMMIT-API-SMOKE-001',
      '00000000-0000-0000-0000-000000001302',
      'STAGE-COMMIT-API-SMOKE-TRANSITION-001',
      'XIANYA',
      'COUNTY_COMPLETE',
      'COUNTY_RESEARCH',
      'FORWARD',
      'COUNTY_RESEARCH',
      'COUNTY_RESEARCH',
      'FILTER',
      '{}'::jsonb,
      '[]'::jsonb,
      '[]'::jsonb,
      '[]'::jsonb,
      'conflicting replay',
      '{}'::jsonb
    );
  exception when others then
    v_failed := true;
  end;

  if not v_failed then
    raise exception 'STAGE COMMIT API FAIL: conflicting idempotent replay was accepted';
  end if;

  perform public.runtime_finish_run(
    'STAGE-COMMIT-API-SMOKE-001',
    'COMPLETE',
    1,
    0,
    '{"fixture":"complete"}'::jsonb
  );
end
$test$;

rollback;
