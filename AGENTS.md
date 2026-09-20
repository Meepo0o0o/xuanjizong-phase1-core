# AGENTS.md

Binding instructions for engineering agents working in the public Xuanjizong Phase 1 core repository.

## Goal

Build the smallest system that reliably supports the real Phase 1 workflow.

Prefer, in order:

platform-native capability -> existing system/subscription -> mature open source -> credible free tier -> custom code.

Do not build infrastructure merely because it is possible. Add custom code only when a real, current requirement cannot be met cleanly by an existing solution.

## Privacy boundary

This repository is public. Keep all user-private, candidate-specific, real job/business, credential, environment-identifier, and private runtime data outside it.

A private repository that contains or may contain such data must remain private.

This repository may contain only reviewed, reusable public-safe engineering artifacts.

## Engineering method

- Solve the current blocker, not hypothetical future problems.
- When the existing stack can support the next real TEST run, stop preparing and run TEST.
- Let real operation expose missing capability before adding infrastructure.
- Do not create custom schedulers, control planes, governance layers, databases, workers, services, tables, or triggers unless a concrete requirement actually needs them.
- Prefer simple integration and small glue code over framework building.

## Platform responsibilities

- GitHub: source control and CI.
- PostgreSQL/Supabase: canonical mutable runtime data, transactions, constraints, and only the minimum shared persistence functions needed by the workflow.
- Scheduled Tasks: scheduling.
- ChatGPT/Web: research and reasoning.

Do not make one component imitate another component's job.

## Source control

- Work through branches and pull requests because `main` is protected.
- Required CI must pass before merge.
- Do not force-push `main`.
- Remove temporary branches after they are no longer useful.

## TEST and PROD

Use TEST for new engineering behavior first.

Free, reversible TEST work that does not damage real business data may proceed without extra ceremony.

PROD destructive changes, irreversible deletion, broad permission expansion, or major architecture changes require explicit user approval.

## Cost

Prefer adequate free solutions. Do not provision new paid resources without explicit user approval.

Engineering complexity and maintenance burden are also costs.

## Validation

Use the minimum validation needed to know the change works.

Confirm the target when similar TEST/PROD or Private/Public resources could be confused. Read back important mutations. Do not turn ordinary engineering work into a security audit or repeated validation ritual.

## Done

A change is done when the current requirement works and has enough evidence to trust it.

Do not keep building after the current blocker is removed.
