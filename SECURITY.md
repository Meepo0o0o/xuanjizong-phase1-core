# Security and privacy boundary

This public repository must remain free of private candidate data, production records, credentials, account identifiers, and environment-specific project IDs.

## Publication rule

Private repositories containing user, candidate, business, environment, or runtime data must remain private.

Do not convert such a repository to public in order to obtain branch-protection, CI, or other platform features. If public source control is needed, create a separate clean-room public repository that contains only reviewed public-safe engineering artifacts and has independent history.

A Private -> Public change is permitted only after repository-wide exposure review confirms the exact repository is intentionally public-safe. Uncertainty means no publication.

## Never commit

- passwords, API keys, access tokens, service-role keys;
- database connection strings containing credentials;
- candidate resumes or personal evidence;
- real application/job-state snapshots;
- private spreadsheet/file IDs;
- production/test project IDs;
- compiled production prompts containing private business data.

Use deployment secrets and the private runtime/database layer for those values.

If private data is committed, stop publication and remediate history before making the affected repository public.
