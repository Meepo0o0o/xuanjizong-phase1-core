-- 008_runtime_identity_v2.sql
-- Explicit runtime identity smoke test. All fixture writes are rolled back.

begin;

do $test$
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
    'Renamed display title is not identity',
    'ScheduledTasks',
    'TEST',
    0,
    '{"fixture":true}'::jsonb
  );

  if v_run1 is distinct from v_run2 then
    raise exception 'RUNTIME IDENTITY V2 FAIL: exact identity replay returned a different run';
  end if;

  select *
    into v_row
  from public.research_runs
  where research_run_id = v_run1;

  if v_row.worker_key is distinct from 'XIANYA'
     or v_row.contract_version is distinct from 'xianya-contract-v2'
     or v_row.release_version is distinct from 'phase1-v0.2.0'
     or v_row.deployment_id is distinct from 'xianya-test-fixture-001'
     or v_row.task_id is distinct from 'task-runtime-identity-fixture'
     or v_row.runtime_backend is distinct from 'ScheduledTasks'
     or v_row.environment is distinct from 'TEST' then
    raise exception 'RUNTIME IDENTITY V2 FAIL: explicit identity was not persisted correctly';
  end if;

  if v_row.schema_version is distinct from v_row.contract_version
     or v_row.runtime_version is distinct from v_row.release_version then
    raise exception 'RUNTIME IDENTITY V2 FAIL: legacy compatibility aliases drifted';
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
    raise exception 'RUNTIME IDENTITY V2 FAIL: release drift replay was accepted';
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
    raise exception 'RUNTIME IDENTITY V2 FAIL: deployment drift replay was accepted';
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
    raise exception 'RUNTIME IDENTITY V2 FAIL: scheduler task drift replay was accepted';
  end if;

  perform public.runtime_finish_run(
    'RUNTIME-IDENTITY-V2-SMOKE-001',
    'NO_OP',
    0,
    0,
    '{"fixture":"identity-v2-complete"}'::jsonb
  );
end
$test$;

rollback;
