# 0014 The Claude Code harness: sandbox, skills, hooks, memory, flows

Date: 2026-10-24

## Context

Claude Code is the main builder. Anthropic's guidance: start with CLAUDE.md and built-ins, add each
extension when its trigger appears; keep CLAUDE.md under 200 lines; procedures go to skills;
guardrails go to hooks; auto memory is per user and outside git. The full architecture is in
`docs/agents/harness.md`; this ADR records the decisions.

## Decision

- Sessions run in Claude Desktop's WSL mode on a Debian distro with the Bash sandbox mandatory.
  The allowlist starts with every known host and grows one line per tool. Only the container
  runtime is excluded from the sandbox; the dev cluster API is bound to the WSL interface address
  so cluster tools stay sandboxed. Read access to the Windows drives, the SSH directory and the App
  key directory is denied.
- Auto memory is off. Knowledge lives in git: CLAUDE.md for always-on rules, `.claude/rules` for
  scoped guidance, ADRs and the glossary for decisions and terms, research findings files for
  gathered facts, reference skills for component knowledge. Subagent memory is therefore
  unavailable; accepted.
- Skills: downloaded skills are the entries in skills-lock.json, never edited; our own carry the
  hl- prefix; overlapping downloaded skills are demoted with skillOverrides in settings. A plugin
  is made only when a second repository needs the setup.
- One skill per stage: research through the research skill; planning through wayfinder or
  grill-with-docs; breakdown through to-tickets; documenting through domain-modeling via
  grill-with-docs. The hl-flow router is the single entry point and calls exactly one skill.
- Hooks enforce: the merge guard (ADR 0013) and the issue template (Goal, Done when, Out of scope,
  Depends on).
- Flows are conductor skills with a state file as source of truth, one suite skill per stage,
  handovers at every stage boundary, hook-enforced loops with a per-run bound, plain stops at human
  gates, and implement-spec as the separate parallel build flow. Dynamic workflows are used only for
  stages with no sign-off inside them.

## Consequences

- The first artifact in the repository is this harness skeleton, before any homelab code.
- Nothing learns across sessions unless written down. That is the point.
