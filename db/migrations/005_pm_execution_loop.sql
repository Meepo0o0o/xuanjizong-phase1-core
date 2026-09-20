-- Migration 005 — PM execution delegation and acceptance loop
-- Enforces: impact analysis -> work order -> execution return -> PM acceptance -> closure.

alter table change_impacts
  add column if not exists execution_required boolean not null default false;

alter table change_impacts
  add column if not exists execution_owner text;

create table if not exists execution_work_orders (
  work_order_id text primary key,
  change_id text not null,
  component_key text not null,
  executor_layer text not null,
  dispatch_target text,
  task_title text not null,
  task_instructions text not null,
  desired_end_state text not null,
  acceptance_criteria jsonb not null default '[]'::jsonb,
  evidence_requirements jsonb not null default '[]'::jsonb,
  prohibited_mutations jsonb not null default '[]'::jsonb,
  rollback_condition text,
  dependency_notes text,
  status text not null default 'DRAFT' check (
    status in ('DRAFT','DISPATCHED','IN_PROGRESS','RETURNED','BLOCKED','REWORK','ACCEPTED','CANCELLED')
  ),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  dispatched_at timestamptz,
  started_at timestamptz,
  returned_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  foreign key (change_id, component_key)
    references change_impacts(change_id, component_key)
    on delete cascade
);

create table if not exists execution_returns (
  return_id uuid primary key default gen_random_uuid(),
  work_order_id text not null references execution_work_orders(work_order_id) on delete cascade,
  attempt_no integer not null check (attempt_no >= 1),
  executor_identity text,
  result_status text not null check (
    result_status in ('SUCCESS','PARTIAL','FAILED','BLOCKED')
  ),
  result_summary text not null,
  actions_performed jsonb not null default '[]'::jsonb,
  artifacts_touched jsonb not null default '[]'::jsonb,
  executor_readback_evidence jsonb not null default '{}'::jsonb,
  residual_issues jsonb not null default '[]'::jsonb,
  returned_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (work_order_id, attempt_no)
);

