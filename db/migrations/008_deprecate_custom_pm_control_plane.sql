-- 008_deprecate_custom_pm_control_plane.sql
-- Non-destructive deprecation marker only. No rows or objects are removed.

comment on table system_changes is
  'DEPRECATED for new project-management work. Historical/forensic only. Use GitHub Issues/PRs/ADRs/CHANGELOG and runtime readback per ADR-001.';
comment on table change_impacts is
  'DEPRECATED for new project-management work. Historical/forensic only. See ADR-001.';
comment on table execution_work_orders is
  'DEPRECATED for new project-management work. Historical/forensic only. See ADR-001.';
comment on table execution_returns is
  'DEPRECATED for new project-management work. Historical/forensic only. See ADR-001.';
comment on table pm_acceptance_reviews is
  'DEPRECATED for new project-management work. Historical/forensic only. See ADR-001.';
comment on table engineering_governance_rules is
  'DEPRECATED local rule catalog. Generic engineering discipline follows mature industry/tool guidance; project-specific rules live in AGENTS.md/contracts/ADRs.';
comment on table project_changelog_entries is
  'DEPRECATED duplicate project changelog store. CHANGELOG.md is the project changelog; retain this table as historical/forensic only.';

comment on view change_gate_status is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view engineering_governance_health is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view execution_work_order_gate is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view latest_execution_return is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view latest_pm_acceptance is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view missing_execution_work_orders is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view missing_project_changelog is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
comment on view pm_change_lifecycle_status is 'DEPRECATED with the custom PM control plane; historical/forensic only.';
