-- 012_remove_untracked_rls_event_trigger.sql
-- Remove non-canonical RLS auto-enable machinery observed in PROD outside migration history.
-- RLS is enforced explicitly by versioned migrations plus CI security checks.

drop event trigger if exists ensure_rls;
drop function if exists public.rls_auto_enable();

comment on schema public is
  'Phase 1 application schema. Security changes are migration-controlled and CI-verified; no hidden RLS event trigger is authoritative.';
