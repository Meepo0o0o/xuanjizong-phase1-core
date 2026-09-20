-- 006_security_baseline.sql
-- Non-mutating verification of the Phase 1 Supabase security baseline.

do $security_baseline$
declare
  n integer;
begin
  select count(*) into n
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity;

  if n <> 0 then
    raise exception 'SECURITY BASELINE FAIL: % public base tables do not have RLS enabled', n;
  end if;

  select count(*) into n
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public'
    and c.relkind = 'v'
    and c.relname in (
      'xianya_queue',
      'zhongshu_queue',
      'open_watch_queue',
      'recent_eliminations_for_audit',
      'kingslanding_pending'
    )
    and not (coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']);

  if n <> 0 then
    raise exception 'SECURITY BASELINE FAIL: % runtime views are not security_invoker', n;
  end if;

  select count(*) into n
  from pg_event_trigger
  where evtname = 'ensure_rls';

  if n <> 0 then
    raise exception 'SECURITY BASELINE FAIL: untracked ensure_rls event trigger exists';
  end if;

  select count(*) into n
  from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname = 'rls_auto_enable';

  if n <> 0 then
    raise exception 'SECURITY BASELINE FAIL: untracked public.rls_auto_enable function exists';
  end if;

  if exists (select 1 from pg_roles where rolname = 'anon') then
    select count(*) into n
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'anon';

    if n <> 0 then
      raise exception 'SECURITY BASELINE FAIL: anon retains % public relation grants', n;
    end if;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    select count(*) into n
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'authenticated';

    if n <> 0 then
      raise exception 'SECURITY BASELINE FAIL: authenticated retains % public relation grants', n;
    end if;
  end if;
end
$security_baseline$;
