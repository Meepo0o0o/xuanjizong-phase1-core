# Architecture

## Boundary

GitHub is the public source of truth for reusable Phase 1 engineering artifacts:
- database schema and migrations;
- persistence invariants;
- CI validation;
- architecture decisions;
- engineering-agent instructions.

Private runtime/business configuration is injected outside this repository and must not be committed here.

## Runtime/data authority

PostgreSQL/Supabase is the canonical mutable runtime store. Environment identifiers and credentials are deployment configuration, not source code.

## Persistence invariants

- one canonical mutable store;
- deterministic idempotency for unattended mutations;
- atomic workflow transitions where practical;
- readback before claiming mutation success;
- append history rather than silently overwriting it;
- no fallback to a legacy store as hidden runtime authority.

## Deployment

CI validates schema and persistence behavior against an ephemeral PostgreSQL instance. Production deployment is a separate promotion step and must be verified by runtime readback.