create table if not exists pm_acceptance_reviews (
  review_id uuid primary key default gen_random_uuid(),
  work_order_id text not null references execution_work_orders(work_order_id) on delete cascade,
  return_id uuid not null references execution_returns(return_id) on delete cascade,
  reviewer_role text not null default 'PM',
  decision text not null check (
    decision in ('ACCEPT','REWORK','REJECT','BLOCKED')
  ),
  expected_state jsonb not null default '{}'::jsonb,
  observed_state jsonb not null default '{}'::jsonb,
  independent_checks jsonb not null default '[]'::jsonb,
  review_summary text not null,
  reviewed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists execution_work_orders_change_idx
  on execution_work_orders(change_id, status);

create index if not exists execution_returns_work_order_idx
  on execution_returns(work_order_id, returned_at desc);

create index if not exists pm_acceptance_reviews_work_order_idx
  on pm_acceptance_reviews(work_order_id, reviewed_at desc);

create or replace view latest_execution_return as
select distinct on (work_order_id)
  return_id,
  work_order_id,
  attempt_no,
  executor_identity,
  result_status,
  result_summary,
  actions_performed,
  artifacts_touched,
  executor_readback_evidence,
  residual_issues,
  returned_at,
  metadata
from execution_returns
order by work_order_id, attempt_no desc, returned_at desc;

create or replace view latest_pm_acceptance as
select distinct on (work_order_id)
  review_id,
  work_order_id,
  return_id,
  reviewer_role,
  decision,
  expected_state,
  observed_state,
  independent_checks,
  review_summary,
  reviewed_at,
  metadata
from pm_acceptance_reviews
order by work_order_id, reviewed_at desc;

create or replace view execution_work_order_gate as
select
  w.work_order_id,
  w.change_id,
  w.component_key,
  w.executor_layer,
  w.dispatch_target,
  w.task_title,
  w.status,
  w.attempt_count,
  r.return_id,
  r.attempt_no as returned_attempt_no,
  r.result_status as executor_result_status,
  r.returned_at,
  a.review_id,
  a.decision as pm_decision,
  a.reviewed_at,
  case
    when w.status = 'CANCELLED' then 'CANCELLED'
    when w.status = 'ACCEPTED' and a.decision = 'ACCEPT' and r.return_id is not null then 'ACCEPTED'
    when w.status = 'ACCEPTED' and (a.decision is distinct from 'ACCEPT' or r.return_id is null) then 'INVALID_ACCEPTED_STATE'
    when r.return_id is not null and a.review_id is null then 'AWAITING_PM_ACCEPTANCE'
    when a.decision = 'REWORK' then 'REWORK_REQUIRED'
    when a.decision in ('REJECT','BLOCKED') then 'BLOCKED'
    when w.status in ('DRAFT','DISPATCHED','IN_PROGRESS','RETURNED','REWORK','BLOCKED') then w.status
    else 'UNVERIFIED'
  end as gate_status
from execution_work_orders w
left join latest_execution_return r using (work_order_id)
left join latest_pm_acceptance a using (work_order_id);

create or replace view missing_execution_work_orders as
select
  i.change_id,
  i.component_key,
  i.component_type,
  i.impact_summary,
  i.required_action,
  i.execution_owner
from change_impacts i
where i.execution_required
  and i.status <> 'NOT_APPLICABLE'
  and not exists (
    select 1
    from execution_work_orders w
    where w.change_id = i.change_id
      and w.component_key = i.component_key
      and w.status <> 'CANCELLED'
  );

create or replace view pm_change_lifecycle_status as
select
  c.change_id,
  c.phase,
  c.title,
  c.change_class,
  c.status as change_status,
  (select count(*) from change_impacts i where i.change_id=c.change_id) as impact_count,
  (select count(*) from change_impacts i where i.change_id=c.change_id and i.status in ('PENDING','IMPLEMENTED','BLOCKED','DRIFT')) as open_impact_count,
  (select count(*) from change_impacts i where i.change_id=c.change_id and i.execution_required and i.status <> 'NOT_APPLICABLE') as execution_required_count,
  (select count(*) from missing_execution_work_orders m where m.change_id=c.change_id) as missing_work_order_count,
  (select count(*) from execution_work_orders w where w.change_id=c.change_id and w.status <> 'CANCELLED') as work_order_count,
  (select count(*) from execution_work_order_gate g where g.change_id=c.change_id and g.gate_status='ACCEPTED') as accepted_work_order_count,
  (select count(*) from execution_work_order_gate g where g.change_id=c.change_id and g.gate_status not in ('ACCEPTED','CANCELLED')) as open_work_order_count,
  case
    when (select count(*) from change_impacts i where i.change_id=c.change_id) = 0
      then 'BLOCKED_NO_IMPACT_ANALYSIS'
    when (select count(*) from change_impacts i where i.change_id=c.change_id and i.status in ('PENDING','IMPLEMENTED','BLOCKED','DRIFT')) > 0
      then 'BLOCKED_IMPACTS'
    when (select count(*) from missing_execution_work_orders m where m.change_id=c.change_id) > 0
      then 'BLOCKED_MISSING_WORK_ORDERS'
    when (select count(*) from execution_work_order_gate g where g.change_id=c.change_id and g.gate_status not in ('ACCEPTED','CANCELLED')) > 0
      then 'BLOCKED_EXECUTION_OR_ACCEPTANCE'
    else 'READY_FOR_CHANGE_CLOSURE'
  end as lifecycle_gate
from system_changes c;

create or replace function enforce_work_order_return_contract()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'RETURNED' and old.status is distinct from 'RETURNED' then
    if not exists (
      select 1 from execution_returns r
      where r.work_order_id = new.work_order_id
    ) then
      raise exception 'Work order % cannot become RETURNED without an execution return', new.work_order_id;
    end if;
  end if;

  if new.status = 'ACCEPTED' and old.status is distinct from 'ACCEPTED' then
    if not exists (
      select 1
      from pm_acceptance_reviews a
      join execution_returns r on r.return_id = a.return_id
      where a.work_order_id = new.work_order_id
        and a.decision = 'ACCEPT'
        and r.work_order_id = new.work_order_id
    ) then
      raise exception 'Work order % cannot become ACCEPTED without PM ACCEPT review of an execution return', new.work_order_id;
    end if;
  end if;

  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_enforce_work_order_return_contract on execution_work_orders;
create trigger trg_enforce_work_order_return_contract
before update on execution_work_orders
for each row execute function enforce_work_order_return_contract();

create or replace function enforce_change_complete_gate()
returns trigger
language plpgsql
as $$
declare
  open_impacts integer;
  missing_orders integer;
  open_orders integer;
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

    if open_impacts > 0 or missing_orders > 0 or open_orders > 0 then
      raise exception
        'Change % cannot become COMPLETE: open_impacts=%, missing_work_orders=%, open_work_orders=%',
        new.change_id, open_impacts, missing_orders, open_orders;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_change_complete_gate on system_changes;
create trigger trg_enforce_change_complete_gate
before update on system_changes
for each row execute function enforce_change_complete_gate();

alter table execution_work_orders enable row level security;
alter table execution_returns enable row level security;
alter table pm_acceptance_reviews enable row level security;

comment on table execution_work_orders is
'PM-issued implementation tasks. A material mutation is not considered executed until an executor return exists and PM accepts it.';

comment on table execution_returns is
'Execution-layer returns. SUCCESS is evidence submission, not PM acceptance.';

comment on table pm_acceptance_reviews is
'Independent PM verification and disposition of executor returns.';

comment on view pm_change_lifecycle_status is
'End-to-end PM gate: impacts -> work orders -> executor returns -> PM acceptance -> change closure.';
