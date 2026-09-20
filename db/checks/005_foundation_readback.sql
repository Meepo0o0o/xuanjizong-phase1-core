-- 005_foundation_readback.sql
-- Non-mutating foundation acceptance/readback checks.

do $foundation_readback$
declare
  n integer;
begin
  select count(*) into n
  from information_schema.tables
  where table_schema='public'
    and table_type='BASE TABLE'
    and table_name in ('companies','opportunities','research_runs','stage_analyses','workflow_events');

  if n <> 5 then
    raise exception 'FOUNDATION READBACK FAIL: required base tables missing';
  end if;

  select count(*) into n
  from information_schema.views
  where table_schema='public'
    and table_name in ('xianya_queue','zhongshu_queue','kingslanding_pending','open_watch_queue','recent_eliminations_for_audit');

  if n <> 5 then
    raise exception 'FOUNDATION READBACK FAIL: required runtime views missing';
  end if;

  select count(*) into n
  from information_schema.routines
  where routine_schema='public'
    and routine_name in ('runtime_begin_run','runtime_finish_run','runtime_transition_opportunity');

  if n <> 3 then
    raise exception 'FOUNDATION READBACK FAIL: shared runtime persistence API incomplete';
  end if;

  select count(*) into n
  from information_schema.tables
  where table_schema='public'
    and table_name in (
      'system_changes','change_impacts','execution_work_orders',
      'execution_returns','pm_acceptance_reviews',
      'engineering_governance_rules','project_changelog_entries',
      'runtime_desired_state','runtime_actual_observations',
      'runtime_deployment_generations','raw_import_records'
    );

  if n <> 0 then
    raise exception 'FOUNDATION READBACK FAIL: retired control-plane objects returned to public';
  end if;

  if not exists (
    select 1 from information_schema.schemata where schema_name='archive'
  ) then
    raise exception 'FOUNDATION READBACK FAIL: archive schema missing';
  end if;
end
$foundation_readback$;
