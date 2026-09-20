-- 翰林院 PostgreSQL transactional smoke test
-- Safe: all fixture writes are rolled back.

begin;

insert into companies(company_id, canonical_name, normalized_name)
values ('00000000-0000-0000-0000-000000000101','SMOKE COMPANY','smoke-company');

insert into opportunities(
  opportunity_id,candidate_key,company_id,role_title,location,
  current_stage,current_machine_disposition,is_active
) values (
  '00000000-0000-0000-0000-000000000201',
  'smoke|role|sg|v1',
  '00000000-0000-0000-0000-000000000101',
  'Smoke Role','Singapore',
  'ZHONGSHU_DECISION','PRESENT_FOR_HUMAN',true
);

insert into research_runs(
  research_run_id,run_id,worker,worker_key,status,schema_version,
  runtime_version,task_title,runtime_backend,environment,input_count,output_count,error_count
) values (
  '00000000-0000-0000-0000-000000000301',
  'SMOKE-ZSS-001','中书省','ZHONGSHUSHENG','COMPLETE','zhongshusheng-v4',
  'V02','璇玑宗｜中书省 V02 PROD','PostgreSQL','TEST',1,1,0
);

insert into stage_analyses(
  analysis_id,opportunity_id,research_run_id,stage,
  role_essence,why_role_exists_now,employer_buying_thesis,
  operating_model,acquisition_burden,nonstandard_winner_path,
  structural_loss_case,research_status,evidence_exhaustion_status,
  intelligence_completeness,machine_disposition,review_ready
) values (
  '00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000301',
  'ZHONGSHU_DECISION',
  'Fixture role essence',
  'Fixture why-now',
  'Fixture buying thesis',
  'Fixture operating model',
  'MODERATE',
  'Fixture non-standard path',
  'Fixture structural loss',
  'RESEARCH_COMPLETE',
  'PUBLIC_EVIDENCE_EXHAUSTED',
  'DECISION_CRITICAL_UNKNOWN',
  'PRESENT_FOR_HUMAN',
  true
);

insert into sources(
  source_id,url,publisher,source_type,authority,title,content_hash
) values (
  '00000000-0000-0000-0000-000000000501',
  'https://example.invalid/smoke',
  'SMOKE COMPANY',
  'OFFICIAL_NEWSROOM',
  'PRIMARY_OFFICIAL',
  'Smoke Source',
  'smoke-hash-v1'
);

insert into claims(
  claim_id,source_id,company_id,opportunity_id,claim_type,claim_text,evidence_strength
) values (
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000501',
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000201',
  'WHY_NOW',
  'Fixture claim',
  'HIGH'
);

insert into interpretations(
  interpretation_id,analysis_id,interpretation_type,interpretation_text,confidence
) values (
  '00000000-0000-0000-0000-000000000701',
  '00000000-0000-0000-0000-000000000401',
  'EMPLOYER_BUYING_THESIS',
  'Fixture interpretation',
  'HIGH'
);

insert into interpretation_claims(interpretation_id,claim_id,relationship)
values (
  '00000000-0000-0000-0000-000000000701',
  '00000000-0000-0000-0000-000000000601',
  'SUPPORTS'
);

insert into decision_impacts(
  decision_impact_id,analysis_id,interpretation_id,impact_type,impact_text,direction,severity,decision_changing
) values (
  '00000000-0000-0000-0000-000000000801',
  '00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000701',
  'FIT',
  'Fixture decision impact',
  'POSITIVE',
  'MATERIAL',
  true
);

do $$
declare
  n integer;
begin
  select count(*) into n
  from kingslanding_pending
  where candidate_key='smoke|role|sg|v1';

  if n <> 1 then
    raise exception 'SMOKE FAIL: expected 1 Kingslanding row, got %', n;
  end if;

  select count(*) into n
  from interpretations i
  join interpretation_claims ic on ic.interpretation_id=i.interpretation_id
  join claims c on c.claim_id=ic.claim_id
  join sources s on s.source_id=c.source_id
  join decision_impacts di on di.interpretation_id=i.interpretation_id
  where i.analysis_id='00000000-0000-0000-0000-000000000401';

  if n <> 1 then
    raise exception 'SMOKE FAIL: evidence graph is broken';
  end if;
end $$;

rollback;
