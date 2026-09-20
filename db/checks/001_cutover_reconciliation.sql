-- 翰林院 cutover reconciliation checks
-- Run after legacy import and before any PROD worker cutover.

-- 1. No duplicate opportunity identity.
select candidate_key, count(*)
from opportunities
group by candidate_key
having count(*) > 1;

-- 2. No duplicate case number.
select case_number, count(*)
from case_number_events
group by case_number
having count(*) > 1;

-- 3. Every raw legacy row must have an explicit import outcome.
select legacy_sheet, count(*) as unresolved_rows
from archive.raw_import_records
where import_status is null
   or import_status not in ('IMPORTED','PROJECTION_ONLY','LEGACY_ONLY','REJECTED_WITH_REASON')
group by legacy_sheet;

-- 4. Rejected imports must be explicit and inspectable.
select legacy_sheet, legacy_row_number, error
from archive.raw_import_records
where import_status = 'REJECTED_WITH_REASON'
order by legacy_sheet, legacy_row_number;

-- 5. Kingslanding inbox sanity.
select candidate_key, company, role_title, location, research_status,
       evidence_exhaustion_status, analysis_created_at
from kingslanding_pending
order by analysis_created_at;

-- 6. PRESENT_FOR_HUMAN must have a review-ready Zhongshu analysis.
select o.candidate_key
from opportunities o
where o.current_machine_disposition = 'PRESENT_FOR_HUMAN'
  and o.current_human_review is null
  and not exists (
    select 1 from stage_analyses a
    where a.opportunity_id = o.opportunity_id
      and a.stage = 'ZHONGSHU_DECISION'
      and a.review_ready = true
  );

-- 7. Every normalized production asset must belong to an analysis/opportunity.
select pa.production_asset_id
from production_assets pa
left join opportunities o on o.opportunity_id = pa.opportunity_id
where o.opportunity_id is null;

-- 8. V4 Zhongshu analyses marked RESEARCH_COMPLETE must have evidence graph.
select o.candidate_key, a.analysis_id
from stage_analyses a
join opportunities o on o.opportunity_id = a.opportunity_id
where a.stage = 'ZHONGSHU_DECISION'
  and a.research_status = 'RESEARCH_COMPLETE'
  and a.created_at >= timestamptz '2026-09-19 23:00:00+08'
  and not exists (
    select 1
    from interpretations i
    join interpretation_claims ic on ic.interpretation_id = i.interpretation_id
    join claims c on c.claim_id = ic.claim_id
    where i.analysis_id = a.analysis_id
  );

-- 9. Decision-changing impacts must trace to an interpretation.
select di.decision_impact_id, di.analysis_id
from decision_impacts di
where di.decision_changing = true
  and di.interpretation_id is null;

-- 10. Watch tickets must refer to active opportunities.
select wt.watch_ticket_id, o.candidate_key
from watch_tickets wt
join opportunities o on o.opportunity_id = wt.opportunity_id
where wt.status = 'OPEN' and o.is_active = false;

-- 11. Coverage cells should resolve to a known research run when run_id was recoverable.
select cc.coverage_cell_id
from coverage_cells cc
where cc.research_run_id is null;

-- 12. Report import counts by legacy source tab.
select legacy_sheet, import_status, count(*)
from archive.raw_import_records
group by legacy_sheet, import_status
order by legacy_sheet, import_status;
