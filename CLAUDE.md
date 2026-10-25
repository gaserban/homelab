# homelab

Backlog: GitHub Issues. Every issue has Goal, Done when, Out of scope, Depends on.
This repo is public: never commit secrets. Push protection and a pre-tool hook enforce it; this line is the reminder.

## How work flows
- Skills are chosen by their descriptions; the catalog with triggers is in `docs/agents/harness.md`. Before any planning skill, read `docs/adr/README.md`. Skills that create issues, branches or PRs are hidden from Claude and typed by the operator.
- A rule that must hold every time is a hook, never a sentence here.
- A PR is one completed feature: a spec with all its tickets, or a standalone change. Start each on its own branch off `origin/main`, without asking; a spec's tickets merge into the spec's branch. When the feature is done, push it, open the PR closing the spec and its tickets, and tell the operator; the merge stays theirs (ADR 0013).
- Downloaded skills (listed in skills-lock.json) are never edited; wrap them in an `hl-` skill instead.

## Repo facts
- Engine: Flux via the Flux Operator. Dev syncs from a local OCI artifact; prod from GitHub with a read-only key.
- Stateful Kustomizations carry `deletionPolicy: Orphan` and stateful objects carry the no-prune annotation.
- Images must be multi-architecture (amd64 + arm64).
- Decisions live in `docs/adr/`; read the index before proposing a change to any of them.

## Agent skills

### Issue tracker

GitHub Issues, every body mapped onto the four-heading template. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default roles, label string equal to role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
