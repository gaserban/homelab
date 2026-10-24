---
name: hl-engineer
description: Plan a deployment from one GitHub issue to approved, blocking-linked tickets, with checkpoints and operator gates. Usage: /hl-engineer <issue> | resume <issue>
disable-model-invocation: true
argument-hint: "<issue> | resume <issue>"
hooks:
  PreToolUse:
    - matcher: "Agent"
      hooks:
        - type: command
          command: "bash .claude/hooks/flow-review-bound.sh"
---

You are the **conductor** for one GitHub issue (`$ARGUMENTS`): you take it from intake to
approved tickets, then stop. Building is the next flow (`/implement` or `/implement-spec`, typed
by the operator). Every stage runs here in the main conversation, because only here can you ask
the operator. The design is ADR 0016; `docs/agents/harness.md` ("The engineer flow") is the map.

## Gates and checkpoints

- A **gate** is an `AskUserQuestion` with the options Approve, Revise, Stop and a one-paragraph
  summary of what is being approved. Only an explicit Approve moves the flow on. Revise loops the
  stage with the operator's notes. A gate that closes without an answer counts as Stop.
- A **checkpoint** closes a stage without asking: you record it and carry on; the operator can
  interject.
- At every gate and checkpoint, in this order:
  1. write the stage's **brief** to `.flow/<n>/NN-<stage>.md` ([reference.md](reference.md),
     "Brief");
  2. update `.flow/<n>.json` (`stage`, `status`, `updated`);
  3. post one progress line on the issue: `gh issue comment <n> --body "hl-engineer: <stage>
     <approved|checkpoint>. <one sentence>"`.
- **Push right**: ask the operator only at the gates below. Settle anything you can look up
  yourself (repo, ADRs, docs, research) before you ask.
- The hidden skills (`to-tickets`, `to-spec`, `wayfinder`, `implement`) belong to the operator.
  When a stage needs one, name the exact command for the operator to type and end your turn.

## State

`.flow/<n>.json` is the cursor (gitignored, local); the issue and its comments are the durable
record.

```json
{"issue": 14, "stage": "plan", "status": "running", "max_rounds": 3,
 "review": {"Falsifier": 0, "Saboteur": 0, "Newcomer": 0}, "updated": "2026-10-25T12:00:00Z"}
```

`status` is `running`, `awaiting-operator`, `done` or `stopped`. The review-bound hook owns
`review`. Change `max_rounds` only when the operator picks "more rounds" at the bound.

## Stages

**0 Intake.** `$ARGUMENTS` is `<n>` or `resume <n>`.
- Resume, or `.flow/<n>.json` already exists: read it and the latest brief, set `status` to
  `running`, and continue at its stage.
- New: `gh issue view <n> --json number,title,body,labels,comments`. The body must carry Goal, Done
  when, Out of scope and Depends on; if it lacks one, tell the operator which and stop. Read
  `docs/adr/README.md`, every ADR the issue touches, CLAUDE.md's repo facts and the
  `docs/research/` notes on the topic. Confirm `docs/agents/issue-tracker.md` exists (to-tickets
  needs it). Create the state file. Done when you can name the ADRs this issue rests on.

**1 Requirements.** Invoke the `grilling` skill on the issue. Look facts up yourself, with Explore
subagents for wide searches, and ask the operator only what the repo cannot answer. When a term or
a decision settles, invoke `domain-modeling` to record it (GLOSSARY.md, a new ADR). Done when
every branch of the design tree is answered or written down as an open question. Brief
`01-requirements.md`. **Gate.**

**2 Plan.** Write `02-plan.md`: two or three options, a recommendation, and for the recommendation
the ADRs it rests on, rollout on dev then prod, verification, deletion safety, image architectures
and the secrets path. Copy the issue's Goal and Done when into it; the reviewers cannot run `gh`.
Write every "done" as a **runnable check**: `command → expected signal`, tagged static (no
cluster), dev (the kind cluster) or operator (only a human can observe it). These checks are the
seams `tdd` tests at; they are agreed here because `/implement-spec` runs agents that cannot ask.
Then the **review loop**:
1. In one message, spawn three `hl-plan-reviewer` agents. Each prompt's first line is
   `Lens: Falsifier`, `Lens: Saboteur` or `Lens: Newcomer`; the second line is the brief's path.
2. Act on every finding: fix the plan, or rebut it in the brief's review log with the reason.
3. Repeat with the lenses that did not pass, until all three pass.
4. If the hook blocks a launch, the bound is reached: gate with Approve as is, More rounds, Revise
   yourself, Stop.

Done when every lens passed, or the operator chose at the bound. **Gate.**

**3 Breakdown.** Cut the plan into **vertical slices**: each part deployable and verifiable alone
on dev. Write `03-parts.md` as a table: part, what it delivers, depends on, tool choice
(`ADR-fixed: <ADR>` or `open`), runnable checks. Done when every Done-when check of the issue maps
to a part and every part has at least one runnable check.
**Checkpoint.**

**4 Adopt or build.** For each part whose tool choice is `open`, list the candidate tools (plus
"build" when building is realistic). In one message, invoke the `research` skill once per
candidate, asking for `docs/research/<tool>.md` scored on the checklist in
[reference.md](reference.md). Parts fixed by an ADR cite it and get no verdict. Write the verdict
table to `04-verdicts.md`. If a verdict reshapes the parts, go back to stage 3. Done when every
open part has one verdict. **Gate.**

**5 Publish.** Post the approved plan as one comment on the issue ([reference.md](reference.md),
"Plan comment"); it is what `to-tickets` reads. List the files this run changed in the working tree
(research notes, ADRs, glossary) and leave committing them to the operator. Set `stage` to
`publish` and `status` to `awaiting-operator`, then end your turn with:
`Type /to-tickets <n> to publish the tickets, then /hl-engineer resume <n>.`

**6 Close-out** (on resume after `to-tickets`). For each new sub-issue of `<n>`, check the four
headings, the parent link, that its native blocked-by edges match `03-parts.md`, and that its
`## Done when` kept the part's runnable checks word for word. Report every
gap and the fix. **Gate**; on Approve set `status` to `done` and name the next step:
`/implement <ticket>` for one ticket, `/implement-spec <n>` for all of them.
