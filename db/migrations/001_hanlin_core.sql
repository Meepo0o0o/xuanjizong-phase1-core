-- 璇玑宗 Phase 1 / 翰林院 canonical database
-- PostgreSQL 15+
-- Migration 001
-- NOTE: not deployed as of authoring; safe to refine before first application.

create extension if not exists pgcrypto;

create type workflow_stage as enum (
  'DISCOVERY',
  'COUNTY_RESEARCH',
  'ZHONGSHU_DECISION',
  'PRESENTED',
  'HUMAN_REVIEW',
  'APPLICATION',
  'CLOSED'
);

create type machine_disposition as enum (
  'IN_PIPELINE',
  'FORWARD',
  'FILTER',
  'WATCH',
  'DOSSIER_INCOMPLETE',
  'PRESENT_FOR_HUMAN',
  'KNOWN_NO_REPROCESS'
);

-- Kingslanding review authority only. Downstream application lifecycle is stored
-- separately in application_events and must not be conflated with review judgment.
create type human_review_disposition as enum (
  'APPROVE',
  'REJECT',
  'RESEARCH_MORE'
);

create type source_authority as enum (
  'PRIMARY_OFFICIAL',
  'PRIMARY_REGULATORY',
  'HIGH_QUALITY_EXTERNAL',
  'SECONDARY_MARKET',
  'COMMUNITY',
  'UNVERIFIED'
);

create type asset_requirement_strength as enum (
  'MUST_BE_NATIVE',
  'STRONGLY_PREFERRED_NATIVE',
  'TRANSFERABLE',
  'LEARNABLE',
  'INCIDENTAL'
);

create type evidence_relation as enum (
  'SUPPORTS',
  'CONTRADICTS',
  'QUALIFIES',
  'CONTEXTUALIZES'
);

create type fit_level as enum (
  'HIGH',
  'MEDIUM',
  'LOW',
  'UNKNOWN'
);

create type translation_cost_level as enum (
  'LOW',
  'MODERATE',
  'HIGH',
  'PROHIBITIVE',
  'UNKNOWN'
);

create type substitution_case_status as enum (
  'EVIDENCED',
  'PARTIAL',
  'NOT_EVIDENCED',
  'UNKNOWN'
);


