# AGENTS.md

Binding instructions for engineering agents working in the public Xuanjizong Phase 1 core repository.

## Public boundary

This repository is public engineering infrastructure. Do not commit private or user-specific runtime/business data.

Forbidden in this repository:
- candidate/person-specific evidence or resumes;
- real job/application records or private company-research snapshots;
- compensation or personal targeting rules;
- production/test account or project identifiers;
- spreadsheet/file identifiers used by private runtime;
- credentials, tokens, private keys, authenticated connection strings;
- compiled production prompts that contain private business configuration.

Private configuration and mutable business state belong outside this repository.

## Working method

For non-trivial changes:

inspect/research -> compare standard approaches -> choose the simplest sufficient path -> execute -> validate -> read back

Use established platform/industry primitives before inventing custom infrastructure.

## Source control

- Work on a branch.
- Use a pull request for changes to main.
- Required CI must pass before merge.
- Do not force-push main.
- Do not claim deployment success from repository state alone.

## Database

- PostgreSQL is the canonical mutable persistence technology for Phase 1.
- Schema changes are versioned migrations.
- Unattended mutations must be idempotent/replay-safe.
- Workflow transitions should be atomic where practical.
- A mutation is not successful until canonical readback confirms it.
- Do not embed environment-specific identifiers or credentials in migrations.

## Validation

Changes affecting schema or persistence must be tested against a fresh PostgreSQL database. Run the relevant migration, smoke, security, and contract gates on the current HEAD.

## Done

A change is done only when the intended repository outcome is implemented and verified. Runtime/production outcomes require separate runtime evidence.
