-- Review-rigor quality gates for post-V4 Zhongshu records.
-- Apply to new records after contract cutover; legacy migrated rows are exempt unless re-researched.

-- 1. PRESENT_FOR_HUMAN must expose three fit dimensions and translation cost.
select o.candidate_key, a.analysis_id
from opportunities o
join stage_analyses a on a.opportunity_id = o.opportunity_id
join research_runs r on r.research_run_id = a.research_run_id
where o.current_machine_disposition = 'PRESENT_FOR_HUMAN'
  and a.stage = 'ZHONGSHU_DECISION'
  and a.review_ready = true
  and r.schema_version = 'zhongshusheng-v4'
  and (a.execution_fit = 'UNKNOWN'
       or a.asset_fit = 'UNKNOWN'
       or a.competitive_fit = 'UNKNOWN'
       or a.translation_cost = 'UNKNOWN');

-- 2. A claimed non-standard winner path must not exist without an explicit substitution status.
select o.candidate_key, a.analysis_id, a.nonstandard_winner_path, a.substitution_case_status
from opportunities o
join stage_analyses a on a.opportunity_id = o.opportunity_id
join research_runs r on r.research_run_id = a.research_run_id
where a.stage = 'ZHONGSHU_DECISION'
  and r.schema_version = 'zhongshusheng-v4'
  and a.nonstandard_winner_path is not null
  and btrim(a.nonstandard_winner_path) <> ''
  and a.substitution_case_status in ('NOT_EVIDENCED','UNKNOWN');

-- 3. PRESENT_FOR_HUMAN must contain the strongest rejection case.
select o.candidate_key, a.analysis_id
from opportunities o
join stage_analyses a on a.opportunity_id = o.opportunity_id
join research_runs r on r.research_run_id = a.research_run_id
where o.current_machine_disposition = 'PRESENT_FOR_HUMAN'
  and a.stage = 'ZHONGSHU_DECISION'
  and a.review_ready = true
  and r.schema_version = 'zhongshusheng-v4'
  and (a.strongest_rejection_case is null or btrim(a.strongest_rejection_case) = '');

-- 4. LOW Asset Fit + LOW Competitive Fit presented to humans requires an evidenced exception.
select o.candidate_key, a.analysis_id, a.substitution_case_status, a.career_capital
from opportunities o
join stage_analyses a on a.opportunity_id = o.opportunity_id
join research_runs r on r.research_run_id = a.research_run_id
where o.current_machine_disposition = 'PRESENT_FOR_HUMAN'
  and a.stage = 'ZHONGSHU_DECISION'
  and a.review_ready = true
  and r.schema_version = 'zhongshusheng-v4'
  and a.asset_fit = 'LOW'
  and a.competitive_fit = 'LOW'
  and a.substitution_case_status <> 'EVIDENCED';

-- 5. PROHIBITIVE translation cost should not reach Kingslanding without an evidenced substitution case.
select o.candidate_key, a.analysis_id, a.substitution_case_status
from opportunities o
join stage_analyses a on a.opportunity_id = o.opportunity_id
join research_runs r on r.research_run_id = a.research_run_id
where o.current_machine_disposition = 'PRESENT_FOR_HUMAN'
  and a.stage = 'ZHONGSHU_DECISION'
  and a.review_ready = true
  and r.schema_version = 'zhongshusheng-v4'
  and a.translation_cost = 'PROHIBITIVE'
  and a.substitution_case_status <> 'EVIDENCED';

-- 6. County dossiers forwarded to Zhongshu should not omit prosecution / three-fit analysis.
select o.candidate_key, a.analysis_id
from opportunities o
join stage_analyses a on a.opportunity_id = o.opportunity_id
join research_runs r on r.research_run_id = a.research_run_id
where a.stage = 'COUNTY_RESEARCH'
  and r.schema_version = 'xianya-v2'
  and a.machine_disposition = 'FORWARD'
  and (a.execution_fit = 'UNKNOWN'
       or a.asset_fit = 'UNKNOWN'
       or a.competitive_fit = 'UNKNOWN'
       or a.translation_cost = 'UNKNOWN'
       or a.prosecution_case is null
       or btrim(a.prosecution_case) = '');