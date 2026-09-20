-- Migration 006 — changelog and governance baseline enforcement

alter table system_changes
  add column if not exists changelog_required boolean not null default true;

alter table system_changes
  add column if not exists governance_profile text not null default 'engineering-governance-v1';

create table if not exists project_changelog_entries (
  entry_id uuid primary key default gen_random_uuid(),
  change_id text references system_changes(change_id) on delete set null,
  category text not null check (
    category in ('Added','Changed','Deprecated','Removed','Fixed','Security','Governance','Incident')
  ),
  summary text not null,
  details text,
  version_label text not null default 'Unreleased',
  effective_at timestamptz not null default now(),
  git_ref text,
  source_refs jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists project_changelog_change_idx
  on project_changelog_entries(change_id, effective_at desc);

create table if not exists engineering_governance_rules (
  rule_id text primary key,
  profile text not null default 'engineering-governance-v1',
  title text not null,
  requirement_level text not null check (requirement_level in ('MUST','SHOULD','MAY')),
  rule_text text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','SUPERSEDED','RETIRED')),
  source_refs jsonb not null default '[]'::jsonb,
  effective_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists governance_exceptions (
  exception_id text primary key,
  rule_id text not null references engineering_governance_rules(rule_id),
  scope text not null,
  rationale text not null,
  risk text not null,
  compensating_control text not null,
  owner text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','EXPIRED','CLOSED','REJECTED')),
  approved_by text not null,
  approved_at timestamptz not null default now(),
  expires_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb
);

create or replace view missing_project_changelog as
select
  c.change_id,
  c.title,
  c.change_class,
  c.status,
  c.changelog_required
from system_changes c
where c.changelog_required
  and not exists (
    select 1
    from project_changelog_entries e
    where e.change_id = c.change_id
  );

create or replace function enforce_change_complete_gate()
returns trigger
language plpgsql
as $$
declare
  open_impacts integer;
  missing_orders integer;
  open_orders integer;
  missing_log integer;
begin
  if new.status = 'COMPLETE' and old.status is distinct from 'COMPLETE' then
    select count(*) into open_impacts
    from change_impacts
    where change_id = new.change_id
      and status in ('PENDING','IMPLEMENTED','BLOCKED','DRIFT');

    select count(*) into missing_orders
    from missing_execution_work_orders
    where change_id = new.change_id;

    select count(*) into open_orders
    from execution_work_order_gate
    where change_id = new.change_id
      and gate_status not in ('ACCEPTED','CANCELLED');

    select count(*) into missing_log
    from missing_project_changelog
    where change_id = new.change_id;

    if open_impacts > 0 or missing_orders > 0 or open_orders > 0 or missing_log > 0 then
      raise exception
        'Change % cannot become COMPLETE: open_impacts=%, missing_work_orders=%, open_work_orders=%, missing_changelog=%',
        new.change_id, open_impacts, missing_orders, open_orders, missing_log;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_change_complete_gate on system_changes;
create trigger trg_enforce_change_complete_gate
before update on system_changes
for each row execute function enforce_change_complete_gate();

create or replace view engineering_governance_health as
select
  (select count(*) from engineering_governance_rules where status='ACTIVE') as active_rules,
  (select count(*) from governance_exceptions where status='ACTIVE' and expires_at > now()) as active_exceptions,
  (select count(*) from governance_exceptions where status='ACTIVE' and expires_at <= now()) as expired_but_open_exceptions,
  (select count(*) from missing_project_changelog) as changes_missing_changelog;

alter table project_changelog_entries enable row level security;
alter table engineering_governance_rules enable row level security;
alter table governance_exceptions enable row level security;

comment on table project_changelog_entries is
'Canonical structured changelog entries. CHANGELOG.md is the human-readable projection.';
comment on table engineering_governance_rules is
'Machine-readable registry of active engineering/project governance rules.';
comment on table governance_exceptions is
'Explicit, owned, time-bounded exceptions to governance MUST rules. Silent bypass is prohibited.';
