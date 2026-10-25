# The agent harness

How Claude Code is set up in this repository and how its flows compose. Decisions are recorded in
ADR 0013 to ADR 0016; this document is the architecture they refer to. Anthropic's rule governs
growth: nothing is built up front; each piece is added when its trigger appears (a convention got
wrong twice, the same procedure pasted a third time, a rule that must hold every time).

## Layers

| Layer | Claude Code primitive | Lives in | Loads |
| --- | --- | --- | --- |
| Always-on rules | CLAUDE.md (under 200 lines); `.claude/rules/*.md`, optionally scoped to paths | repo root, `.claude/rules` | every session |
| Knowledge | reference skills Claude may load itself; ADRs; glossary; `docs/research/` | `.claude/skills`, `docs` | on demand |
| Actions | user-invoked skills (`disable-model-invocation: true`), each leaving an artifact | `.claude/skills` | when called |
| Router | the skill listing: every model-visible skill's description is in context and Claude picks by it; side-effecting skills are hidden and typed by the operator, who finds them with `/` plus letters or `/skills` | skill frontmatter; `skillOverrides` in settings | every session |
| Isolation | subagents with a tool allowlist, preloaded skills, own hooks; skills with `context: fork` | `.claude/agents` | when spawned |
| Gates | hooks: PreToolUse denies or asks; Stop refuses to end a turn; prompt and agent hook types judge | settings, skill and agent frontmatter | on event |
| Loops | a Stop hook that blocks until a check passes; `/loop`; workflows of the "fix until green" shape | settings, `.claude/workflows` | on event |
| Graphs | dynamic workflows (agent, parallel, pipeline, phase); the ticket graph (to-tickets edges, run by implement-spec) | `.claude/workflows`, GitHub Issues | when run |
| Packaging | a plugin, when a second repository needs this setup | later | |

## Composition rules

1. A skill is model-visible if it reads, analyzes, advises, or is reached by another skill; hidden
   if it acts on the world. A hidden skill cannot be called by another skill, so a flow that
   needs one stops and names it for the operator.
2. A rule that must hold every time is a hook, never prose.
3. Every action skill leaves a durable artifact: a file, an ADR, an issue, a PR.
4. Anything coordinating more than a handful of agents is a saved workflow, not an improvised fan-out.
5. Subagents get the narrowest tool list that does the job. A reviewer cannot edit.
6. Downloaded skills (skills-lock.json) are wrapped, never edited, never committed: a SessionStart
   hook restores them (ADR 0017). Our skills carry the `hl-` prefix.
   A divergence climbs the ladder in ADR 0016: configure (`docs/agents/*.md`, CLAUDE.md), enforce
   (hook), restrict (`skillOverrides`), route around, and fork only under its own ADR.
7. State between stages lives in artifacts and a state file, never only in the conversation.
8. A stage refuses to start without its predecessor's handover.
9. A subagent runs on the smallest model that does its job, set in its agent file (`model:`) or on
   the Agent call: Haiku for read-only fan-out lookups (Explore), Sonnet for bounded production work
   with a spec in hand (research notes, implementers, graders), Opus for judgment that must be
   adversarial (plan reviewers, mergers). The conductor runs on the session model, because the
   operator is there.

## Stage to skill

| Stage | Skill | Typed by | Artifact |
| --- | --- | --- | --- |
| Research | `research` | Claude | `docs/research/<topic>.md` with sources and an adopt-or-build verdict |
| Planning | `wayfinder` (work too big for a session) or `grill-with-docs` (one decision) | operator | map issue and decision tickets; an ADR per decision |
| Spec | `to-spec` | operator | spec issue |
| Breakdown | `to-tickets` | operator | tickets in the four-part template with blocking links |
| Documenting | `domain-modeling`, reached through `grill-with-docs` | operator | ADRs, GLOSSARY.md |
| Build | `implement` | operator | branch and PR |
| Review | `code-review` as a read-only subagent | Claude | PR findings |
| Agent briefs | `triage` | operator | agent-ready briefs on tickets |
| Parallel build | `implement-spec` | operator | PRs per ready ticket |

## The engineer flow

`/hl-engineer <issue>` is a conductor (ADR 0016). It takes one GitHub issue to approved tickets
and stops; `/implement` or `/implement-spec` take over from there. Every stage runs in the main
conversation, because only there can it ask the operator.

