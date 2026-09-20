# Environment isolation

Phase 1 uses separate Supabase projects for TEST and PROD. Runtime identity alone is not enough to prevent an accidental cross-wiring, so each database also carries an admin-configured environment marker in `private.runtime_environment_guard`.

`runtime_begin_run_v2` fails closed when:

- the database environment marker has not been configured; or
- the requested runtime environment does not match the database marker.

The public migration creates the guard mechanism but does not seed TEST or PROD. Environment-specific values are deployment configuration and must be injected outside this public repository.

The normal runtime role may read the guard but may not modify it. The legacy `runtime_begin_run` API is removed from the normal service-role execution path once this migration is applied.

This guard detects environment misrouting. It is not a substitute for least-privilege credentials: database-administration connectors remain privileged and must be governed separately.
