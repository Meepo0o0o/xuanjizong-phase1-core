# xuanjizong-phase1-core

Public engineering layer for Xuanjizong Phase 1.

This repository contains reusable source-controlled infrastructure only:
- PostgreSQL schema migrations and validation checks;
- CI validation;
- architecture and engineering-agent instructions.

## Privacy boundary

Do **not** commit:
- candidate/person-specific evidence;
- real job/application records;
- compensation or personal targeting rules;
- production/test project IDs or account identifiers;
- credentials, tokens, secrets, or private URLs;
- production snapshots or compiled production prompts.

Mutable/private runtime and business data belongs in the private database/runtime configuration layer.

## Release rule

Changes reach `main` only through a pull request whose required CI check passes.
