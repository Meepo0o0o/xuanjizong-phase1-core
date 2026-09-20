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

## Cost and resource policy

- Prefer no-cost solutions when they satisfy the requirement.
- Before proposing or provisioning a paid resource, first research built-in, existing-subscription, mature open-source, and credible free-tier alternatives.
- Use a paid resource only when the no-cost alternatives are materially insufficient for the requirement, and do not incur new paid spend without explicit user approval.
- Treat engineering complexity and maintenance burden as costs too: prefer the simplest sufficient standard solution over custom infrastructure.

## Repository publication safety gate

Repository visibility changes are security-sensitive operations and must fail closed.

- Never recommend or perform Private -> Public on a repository that contains, has contained, or may contain candidate/person-specific data, private business records, environment identifiers, credentials, production snapshots, private prompts, or other non-public runtime assets.
- A repository may become public only if it is a purpose-built public-safe repository or clean-room export.
- Before any Public publication decision, verify the exact repository identity and inspect the exposure surface beyond the default branch, including current branches, commit history, pull requests, workflow artifacts/logs where relevant, and known secret/privacy risks.
- If repository identity, history, or data classification is uncertain, stop and keep the repository private. Do not ask the user to make it public as a troubleshooting shortcut.
- Do not treat branch-protection pricing or platform limitations as sufficient reason to expose private assets. Prefer architectural separation, another no-cost safe platform, or a different control.
- Visibility changes require explicit user approval after the risk boundary is stated; engineering automation must not silently broaden visibility.

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
