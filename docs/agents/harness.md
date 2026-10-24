# The agent harness

How Claude Code is set up in this repository and how its flows compose. Decisions are recorded in
ADR 0013 and ADR 0014; this document is the architecture they refer to. Anthropic's rule governs
growth: nothing is built up front; each piece is added when its trigger appears (a convention got
wrong twice, the same procedure pasted a third time, a rule that must hold every time).

## Layers

| Layer | Claude Code primitive | Lives in | Loads |
| --- | --- | --- | --- |
| Always-on rules | CLAUDE.md (under 200 lines); `.claude/rules/*.md`, optionally scoped to paths | repo root, `.claude/rules` | every session |
| Knowledge | reference skills Claude may load itself; ADRs; glossary; `docs/research/` | `.claude/skills`, `docs` | on demand |
| Actions | user-invoked skills (`disable-model-invocation: true`), each leaving an artifact | `.claude/skills` | when called |
| Router | `hl-flow`: a user-invoked skill whose body calls exactly one other skill | `.claude/skills/hl-flow` | when called |
| Isolation | subagents with a tool allowlist, preloaded skills, own hooks; skills with `context: fork` | `.claude/agents` | when spawned |
| Gates | hooks: PreToolUse denies or asks; Stop refuses to end a turn; prompt and agent hook types judge | settings, skill and agent frontmatter | on event |
| Loops | a Stop hook that blocks until a check passes; `/loop`; workflows of the "fix until green" shape | settings, `.claude/workflows` | on event |
| Graphs | dynamic workflows (agent, parallel, pipeline, phase); the ticket graph (to-tickets edges, run by implement-spec) | `.claude/workflows`, GitHub Issues | when run |
| Packaging | a plugin, when a second repository needs this setup | later | |

## Composition rules

1. Every multi-stage task enters through `hl-flow`, which calls one skill per stage. Never two.
2. A rule that must hold every time is a hook, never prose.
3. Every action skill leaves a durable artifact: a file, an ADR, an issue, a PR.
4. Anything coordinating more than a handful of agents is a saved workflow, not an improvised fan-out.
5. Subagents get the narrowest tool list that does the job. A reviewer cannot edit.
6. Downloaded skills (skills-lock.json) are wrapped, never edited. Our skills carry the `hl-` prefix.
7. State between stages lives in artifacts and a state file, never only in the conversation.
8. A stage refuses to start without its predecessor's handover.

## Stage to skill

| Stage | Skill | Artifact |
| --- | --- | --- |
| Research | `research` | `docs/research/<topic>.md` with sources and an adopt-or-build verdict |
| Planning | `wayfinder` (work too big for a session) or `grill-with-docs` (one decision) | map issue and decision tickets; an ADR per decision |
| Breakdown | `to-spec`, then `to-tickets` | spec issue; tickets in the four-part template with blocking links |
| Documenting | `domain-modeling`, reached through `grill-with-docs` | ADRs, GLOSSARY.md |
| Build | `implement` | branch and PR |
| Review | `code-review` as a read-only subagent | PR findings |
| Agent briefs | `triage` | agent-ready briefs on tickets |
| Parallel build | `implement-spec` | PRs per ready ticket |

## The engineer flow

`/hl-engineer` is a conductor. It calls one skill per stage and stops at the human gates.

```
design from the operator
 1 Requirements  grill-with-docs ─ gate: shared understanding confirmed
 2 Plan          wayfinder, or the ADRs from stage 1
 3 Research      research, forked; adopt-or-build checklist ─ gate: verdict accepted
 4 Breakdown     to-spec, to-tickets
 5 Build         implement
 6 Review loop   code-review (read-only subagent)
                 pass → 7; fail and rounds < N → 5 (Stop hook refuses to end the turn);
                 fail and rounds = N → stop and ask the operator
                 gate: PR approved
 7 Agent briefs  triage → hand-off to implement-spec (separate flow)
```

State file: `.flow/<run>.json` with stage, status (running or awaiting-operator), review round, N.
Handover: at every boundary the finishing stage updates the state file and writes
`.flow/<run>/handoff-<stage>.md` with the `handoff` skill (what was decided, where the artifacts
are, what is open, which skill runs next; pointers, not copies; nothing sensitive). Resume is
`/hl-engineer resume`: read the state file, read the latest handover, continue.

Adopt-or-build checklist, applied by the research stage: maintained within the last year,
permissive licence, passing security audits, more than one maintainer, multi-architecture images,
pinned by digest. Fail any, and the verdict is build or find another.

## Hooks in force

| Hook | Event | Enforces |
| --- | --- | --- |
| `.claude/hooks/git-guard.sh` | PreToolUse on Bash | no merge, no push to main, no force push, no destructive local git |
| `.claude/hooks/issue-template.sh` | PreToolUse on Bash matching gh issue | the four headings in every issue body |
| review-loop (in `hl-engineer` frontmatter, planned) | Stop | the bounded review loop |

## Sandbox

Mandatory on WSL2. The network allowlist in `.claude/settings.json` starts with every known host.
Sandboxed commands cannot reach the host's loopback, so the dev cluster API is bound to the WSL
interface address and that address and port are allowlisted; only the container runtime is excluded
from the sandbox, because its socket is unavoidable. Read access to the Windows drives, the SSH
directory and the App key directory is denied to the Read tool and the sandbox alike.

## Memory

Auto memory is off. Everything Claude should know is in git and reviewable: CLAUDE.md, rules, ADRs,
glossary, research files, reference skills. Subagent memory is unavailable as a result. Revisit
only if repeated corrections pile up faster than they are written down.

## Skill inventory

Downloaded (never edited; see skills-lock.json): the Anthropic plugin-dev guides (skill, hook,
agent development), skill-creator, writing-for-agents, the planning suite from mattpocock/skills
(ask-matt, grilling, grill-me, grill-with-docs, wayfinder, to-spec, to-tickets, implement,
implement-spec, triage, research, handoff, claude-handoff, chief-of-staff, wizard, domain-modeling,
code-review, prototype, tdd, retro, wait-what, setup-matt-pocock-skills), the Flux gitops-knowledge
skill, the Terraform/OpenTofu skill, find-skills.

Ours (`hl-` prefix): `hl-flow` (router), `hl-engineer` (conductor), `hl-add-app` (planned, after
the KRO prototype).
