-- 004_runtime_persistence_api.sql
-- Safe foundation test: all fixture writes are rolled back.

begin;

insert into public.companies(company_id, canonical_name, normalized_name)
values ('00000000-0000-0000-0000-000000001101','RUNTIME API SMOKE','runtime-api-smoke');

insert into public.opportunities(
  opportunity_id,candidate_key,company_id,role_title,location,
  current_stage,current_machine_disposition,is_active
) values (
  '00000000-0000-0000-0000-000000001201',
  'runtime-api|role|test|v1',
  '00000000-0000-0000-0000-000000001101',
  'Runtime API Smoke Role','TEST',
  'DISCOVERY','FORWARD',true
);

do $test$
declare
  v_run1 uuid;
  v_run2 uuid;
  v_event1 uuid;
  v_event2 uuid;
  v_status text;
  v_stage workflow_stage;
  v_disp machine_disposition;
  v_n integer;
  v_failed boolean := false;
begin
  v_run1 := public.runtime_begin_run(
    'RUNTIME-API-SMOKE-001',
    '县衙',
    'XIANYA',
    'xianya-v2',
    'V02',
    'task-smoke',
    '璇玑宗｜县衙 V02 TEST',
    'PostgreSQL',
    'TEST',
    1,
    '{"fixture":true}'::jsonb
  );

  v_run2 := public.runtime_begin_run(
    'RUNTIME-API-SMOKE-001',
    '县衙',
    'XIANYA',
    'xianya-v2',
    'V02',
    'task-smoke',
    '璇玑宗｜县衙 V02 TEST',
    'PostgreSQL',
    'TEST',
    1,
    '{"fixture":true}'::jsonb
  );

  if v_run1 is distinct from v_run2 then
    raise exception 'RUNTIME API FAIL: begin_run replay returned a different run';
  end if;

  begin
    perform public.runtime_begin_run(
      'RUNTIME-API-SMOKE-001',
      '县衙',
      'XIANYA',
      'xianya-v2',
      'V99',
      'task-smoke',
      '璇玑宗｜县衙 V02 TEST',
      'PostgreSQL',
      'TEST',
      1,
      '{}'::jsonb
    );
  exception when others then
    v_failed := true;
  end;

  if not v_failed then
    raise exception 'RUNTIME API FAIL: identity drift replay was accepted';
  end if;

  v_event1 := public.runtime_transition_opportunity(
    '00000000-0000-0000-0000-000000001201',
    v_run1,
    'RUNTIME-API-SMOKE-TRANSITION-001',
    'XIANYA',
    'COUNTY_COMPLETE',
    'DISCOVERY',
    'FORWARD',
    'COUNTY_RESEARCH',
    'FORWARD',
    'fixture transition',
    '{"fixture":true}'::jsonb
  );

  v_event2 := public.runtime_transition_opportunity(
    '00000000-0000-0000-0000-000000001201',
    v_run1,
    'RUNTIME-API-SMOKE-TRANSITION-001',
    'XIANYA',
    'COUNTY_COMPLETE',
    'DISCOVERY',
    'FORWARD',
    'COUNTY_RESEARCH',
    'FORWARD',
    'fixture transition',
    '{"fixture":true}'::jsonb
  );

  if v_event1 is distinct from v_event2 then
    raise exception 'RUNTIME API FAIL: transition replay returned a different event';
  end if;

  select current_stage, current_machine_disposition
    into v_stage, v_disp
  from public.opportunities
  where opportunity_id='00000000-0000-0000-0000-000000001201';

  if v_stage <> 'COUNTY_RESEARCH' or v_disp <> 'FORWARD' then
    raise exception 'RUNTIME API FAIL: canonical opportunity state not updated';
  end if;

  select count(*) into v_n
  from public.workflow_events
  where idempotency_key='RUNTIME-API-SMOKE-TRANSITION-001';

  if v_n <> 1 then
    raise exception 'RUNTIME API FAIL: expected one workflow event, got %', v_n;
  end if;

  perform public.runtime_finish_run(
    'RUNTIME-API-SMOKE-001',
    'COMPLETE',
    1,
    0,
    '{"fixture":"complete"}'::jsonb
  );

  perform public.runtime_finish_run(
    'RUNTIME-API-SMOKE-001',
    'COMPLETE',
    1,
    0,
    '{"fixture":"complete"}'::jsonb
  );

  select status into v_status
  from public.research_runs
  where run_id='RUNTIME-API-SMOKE-001';

  if v_status <> 'COMPLETE' then
    raise exception 'RUNTIME API FAIL: run did not finish COMPLETE';
  end if;

  v_failed := false;
  begin
    perform public.runtime_finish_run(
      'RUNTIME-API-SMOKE-001',
      'FAILED',
      0,
      1,
      '{"fixture":"conflict"}'::jsonb
    );
  exception when others then
    v_failed := true;
  end;

  if not v_failed then
    raise exception 'RUNTIME API FAIL: conflicting terminal replay was accepted';
  end if;
