# homelab

Backlog: GitHub Issues. Every issue has Goal, Done when, Out of scope, Depends on.
This repo is public: never commit secrets. Push protection and a pre-tool hook enforce it; this line is the reminder.

## How work flows
- Skills are chosen by their descriptions; the catalog with triggers is in `docs/agents/harness.md`. Before any planning skill, read `docs/adr/README.md`. Skills that create issues, branches or PRs are hidden from Claude and typed by the operator.
- A rule that must hold every time is a hook, never a sentence here.
- Downloaded skills (listed in skills-lock.json) are never edited; wrap them in an `hl-` skill instead.

## Repo facts
- Engine: Flux via the Flux Operator. Dev syncs from a local OCI artifact; prod from GitHub with a read-only key.
- Stateful Kustomizations carry `deletionPolicy: Orphan` and stateful objects carry the no-prune annotation.
- Images must be multi-architecture (amd64 + arm64).
- Decisions live in `docs/adr/`; read the index before proposing a change to any of them.
