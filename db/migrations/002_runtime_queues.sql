-- Migration 002 — runtime worker queues

create or replace view xianya_queue as
select
  o.opportunity_id,
  o.candidate_key,
  c.canonical_name as company,
  o.role_title,
  o.location,
  o.requisition_id,
  o.official_url,
  o.source_url,
  o.opening_state,
  d.analysis_id as discovery_analysis_id,
  d.created_at as discovery_created_at,
  d.metadata as discovery_metadata
from opportunities o
join companies c on c.company_id=o.company_id
join lateral (
  select a.*
  from stage_analyses a
  where a.opportunity_id=o.opportunity_id
    and a.stage='DISCOVERY'
  order by a.created_at desc
  limit 1
) d on true
where o.current_stage='DISCOVERY'
  and o.current_machine_disposition='FORWARD'
  and o.is_active=true
  and not exists (
    select 1
    from stage_analyses a2
    where a2.opportunity_id=o.opportunity_id
      and a2.stage='COUNTY_RESEARCH'
      and a2.created_at >= d.created_at
  );

create or replace view zhongshu_queue as
select
  o.opportunity_id,
  o.candidate_key,
  c.canonical_name as company,
  o.role_title,
  o.location,
  o.requisition_id,
  o.official_url,
  o.source_url,
  o.opening_state,
  a.analysis_id as county_analysis_id,
  a.employer_buying_thesis,
  a.scope_accountability,
  a.commercial_motion,
  a.acquisition_burden,
  a.resource_structure,
  a.influence_object,
  a.operating_model,
  a.competition_pool_summary,
  a.candidate_pool_reality,
  a.execution_fit,
  a.asset_fit,
  a.competitive_fit,
  a.translation_cost,
  a.translation_cost_rationale,
  a.prosecution_case,
  a.substitution_hypothesis,
  a.structural_loss_case,
  a.blocking_reasons,
  a.residual_unknowns,
  a.created_at as county_created_at
from opportunities o
join companies c on c.company_id=o.company_id
join lateral (
  select ca.*
  from stage_analyses ca
  where ca.opportunity_id=o.opportunity_id
    and ca.stage='COUNTY_RESEARCH'
  order by ca.created_at desc
  limit 1
) a on true
where o.current_stage='COUNTY_RESEARCH'
  and o.current_machine_disposition='FORWARD'
  and o.is_active=true
  and not exists (
    select 1
    from stage_analyses z
    where z.opportunity_id=o.opportunity_id
      and z.stage='ZHONGSHU_DECISION'
      and z.created_at >= a.created_at
  );

create or replace view open_watch_queue as
select
  wt.watch_ticket_id,
  wt.opportunity_id,
  o.candidate_key,
  c.canonical_name as company,
  o.role_title,
  o.location,
  wt.trigger_condition,
  wt.next_check_at,
  wt.created_at,
  wt.metadata
from watch_tickets wt
join opportunities o on o.opportunity_id=wt.opportunity_id
join companies c on c.company_id=o.company_id
where wt.status='OPEN'
  and o.is_active=true;

create or replace view recent_eliminations_for_audit as
select
  e.*,
  o.candidate_key,
  c.canonical_name as company,
  o.role_title,
  o.location
from elimination_records e
join opportunities o on o.opportunity_id=e.opportunity_id
join companies c on c.company_id=o.company_id
where e.superseded_by is null;

comment on view xianya_queue is 'Unconsumed discovery survivors eligible for 县衙 V2.';
comment on view zhongshu_queue is 'Unconsumed 县衙 V2 survivors eligible for 中书省 V4.';
comment on view open_watch_queue is 'Open Watch tickets for 举孝廉 monitoring.';
comment on view recent_eliminations_for_audit is 'Current elimination history available to Combined Audit false-negative review.';