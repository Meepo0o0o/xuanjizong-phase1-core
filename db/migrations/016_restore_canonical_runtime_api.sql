-- 016_restore_canonical_runtime_api.sql
-- Restore the existing Persistence Contract V1 runtime-start API after the
-- optional environment-guard experiment revoked it from the normal runtime role.

do $restore_runtime_begin_run$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.runtime_begin_run(text,text,text,text,text,text,text,text,text,integer,jsonb) to service_role';
  end if;
end
$restore_runtime_begin_run$;
