# 0015 Skill visibility by the documented rule; the router retired; two flow tiers

Date: 2026-10-24

Supersedes one bullet of ADR 0014: "The hl-flow router is the single entry point and calls
exactly one skill." The rest of 0014 stands.

## Context

ADR 0014 made `hl-flow`, a user-invoked router skill, the single entry point for multi-stage
work, and CLAUDE.md listed it. More flows were planned, and a list in CLAUDE.md does not scale.
The official Claude Code docs (skills, memory, settings, interactive-mode, commands, workflows
pages) and the downloaded `writing-for-agents` skill, read on 2026-10-24, settle how routing
works:

- There is no router or index concept. Every model-visible skill's name and description is in
  context, and Claude picks by description. CLAUDE.md is for what applies every session.
- Model visibility and human visibility are separate. A skill hidden from Claude
  (`disable-model-invocation: true`, or `skillOverrides: user-invocable-only`) stays in the `/`
  menu, filtered by typing letters; `/skills` filters by name, description and source.
- The documented reason to hide a skill from Claude is side effects or timing: "workflows with
  side effects ... like /commit or /deploy". The author of the sixteen downloaded hidden skills
  applies the same rule and left the analysis skills model-invocable because other skills reach
  them.
- A hidden skill cannot be called by another skill: "If Claude tries anyway, Claude Code blocks
  the call." It cannot be preloaded into a subagent either. So `hl-flow` could never dispatch
  to `research` or `wayfinder`, and this repo's demotion of `grilling`, `domain-modeling`, `tdd`
  and `code-review` broke the chains inside `grill-with-docs` and `implement`.
- The listing budget is 1% of the context window; all installed descriptions total about 6,100
  characters, far below it. Budget is not a reason to hide anything here.
- Workflows take no input mid-run: "For sign-off between stages, run each stage as its own
  workflow." State across sessions is files, issues and pull requests.
- LangChain and LangGraph do not appear in Anthropic's documentation. Orchestrating outside
  Claude Code would bypass the sandbox, hooks, permissions and skills. The documented path for
  orchestration in code is the Agent SDK, the same harness in Python or TypeScript.

## Decision

- Visibility follows the documented rule. A skill is visible to Claude if it reads, analyzes,
  advises, or is reached by another skill. It is hidden, and typed by the operator, if it acts
  on the world (issues, branches, PRs, installs). `skillOverrides` demotes only `prototype`
  (creates a branch) and `find-skills` (installs packages); `ask-matt` is off because it routes
  to skills that are not installed. Author-hidden skills stay as the author set them.
- `hl-flow` is retired. Its "read the ADR index first" rule is one line in CLAUDE.md; the
  choice between `wayfinder` and `grill-with-docs` is in those skills' descriptions.
- CLAUDE.md never lists skills or flows. The human catalog is `docs/agents/harness.md`.
- Two flow tiers:
  - Repeatable flows (for example adding an app: research, write manifests, validate, open a
    PR) are saved workflows in `.claude/workflows/<name>`, run as `/<name> <args>`. Their stages
    are our own visible skills or prompts in the script. The PR review is the gate.
  - Gated flows (for example `hl-engineer`) are conductor skills, hidden and typed. An
    unattended stage is a workflow the conductor launches. A stage owned by an author-hidden
    skill is a human gate: the conductor writes the handover, updates `.flow/<run>.json`, names
    the skill to type, and resumes on `/<conductor> resume`. A conductor never calls a hidden
    skill.
- Orchestration stays inside Claude Code. If orchestration in code is ever needed, the Agent
  SDK is the path. No LangChain or LangGraph.

## Consequences

- A description-based pick can be wrong. Mitigation: descriptions that say when not to use the
  skill, and side-effecting skills hidden so a wrong pick cannot act.
- Each human gate in a gated flow costs the operator one typed command, at a point where a
  decision was due anyway.
- Downloaded skills are not forked to make them callable. If that ever becomes necessary, it is
  a new decision with a maintenance cost.
- The `/hl-flow research <topic>` check in ticket #3 is closed as "retired by this ADR".
