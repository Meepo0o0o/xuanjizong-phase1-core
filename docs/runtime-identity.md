# Runtime identity

Phase 1 treats runtime identity as separate dimensions rather than one overloaded version string.

- `run_id`: one invocation and replay boundary.
- `worker_key`: stable logical worker identity.
- `contract_version`: version of the worker's behavioral/business contract.
- `release_version`: approved software/prompt release.
- `deployment_id`: concrete deployment instance promoted to one environment.
- `task_id`: scheduler task identity.
- `environment`: execution boundary such as TEST or PROD.

`task_title` is display metadata and is not part of identity.

Legacy `research_runs.schema_version` and `research_runs.runtime_version` remain compatibility aliases for `contract_version` and `release_version`. New runtimes must start runs through `runtime_begin_run_v2`.

This is an evidence model, not a replacement deployment-control plane. Scheduled Tasks remains the scheduler source of truth; PostgreSQL records what actually ran.