end
$test$;


do $identity_v2_test$
declare
  v_run1 uuid;
  v_run2 uuid;
  v_row public.research_runs%rowtype;
  v_failed boolean;
begin
  v_run1 := public.runtime_begin_run_v2(
    'RUNTIME-IDENTITY-V2-SMOKE-001',
    '县衙',
    'XIANYA',
    'xianya-contract-v2',
    'phase1-v0.2.0',
    'xianya-test-fixture-001',
    'task-runtime-identity-fixture',
    '璇玑宗｜县衙 TEST fixture',
    'ScheduledTasks',
    'TEST',
    0,
    '{"fixture":true}'::jsonb
  );

  v_run2 := public.runtime_begin_run_v2(
    'RUNTIME-IDENTITY-V2-SMOKE-001',
    '县衙',
    'XIANYA',
    'xianya-contract-v2',
    'phase1-v0.2.0',
    'xianya-test-fixture-001',
    'task-runtime-identity-fixture',
    'Display title may change',
    'ScheduledTasks',
    'TEST',
    0,
    '{"fixture":true}'::jsonb
  );

  if v_run1 is distinct from v_run2 then
    raise exception 'RUNTIME IDENTITY V2 FAIL: replay returned a different run';
  end if;

  select * into v_row
  from public.research_runs
  where research_run_id = v_run1;

  if v_row.worker_key is distinct from 'XIANYA'
     or v_row.contract_version is distinct from 'xianya-contract-v2'
     or v_row.release_version is distinct from 'phase1-v0.2.0'
     or v_row.deployment_id is distinct from 'xianya-test-fixture-001'
     or v_row.task_id is distinct from 'task-runtime-identity-fixture'
     or v_row.runtime_backend is distinct from 'ScheduledTasks'
     or v_row.environment is distinct from 'TEST' then
    raise exception 'RUNTIME IDENTITY V2 FAIL: explicit identity was not persisted';
  end if;

  if v_row.schema_version is distinct from v_row.contract_version
     or v_row.runtime_version is distinct from v_row.release_version then
    raise exception 'RUNTIME IDENTITY V2 FAIL: legacy aliases drifted';
  end if;

  v_failed := false;
  begin
    perform public.runtime_begin_run_v2(
      'RUNTIME-IDENTITY-V2-SMOKE-001','县衙','XIANYA',
      'xianya-contract-v2','phase1-v9.9.9','xianya-test-fixture-001',
      'task-runtime-identity-fixture','fixture','ScheduledTasks','TEST',0,'{}'::jsonb
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'RUNTIME IDENTITY V2 FAIL: release drift was accepted';
  end if;

  v_failed := false;
  begin
    perform public.runtime_begin_run_v2(
      'RUNTIME-IDENTITY-V2-SMOKE-001','县衙','XIANYA',
      'xianya-contract-v2','phase1-v0.2.0','xianya-test-fixture-999',
      'task-runtime-identity-fixture','fixture','ScheduledTasks','TEST',0,'{}'::jsonb
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'RUNTIME IDENTITY V2 FAIL: deployment drift was accepted';
  end if;

  v_failed := false;
  begin
    perform public.runtime_begin_run_v2(
      'RUNTIME-IDENTITY-V2-SMOKE-001','县衙','XIANYA',
      'xianya-contract-v2','phase1-v0.2.0','xianya-test-fixture-001',
      'task-runtime-identity-other','fixture','ScheduledTasks','TEST',0,'{}'::jsonb
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'RUNTIME IDENTITY V2 FAIL: scheduler-task drift was accepted';
  end if;

  perform public.runtime_finish_run(
    'RUNTIME-IDENTITY-V2-SMOKE-001',
    'NO_OP',
    0,
    0,
    '{"fixture":"identity-v2-complete"}'::jsonb
  );
end
$identity_v2_test$;

rollback;