create table companies (
  company_id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  normalized_name text not null unique,
  website text,
  headquarters text,
  company_stage text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table opportunities (
  opportunity_id uuid primary key default gen_random_uuid(),
  candidate_key text not null unique,
  company_id uuid not null references companies(company_id),
  role_title text not null,
  location text,
  requisition_id text,
  official_url text,
  source_url text,
  opening_state text,
  history_status text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  current_stage workflow_stage not null default 'DISCOVERY',
  current_machine_disposition machine_disposition not null default 'IN_PIPELINE',
  current_human_review human_review_disposition,
  case_number text,
  user_action text,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create index opportunities_company_idx on opportunities(company_id);
create index opportunities_pending_idx on opportunities(current_machine_disposition, current_human_review)
  where current_machine_disposition = 'PRESENT_FOR_HUMAN'
    and current_human_review is null;

create table sources (
  source_id uuid primary key default gen_random_uuid(),
  url text not null,
  canonical_url text,
  publisher text,
  source_type text not null,
  authority source_authority not null default 'UNVERIFIED',
  title text,
  published_at timestamptz,
  retrieved_at timestamptz not null default now(),
  content_hash text,
  artifact_uri text,
  metadata jsonb not null default '{}'::jsonb
);

-- Content-addressed de-duplication when content bytes/text are available.
-- Multiple retrievals of a changing URL remain legal when their hashes differ.
create unique index sources_content_dedupe_idx
  on sources ((coalesce(canonical_url, url)), content_hash)
  where content_hash is not null;

create index sources_url_idx on sources ((coalesce(canonical_url, url)));
create index sources_published_idx on sources(published_at desc);

create table opportunity_snapshots (
  snapshot_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  captured_at timestamptz not null default now(),
  opening_state text,
  jd_text text,
  content_hash text,
  source_id uuid references sources(source_id),
  raw_payload jsonb not null default '{}'::jsonb
);

create table claims (
  claim_id uuid primary key default gen_random_uuid(),
  source_id uuid not null references sources(source_id) on delete cascade,
  company_id uuid references companies(company_id),
  opportunity_id uuid references opportunities(opportunity_id),
  claim_type text not null,
  claim_text text not null,
  evidence_strength text,
  published_context text,
  extracted_at timestamptz not null default now(),
  valid_from timestamptz,
  valid_to timestamptz,
  superseded_by uuid references claims(claim_id),
  metadata jsonb not null default '{}'::jsonb
);

create index claims_company_idx on claims(company_id, claim_type);
create index claims_opportunity_idx on claims(opportunity_id, claim_type);

create table research_runs (
  research_run_id uuid primary key default gen_random_uuid(),
  run_id text not null unique,
  worker text not null,
  schema_version text,
  started_at timestamptz,
  finished_at timestamptz,
  status text not null,
  input_context jsonb not null default '{}'::jsonb,
  output_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table company_intelligence (
  intelligence_id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(company_id) on delete cascade,
  topic text not null,
  synthesis text not null,
  why_it_matters text,
  confidence text,
  effective_at timestamptz,
  created_at timestamptz not null default now(),
  research_run_id uuid references research_runs(research_run_id),
  metadata jsonb not null default '{}'::jsonb
);

create table company_intelligence_claims (
  intelligence_id uuid not null references company_intelligence(intelligence_id) on delete cascade,
  claim_id uuid not null references claims(claim_id) on delete cascade,
  relationship evidence_relation not null default 'SUPPORTS',
  primary key (intelligence_id, claim_id)
);

create table stage_analyses (
  analysis_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  research_run_id uuid references research_runs(research_run_id),
  stage workflow_stage not null,
  role_essence text,
  why_role_exists_now text,
  employer_buying_thesis text,
  scope_accountability text,
  commercial_motion text,
  acquisition_burden text,
  resource_structure text,
  influence_object text,
  operating_model text,
  competition_pool_summary text,
  candidate_pool_reality text,
  execution_fit fit_level not null default 'UNKNOWN',
  asset_fit fit_level not null default 'UNKNOWN',
  competitive_fit fit_level not null default 'UNKNOWN',
  translation_cost translation_cost_level not null default 'UNKNOWN',
  translation_cost_rationale text,
  prosecution_case text,
  substitution_hypothesis text,
  strongest_rejection_case text,
  substitution_case_status substitution_case_status not null default 'UNKNOWN',
  employer_substitution_case text,
  standard_winner_archetypes jsonb not null default '[]'::jsonb,
  nonstandard_winner_path text,
  structural_loss_case text,
  why_not_b text,
  career_capital text,
  opportunity_cost text,
  blocking_reasons jsonb not null default '[]'::jsonb,
  residual_unknowns jsonb not null default '[]'::jsonb,
  decision_changing_evidence jsonb not null default '[]'::jsonb,
  decision_sequence jsonb not null default '[]'::jsonb,
  false_negative_audit text,
  research_status text,
  evidence_exhaustion_status text,
  intelligence_completeness text,
  machine_disposition machine_disposition,
  review_ready boolean not null default false,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index stage_analyses_opportunity_idx
  on stage_analyses(opportunity_id, stage, created_at desc);

-- Explicit evidence graph:
-- Source -> Claim -> Interpretation -> Decision Impact.
create table interpretations (
  interpretation_id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references stage_analyses(analysis_id) on delete cascade,
  interpretation_type text not null,
  interpretation_text text not null,
  confidence text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table interpretation_claims (
  interpretation_id uuid not null references interpretations(interpretation_id) on delete cascade,
  claim_id uuid not null references claims(claim_id) on delete cascade,
  relationship evidence_relation not null default 'SUPPORTS',
  note text,
  primary key (interpretation_id, claim_id)
);

create table decision_impacts (
  decision_impact_id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references stage_analyses(analysis_id) on delete cascade,
  interpretation_id uuid references interpretations(interpretation_id) on delete cascade,
  impact_type text not null,
  impact_text text not null,
  direction text,
  severity text,
  decision_changing boolean not null default false,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index decision_impacts_analysis_idx
  on decision_impacts(analysis_id, decision_changing);

create table production_assets (
  production_asset_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  analysis_id uuid references stage_analyses(analysis_id) on delete cascade,
  asset_name text not null,
  asset_class asset_requirement_strength not null,
  rationale text,
  user_evidence text,
  coverage_status text,
  evidence_quality text,
  learnability_hireability text,
  created_at timestamptz not null default now()
);

create table production_asset_claims (
  production_asset_id uuid not null references production_assets(production_asset_id) on delete cascade,
  claim_id uuid not null references claims(claim_id) on delete cascade,
  relationship evidence_relation not null default 'SUPPORTS',
  primary key (production_asset_id, claim_id)
);

create table precedents (
  precedent_id text primary key,
  case_ref text,
  company text,
  role_or_case text,
  precedent_family text not null,
  decision_context text,
  core_pattern text not null,
  production_asset_issue text,
  operating_model_issue text,
  corrected_interpretation text not null,
  applicable_when text,
  do_not_apply_when text,
  regression_priority text,
  status text not null default 'ACTIVE',
  metadata jsonb not null default '{}'::jsonb
);

create table opportunity_precedents (
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  analysis_id uuid not null references stage_analyses(analysis_id) on delete cascade,
  precedent_id text not null references precedents(precedent_id),
  similarity text,
  material_difference text,
  effect text,
  created_at timestamptz not null default now(),
  primary key (opportunity_id, precedent_id, analysis_id)
);

create table workflow_events (
  event_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references opportunities(opportunity_id),
  research_run_id uuid references research_runs(research_run_id),
  event_type text not null,
  from_stage workflow_stage,
  to_stage workflow_stage,
  from_disposition machine_disposition,
  to_disposition machine_disposition,
  actor text not null,
  reason text,
  idempotency_key text,
  occurred_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb
);

create unique index workflow_events_idempotency_idx
  on workflow_events(idempotency_key)
  where idempotency_key is not null;

create table human_decisions (
  human_decision_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  disposition human_review_disposition not null,
  case_number text,
  decision_reason text,
  decided_at timestamptz not null default now(),
  supersedes uuid references human_decisions(human_decision_id),
  metadata jsonb not null default '{}'::jsonb
);

create index human_decisions_opportunity_idx
  on human_decisions(opportunity_id, decided_at desc);

-- Numbering is a durable event, separate from review judgment.
create table case_number_events (
  case_number_event_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  case_number text not null,
  assigned_at timestamptz not null default now(),
  supersedes uuid references case_number_events(case_number_event_id),
  metadata jsonb not null default '{}'::jsonb
);

create unique index active_case_number_unique_idx
  on case_number_events(case_number);

-- Application / recruiting lifecycle is intentionally open-ended so new provider
-- statuses do not require an enum migration.
create table application_events (
  application_event_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  event_type text not null,
  occurred_at timestamptz not null,
  cv_version text,
  status text,
  reason text,
  source_ref text,
  metadata jsonb not null default '{}'::jsonb
);

create index application_events_opportunity_idx
  on application_events(opportunity_id, occurred_at desc);

create table watch_tickets (
  watch_ticket_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  trigger_condition text not null,
  status text not null default 'OPEN',
  next_check_at timestamptz,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create table coverage_cells (
  coverage_cell_id uuid primary key default gen_random_uuid(),
  research_run_id uuid references research_runs(research_run_id) on delete cascade,
  coverage_plan_id text,
  geography text,
  role_lane text,
  company_tier text,
  ecosystem_cluster text,
  source_class text,
  query_family text,
  planned boolean,
  swept boolean,
  raw_observations integer,
  unique_candidates integer,
  unique_employers integer,
  new_candidates integer,
  duplicate_history_hits integer,
  forward_count integer,
  filter_count integer,
  novelty_status text,
  coverage_gap text,
  budget_exhausted boolean,
  coverage_status text,
  evidence_refs text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index coverage_cells_dimensions_idx
  on coverage_cells(geography, role_lane, company_tier, ecosystem_cluster);

create table elimination_records (
  elimination_record_id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(opportunity_id) on delete cascade,
  eliminated_at_stage workflow_stage,
  reason_codes jsonb not null default '[]'::jsonb,
  reason_summary text,
  hard_gate_or_structural text,
  unknowns_at_time text,
  false_negative_audit text,
  material_change_triggers text,
  policy_version text,
  strategy_version text,
  algorithm_bundle_version text,
  reprocess_allowed_when text,
  eliminated_at timestamptz,
  last_checked_at timestamptz,
  superseded_by uuid references elimination_records(elimination_record_id),
  metadata jsonb not null default '{}'::jsonb
);

create index elimination_records_opportunity_idx
  on elimination_records(opportunity_id, eliminated_at desc);

create table raw_import_records (
  import_record_id uuid primary key default gen_random_uuid(),
  legacy_source text not null,
  legacy_sheet text,
  legacy_row_number integer,
  imported_at timestamptz not null default now(),
  import_status text not null,
  canonical_entity text,
  canonical_id uuid,
  payload jsonb not null,
  error text
);

create unique index raw_import_origin_idx
  on raw_import_records(legacy_source, legacy_sheet, legacy_row_number);

create view kingslanding_pending as
select
  o.opportunity_id,
  o.candidate_key,
  c.canonical_name as company,
  o.role_title,
  o.location,
  o.official_url,
  o.current_machine_disposition,
  o.case_number,
  a.analysis_id,
  a.role_essence,
  a.why_role_exists_now,
  a.employer_buying_thesis,
  a.operating_model,
  a.acquisition_burden,
  a.competition_pool_summary,
  a.candidate_pool_reality,
  a.execution_fit,
  a.asset_fit,
  a.competitive_fit,
  a.translation_cost,
  a.translation_cost_rationale,
  a.strongest_rejection_case,
  a.substitution_case_status,
  a.employer_substitution_case,
  a.nonstandard_winner_path,
  a.structural_loss_case,
  a.career_capital,
  a.opportunity_cost,
  a.blocking_reasons,
  a.residual_unknowns,
  a.decision_changing_evidence,
  a.decision_sequence,
  a.false_negative_audit,
  a.research_status,
  a.evidence_exhaustion_status,
  a.created_at as analysis_created_at
from opportunities o
join companies c on c.company_id = o.company_id
join lateral (
  select sa.*
  from stage_analyses sa
  where sa.opportunity_id = o.opportunity_id
    and sa.stage = 'ZHONGSHU_DECISION'
    and sa.review_ready = true
  order by sa.created_at desc
  limit 1
) a on true
where o.current_machine_disposition = 'PRESENT_FOR_HUMAN'
  and o.current_human_review is null
  and o.is_active = true;

comment on view kingslanding_pending is
'Authoritative Kingslanding inbox: review-ready PRESENT_FOR_HUMAN opportunities without a human review disposition.';
