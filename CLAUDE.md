# homelab

Backlog: GitHub Issues. Every issue has Goal, Done when, Out of scope, Depends on.
This repo is public: never commit secrets. Push protection and a pre-tool hook enforce it; this line is the reminder.

## How work flows
- Research → `/research`. Plan → `/wayfinder` (big) or `/grill-with-docs` (one decision). Breakdown → `/to-tickets`. Document → ADRs via `/grill-with-docs`.
- Enter every multi-stage task through `/hl-flow`; it calls exactly one skill per stage. Do not use plan mode, deep research or any other skill for those stages.
- A rule that must hold every time is a hook, never a sentence here.
- Downloaded skills (listed in skills-lock.json) are never edited; wrap them in an `hl-` skill instead.

## Repo facts
- Engine: Flux via the Flux Operator. Dev syncs from a local OCI artifact; prod from GitHub with a read-only key.
- Stateful Kustomizations carry `deletionPolicy: Orphan` and stateful objects carry the no-prune annotation.
- Images must be multi-architecture (amd64 + arm64).
- Decisions live in `docs/adr/`; read the index before proposing a change to any of them.
