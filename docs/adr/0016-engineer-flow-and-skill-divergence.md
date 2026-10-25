# 0016 The engineer flow ends at tickets; divergences from downloaded skills climb a ladder

Date: 2026-10-25

Supersedes, in ADR 0014, the clause "plain stops at human gates" in the flows bullet. Supersedes,
in ADR 0015, the `skillOverrides` sentence in the visibility bullet, the handover sentence in the
gated-flows bullet, and the consequence "Downloaded skills are not forked to make them callable".
The rest of both stands.

## Context

The research notes [hl-engineer-flow.md](../research/hl-engineer-flow.md) and
[skill-divergence.md](../research/skill-divergence.md) (2026-10-25, Claude Code docs and the
upstream skill repositories) tested the `hl-engineer` sketch in `docs/agents/harness.md` and asked
how far this repo may bend the downloaded skills. Their findings:

- Only the main conversation can ask the operator mid-flow. Subagents and `context: fork` skills
  lose `AskUserQuestion`; workflows take no input mid-run.
- Of the stages the operator wants (requirements, plan, breakdown, adopt-or-build, tickets), only
  publishing the tickets needs a hidden skill. `grill-with-docs` only chains `grilling` and
  `domain-modeling`, which Claude may call; `research` is visible.
- A skill's Stop hook stays registered for the rest of the session and fires at every turn end,
  gates included, so it cannot bound a loop that pauses for the operator.
- `handoff` is hidden and writes to `$TMPDIR`, so a conductor cannot use it for `.flow/` handovers.
- `skillOverrides` has four values (`on`, `name-only`, `user-invocable-only`, `off`). All of them
  set visibility; none changes a skill's text, and none is documented to un-hide a skill whose
  author set `disable-model-invocation: true`.
- The `skills` CLI replaces a skill folder whenever upstream changes and never compares local
  files, so an edit to a downloaded skill is lost without warning. Upstream's customization surface
  is `docs/agents/*.md` and CLAUDE.md; anything further is a fork.
- The ticket templates of `to-tickets`, `to-spec` and `wayfinder` lack the four headings that
  `issue-template.sh` requires, and `to-spec` writes `## Out of Scope`, which the case-sensitive
  hook rejects.

## Decision

- `hl-engineer` runs from one GitHub issue to approved tickets and stops. Building, code review and
  triage are not part of it; `/implement` or `/implement-spec` take over from the tickets.
- Stages, all in the main conversation:
  1. Requirements: `grilling` and `domain-modeling`, called by the conductor. Gate.
  2. Plan: a draft, reviewed by the read-only `hl-plan-reviewer` agent in three parallel lenses:
     Falsifier (what evidence would prove the plan wrong, against the ADRs and research notes),
     Saboteur (how it breaks the cluster: deletion, secrets, architecture, drift) and Newcomer
     (could someone without this conversation carry out each part). The conductor revises and
     repeats, at most 3 rounds; a `PreToolUse` hook on `Agent` counts rounds and denies the fourth.
     Gate.
  3. Breakdown into parts. Checkpoint.
  4. Adopt-or-build per part. A part whose tool an ADR already fixes cites the ADR. Otherwise each
     candidate tool gets its own `research` run, in parallel, scored against the checklist in
     harness.md; a verdict can send the flow back to stage 3. Gate.
  5. Publish: the conductor posts the approved plan as one comment on the source issue and names
     `/to-tickets <issue>` for the operator to type. Tickets are native sub-issues of the source
     issue with native blocking links, and `## Depends on` repeats the same references.
- Gates are `AskUserQuestion` prompts (approve, revise, stop) inside the conductor's turn.
  `askUserQuestionTimeout` stays unset so an unanswered gate never continues on its own. A typed
  command is needed only where the stage belongs to an author-hidden skill.
- At every checkpoint the conductor posts a one- or two-line progress comment on the source issue.
- State is `.flow/<issue>.json` plus checkpoint briefs in `.flow/<issue>/`, both gitignored and
  written by the conductor itself. The durable record is the issue and its comments.
- Divergences from downloaded skills climb a ladder, one rung at a time, recording which failure
  moved them up:
  1. Configure: `docs/agents/*.md` and CLAUDE.md.
  2. Enforce: hooks that block with a reason, or add context when a skill is typed.
  3. Restrict: `skillOverrides`, only to hide or demote, by the ADR 0015 visibility rule.
  4. Route around: an `hl-` skill does the step from visible skills, the hidden skill stays an
     operator gate, or the skill is dropped.
  5. Fork: an `hl-` copy that records the upstream commit and hash in its `metadata`, with the
     original installed but `off` as the baseline. Each fork needs its own ADR. A fork that acts
     on the world stays hidden.
- Current `skillOverrides`: `prototype` and `find-skills` are `user-invocable-only`; `ask-matt` and
  `plugin-authoring` are `off`.
- The four-heading mapping lives in `docs/agents/issue-tracker.md` (rung 1), backed by
  `issue-template.sh` (rung 2). `handoff` is dropped from the flow (rung 4).

## Consequences

- One typed command per run (`/to-tickets`), at the point where the operator approves the plan
  anyway.
- Whether `to-tickets`, `to-spec` and `wayfinder` follow the mapping over their own templates is
  unverified. The first dry run settles it; if they ignore it, the next step is a
  `UserPromptExpansion` hook, not a fork.
- On 2026-10-25 Claude wrote `docs/agents/*.md`, the CLAUDE.md "Agent skills" block and the triage
  labels from the `setup-matt-pocock-skills` templates, on the operator's instruction. That was a
  one-off; Claude does not otherwise reproduce what a hidden skill does.
- Not yet decided: where research notes and ADRs from a run land before a PR, and a concrete test
  for "passing security audits" in the adopt-or-build checklist.
