-- 011_harden_exposed_public_schema.sql
-- Security baseline for the Supabase-exposed public schema.
-- Phase 1 is system-operated; anon/authenticated API access is not required.

do $enable_rls$
declare
  r record;
begin
  for r in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public'
  loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
  end loop;
end
$enable_rls$;

-- Postgres views use owner privileges by default. Force the five runtime/human
-- projections to obey the privileges and RLS context of the invoking role.
alter view public.xianya_queue set (security_invoker = true);
alter view public.zhongshu_queue set (security_invoker = true);
alter view public.open_watch_queue set (security_invoker = true);
alter view public.recent_eliminations_for_audit set (security_invoker = true);
alter view public.kingslanding_pending set (security_invoker = true);

-- No client-facing API is part of Phase 1. Remove the broad default Supabase
-- grants from anon/authenticated while preserving postgres/service_role access.
do $revoke_client_access$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all privileges on all tables in schema public from anon';
    execute 'revoke all privileges on all sequences in schema public from anon';
    execute 'revoke all privileges on all functions in schema public from anon';

    -- Repository migrations create application objects as postgres.
    execute 'alter default privileges for role postgres in schema public revoke all on tables from anon';
    execute 'alter default privileges for role postgres in schema public revoke all on sequences from anon';
    execute 'alter default privileges for role postgres in schema public revoke all on functions from anon';
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all privileges on all tables in schema public from authenticated';
    execute 'revoke all privileges on all sequences in schema public from authenticated';
    execute 'revoke all privileges on all functions in schema public from authenticated';

    execute 'alter default privileges for role postgres in schema public revoke all on tables from authenticated';
    execute 'alter default privileges for role postgres in schema public revoke all on sequences from authenticated';
    execute 'alter default privileges for role postgres in schema public revoke all on functions from authenticated';
  end if;
end
$revoke_client_access$;

comment on schema public is
  'Phase 1 application schema. No anon/authenticated client API access; system access only. Public tables use RLS as defense in depth.';
