# Security and privacy boundary

This public repository must remain free of private candidate data, production records, credentials, account identifiers, and environment-specific project IDs.

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