```
issue from the operator
 0 Intake          issue, ADRs, research notes; state file
 1 Prior art       one question per thing a practitioner already knows; Haiku lookups in the repo,
                   Sonnet research upstream, in parallel; the plan cites it or says why not ─ checkpoint
 2 Requirements    grilling, domain-modeling ─ gate
 3 Plan            draft → hl-plan-reviewer ×3 lenses (Falsifier, Saboteur, Newcomer), read-only, Opus
                   revise and repeat, at most 3 rounds (PreToolUse hook on Agent denies the 4th);
                   the log lives in its own file, the brief stays under 3,000 words ─ gate
 4 Breakdown       parts as vertical slices; plan amendments, Saboteur once if they change the
                   design ─ checkpoint
 5 Adopt-or-build  per part: ADR-fixed → cite it; else one research run per candidate, in parallel
                   on Sonnet, scored on the checklist; a verdict may send the flow back to 4 ─ gate
 6 Publish         approved plan as one issue comment; operator types /to-tickets <issue>
                   → native sub-issues with native blocking links
 7 Close-out       headings, parent links, blocked-by edges, Done-when kept word for word ─ gate
```

Every gate appends a row to `docs/agents/hl-engineer-runs.md` (answer, rounds, findings, brief
size, minutes, the operator's friction). The skill is judged on those rows from real issues, and
`/retro` over them every third run decides what changes; the eval set in
`.claude/skills/hl-engineer/evals/evals.json` is the checklist the retro grades against. Stage 1 is
not yet in ADR 0016's stage list and needs a superseding note.

Gates are `AskUserQuestion` prompts (approve, revise, stop); `askUserQuestionTimeout` stays unset.
The only typed command is `/to-tickets`, because it is author-hidden. At every checkpoint the
conductor posts a one- or two-line progress comment on the source issue.

State file: `.flow/<issue>.json` with stage, status (running or awaiting-operator), review round.
Checkpoint briefs: `.flow/<issue>/NN-<stage>.md`, written by the conductor itself (what was
decided, where the artifacts are, what is open; pointers, not copies; nothing sensitive). Both are
gitignored; the durable record is the issue. `handoff` is not used: it is hidden and writes to
`$TMPDIR`. Resume is `/hl-engineer resume <issue>`: read the state file and the latest brief,
continue.

Adopt-or-build checklist, applied in stage 4: maintained within the last year,
permissive licence, passing security audits, more than one maintainer, multi-architecture images,
pinned by digest. Fail any, and the verdict is build or find another.

## Flow model

Two tiers, from the docs: a workflow takes no input mid-run ("for sign-off between stages, run
each stage as its own workflow"); a hidden skill cannot be called by another skill; state across
sessions is files, issues and pull requests.

- **Repeatable flows** (for example `hl-add-app`: research, write manifests, validate, open a
  PR) are saved workflows in `.claude/workflows/<name>`, run as `/<name> <args>`. Their stages
  are our own model-visible skills or prompts in the script. The PR review is the gate; nothing
  is typed between stages.
- **Gated flows** (for example `hl-engineer`) are conductor skills, hidden and typed by the
  operator. Gates are `AskUserQuestion` prompts in the conductor's turn. A stage owned by an
  author-hidden skill (`wayfinder`, `to-spec`, `to-tickets`, `implement`) is a typed gate: the
  conductor writes its brief, updates `.flow/<issue>.json`, names the skill to type, and resumes
  on `/hl-engineer resume <issue>`. A conductor never calls a hidden skill. A workflow is used
  only for a stage with no sign-off inside it.
- Orchestration stays inside Claude Code. LangChain and LangGraph are not in Anthropic's docs
  and would bypass the sandbox, hooks, permissions and skills. If orchestration in code is ever
  needed, the documented path is the Agent SDK: the same harness, in Python or TypeScript.

## Skill catalog

The human index. Claude picks visible skills by description; the operator types the rest.

| Skill | Leaves behind | Visible to | Source |
| --- | --- | --- | --- |
| agent-development, hook-development, skill-development | guidance for writing agents, hooks, skills | Claude | anthropics/claude-code plugin-dev |
| skill-creator | a new or improved skill, eval results | Claude | anthropics/skills |
| writing-for-agents | guidance for skills, CLAUDE.md, AGENTS.md | Claude | mattpocock/skills |
| gitops-knowledge | Flux answers and manifests | Claude | fluxcd/agent-skills |
| terraform-skill | Terraform/OpenTofu guidance | Claude | antonbabenko/terraform-skill |
| wizard | a bash wizard for steps only a human can do | Claude | mattpocock/skills |
| research | `docs/research/<topic>.md` | Claude | mattpocock/skills |
| grilling | a sharpened plan (interview) | Claude | mattpocock/skills |
| domain-modeling | GLOSSARY.md, ADRs | Claude | mattpocock/skills |
| code-review | review findings | Claude | mattpocock/skills |
| tdd | tests and code, test-first | Claude | mattpocock/skills |
| prototype | a throwaway `prototype/<name>` branch | operator (demoted) | mattpocock/skills |
| find-skills | installed skills via npx | operator (demoted) | vercel-labs/skills |
| grill-me | a sharpened plan (interview) | operator | mattpocock/skills |
| grill-with-docs | ADRs and glossary entries, through grilling and domain-modeling | operator | mattpocock/skills |
| wayfinder | a map issue and decision tickets | operator | mattpocock/skills |
| to-spec | a spec issue | operator | mattpocock/skills |
| to-tickets | tickets with blocking edges | operator | mattpocock/skills |
| implement | a branch and commits, through tdd and code-review | operator | mattpocock/skills |
| implement-spec | PRs per ready ticket | operator | mattpocock/skills |
| triage | labels and agent-ready briefs on issues | operator | mattpocock/skills |
| handoff, claude-handoff | a handoff file; claude-handoff also starts a background session | operator | mattpocock/skills |
| retro | a retrospective | operator | mattpocock/skills |
| chief-of-staff | subagent results and wiki files | operator | mattpocock/skills |
| wait-what | a re-pitch of the last message | operator | mattpocock/skills |
| setup-matt-pocock-skills | tracker labels and doc layout (run once; done 2026-10-25, `docs/agents/*.md`) | operator | mattpocock/skills |
| ask-matt | nothing; off, it routes to skills not installed here | nobody | mattpocock/skills |
| hl-engineer (draft, not yet run) | approved tickets, a plan comment on the issue, a local state file | operator | ours |
| hl-plan-reviewer (agent, draft) | plan findings per lens; read-only | Claude, through hl-engineer | ours |
| hl-add-app (planned) | a PR with the app's manifests | operator (workflow) | ours |

## Hooks in force

| Hook | Event | Enforces |
| --- | --- | --- |
| `.claude/hooks/git-guard.sh` | PreToolUse on Bash | no merge, no push to main, no force push, no destructive local git |
| `.claude/hooks/issue-template.sh` | PreToolUse on Bash matching gh issue | the four headings in every issue body |
| `.claude/hooks/token-refresh.sh` | SessionStart; PreToolUse on Bash mentioning gh or git push | a fresh App token cache, minted outside the sandbox (never blocks) |
| `.claude/hooks/flow-review-bound.sh` | PreToolUse on Agent | at most 3 plan-review rounds per run; registered in settings so it holds in every session, subagents included |

## Sandbox

Mandatory on WSL2. The network allowlist in `.claude/settings.json` starts with every known host.
Sandboxed commands cannot reach the host's loopback, so the dev cluster API is bound to the WSL
interface address and that address and port are allowlisted; only the container runtime is excluded
from the sandbox, because its socket is unavoidable. Read access to the Windows drives, the SSH
directory and the App key directory is denied to the Read tool and the sandbox alike. Sandboxed
`gh` and `git push` use the one-hour App token cached in `$XDG_RUNTIME_DIR/homelab-app-token`,
which `token-refresh.sh` mints from the key outside the sandbox.

## Memory

Auto memory is off. Everything Claude should know is in git and reviewable: CLAUDE.md, rules, ADRs,
glossary, research files, reference skills. Subagent memory is unavailable as a result. Revisit
only if repeated corrections pile up faster than they are written down.

## Skill inventory

Claude Code's bundled skills are on only so that the bundled `/deep-research` workflow runs: every
bundled skill is `off` in `skillOverrides` in `.claude/settings.json`, so the skill list in a session
is the repository's (the downloaded ones below and ours) plus `/deep-research`. The overrides are a
denylist: after a Claude Code update, check `/skills` for new bundled entries and turn them off.
Bundled `/code-review` shares its name with the downloaded `code-review`, so it has no entry (an
entry would hit both); check `/skills` shows the downloaded one.

Downloaded (never edited; gitignored, restored from skills-lock.json at session start by
`skills-restore.sh`, which keeps a folder only if it matches the lock's hash; ADR 0017): the
Anthropic plugin-dev guides (skill, hook, agent development), skill-creator, writing-for-agents, the
planning suite from mattpocock/skills (ask-matt, grilling, grill-me, grill-with-docs, wayfinder,
to-spec, to-tickets, implement, implement-spec, triage, research, handoff, claude-handoff,
chief-of-staff, wizard, domain-modeling, code-review, prototype, tdd, retro, wait-what,
setup-matt-pocock-skills), the Flux gitops-knowledge skill, the Terraform/OpenTofu skill,
find-skills.

Ours (`hl-` prefix): `hl-engineer` (conductor, draft), `hl-add-app` (repeatable workflow, planned
after the KRO prototype). `hl-flow` was retired by ADR 0015.
