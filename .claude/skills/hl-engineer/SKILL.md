---
name: hl-engineer
description: Plan a deployment from one GitHub issue to approved, blocking-linked tickets, with checkpoints and operator gates. Usage: /hl-engineer <issue> | resume <issue> | <free-text request>
disable-model-invocation: true
argument-hint: "<issue> | resume <issue> | <free-text request>"
---

You are the **conductor** for one GitHub issue (`$ARGUMENTS`): you take it from intake to
approved tickets, then stop. Building is the next flow (`/implement` or `/implement-spec`, typed
by the operator). Every stage runs here in the main conversation, because only here can you ask
the operator. The design is ADR 0016; `docs/agents/harness.md` ("The engineer flow") is the map.

## Gates and checkpoints

- A **gate** is an `AskUserQuestion` with the options Approve, Revise, Stop and a summary of what
  is being approved. Keep the summary to one paragraph of at most about 120 words and point to the
  brief for the rest: the operator decides from the summary, and a wall of text hides the decision.
  Only an explicit Approve moves the flow on. Revise loops the stage with the operator's notes. A
  gate that closes without an answer counts as Stop.
- A **checkpoint** closes a stage without asking: you record it and carry on; the operator can
  interject.
- At every gate and checkpoint, in this order:
  1. write the stage's **brief** to `.flow/<n>/NN-<stage>.md` ([reference.md](reference.md),
     "Brief");
  2. update `.flow/<n>.json` (`stage`, `status`, `updated`);
  3. post one progress line on the issue: `gh issue comment <n> --body "hl-engineer: <stage>
     <approved|checkpoint|stopped>. <one sentence>"`. A gate that ends in Stop, the review bound
     included, posts `stopped` with the reason and `/hl-engineer resume <n>`, so the issue shows
     where the flow stands without the local state file;
  4. at a gate, once the operator has answered, append a row to the run record
     ([reference.md](reference.md), "Run record"). A Revise answer goes in verbatim as friction.
- **Push right**: ask the operator only at the gates below. Settle anything you can look up
  yourself (repo, ADRs, docs, research) or run yourself (a short experiment, see "Experiments")
  before you ask.
- The hidden skills (`to-tickets`, `to-spec`, `wayfinder`, `implement`) belong to the operator.
  When a stage needs one, name the exact command for the operator to type and end your turn.

## State

`.flow/<n>.json` is the cursor (gitignored, local); the issue and its comments are the durable
record.

```json
{"issue": 14, "stage": "plan", "status": "running", "max_rounds": 3,
 "review": {"Falsifier": 0, "Saboteur": 0, "Newcomer": 0},
 "started": "2026-10-25T11:40:00Z", "updated": "2026-10-25T12:00:00Z"}
```

`status` is `running`, `awaiting-operator`, `done` or `stopped`. Edit the file with `jq`, which the
review-bound hook reads it with. The hook owns `review`: never write it yourself. If you notice the
hook is not firing, say so in the brief and respect `max_rounds` by hand. Change `max_rounds` only
when the operator picks "more rounds" at the bound, and write into that gate's run-record row what
the operator expects the extra rounds to change: a raise with no stated purpose is how a loop runs
on without converging.

## Models

You run on the session model because the operator is here. Every subagent you spawn gets the
smallest model that does its job, because a flow that puts the session model on every lookup
costs more than it returns: Haiku for lookups (Explore in the repo and its docs; they locate, they
do not judge), Sonnet for research notes (bounded work with a brief in hand), Opus for the plan
reviewers (an adversarial judge is the one place where a weaker model is the expensive choice).
This is harness.md's model-tier rule; the reviewer's model lives in its agent file, the others go
on the Agent call.

## Briefs are pointers

A brief is decision-ready: pointers to ADRs, research notes and upstream docs, not copies of them.
The plan brief stays under 3,000 words; its review log (`03-review.md`) and its checks
(`03-checks.md`) live in their own files and do not count. Every other brief stays under 2,000.
Words are the measure, not lines: a 2,000-character table row is a copy, not a pointer. Three
reviewers read the plan in full every round and `to-tickets` turns it into tickets; a plan past
that size is doing the tickets' work.

Write a brief whole with the Write tool when it changes, rather than patching it with scripted
search-and-replace: a patch that misses its anchor fails silently or half-applies, and a brief
rewritten whole stays coherent.

## Checks

Every "done" is a **runnable check** on one line: `<command or action> → <expected signal>`, tagged
static (no cluster), dev (the kind cluster or dev runtime) or operator (only a human can observe
it; the action and what they see are still both written). One tag, no riders: a prerequisite such
as a tool goes into the command or the part's prerequisites line, never into the tag. No reference
to another check ("then run P1 check 3"): repeat the command. A multi-step check is several checks.
These are the seams `tdd` tests at; they are agreed before building because `/implement-spec` runs
agents that cannot ask.

At the plan stage the checks live in `.flow/<n>/03-checks.md` ([reference.md](reference.md),
"Checks file"), numbered and grouped by part, and the plan refers to them by number and says what
each proves. They sit outside the plan's word cap because a runnable check is exact by nature, and
exactness inside the plan is what pushes it past its cap while the reviewers ask for more of it.
Stage 4 copies them into the parts table.

## Experiments

When the flow needs to know how a tool behaves and no source settles it, run it rather than argue
it: a short run in the sandbox settles in minutes what reviewers and the conductor can debate for
rounds. Keep every experiment's files under `$TMPDIR/hl-proto/<n>/` and any build output in a
cache outside the repository, never in the repo or `.state/`. Record what was run, the versions
and the result in the research note the plan cites. End each experiment by removing what it made
and checking it is gone: `test -z "$(ls -A "$TMPDIR/hl-proto/<n>" 2>/dev/null)"` and `.state/`
unchanged (#22).

## Stages

**0 Intake.** `$ARGUMENTS` is `<n>`, `resume <n>`, or a free-text request.
- Resume, or `.flow/<n>.json` already exists: read it and the latest brief, set `status` to
  `running`, and continue at its stage. If the status was `awaiting-operator` or `stopped`, the
  stage's work is done and only its gate is pending: put the gate to the operator again, do not
  redo the stage.
- Free text, no issue yet: draft the issue in the four-heading template
  (`docs/agents/issue-tracker.md`) to `.flow/draft-<slug>.md`, show the operator the full text in
  the conversation (they may not be able to open the file), and create it with
  `gh issue create --title "..." --body-file <absolute path>` only on their confirmation, in a Bash
  call of its own (the issue-template hook reads the file before the command runs). Then continue
  as New with the issue's number.
- New: `gh issue view <n> --json number,title,body,labels,comments`. The body must carry Goal, Done
  when, Out of scope and Depends on; if it lacks one, tell the operator which and stop. Read
  `docs/adr/README.md`, every ADR the issue touches, CLAUDE.md's repo facts and the
  `docs/research/` notes on the topic. Confirm `docs/agents/issue-tracker.md` exists (to-tickets
  needs it). Create the state file with `started`. Brief `00-intake.md`. Done when you can name the
  ADRs this issue rests on.

**1 Prior art.** Before anyone designs, find out what is already settled: a plan that reinvents
an established pattern spends its review rounds rediscovering it, and a plan that cites one starts
where the field is. From the intake brief, write down the questions a practitioner would already
have answered, one line each, in the shape "how do Flux repositories validate manifests before a
cluster exists?": what others run for this, the established pattern, its known failure modes, and
whether an ADR or a research note here decided it already. A question an ADR answers gets the ADR
as its source and no agent. For the rest, spawn one background agent per question, all in one
message: Explore on Haiku when the answer lives in this repo and its docs (it returns pointers, it
does not judge), the `research` skill on Sonnet (`model: sonnet` on the Agent call) when it needs
upstream docs or the web, which leaves `docs/research/<topic>.md`, scored on the checklist in
[reference.md](reference.md) when a tool is involved. Four agents is the norm; more needs a
sentence in the brief saying why, because the spend here is bounded by the question list, not by
curiosity. A question only a run can answer (does this tool work in the sandbox, what does it do
on an empty input, which host does it download from) is answered by an experiment
("Experiments") before the plan rests on it; the plan that guesses at tool behaviour spends its
review rounds on the guess. Write `01-prior-art.md` ([reference.md](reference.md), "Prior-art
brief") from what comes back: per question, the established solution, its source, and what it
settles or rules out for this issue. A question nobody could source is marked unanswered, not
filled from memory. The plan cites each block or says why it deviates. Done when every question
has a sourced or measured answer or is marked unanswered. **Checkpoint.**

**2 Requirements.** Invoke the `grilling` skill on the issue. Look facts up yourself, with Explore
subagents (`model: haiku`) for wide searches, and ask the operator only what the repo cannot
answer. When the issue changes the harness, the dev environment, CI or repo tooling, put the
trust-boundary questions in the first round, because their answers reshape the design and are
expensive to discover in review:
- which code runs outside the Claude sandbox, and who runs it (the operator's shell, a hook, CI);
- whose checkout is whose: does the operator work in Claude's checkout or in their own clone;
- where each tool comes from and how it is invoked (a pinned build-system run, a system package,
  a script in the repo);
- what CI runs from an unreviewed pull request, and with which credentials;
- which paths Claude can write that later run unsandboxed or with the operator's privileges.
When a term or a decision settles, invoke `domain-modeling` to record it (GLOSSARY.md, a new ADR).
Done when every branch of the design tree is answered or written down as an open question. Brief
`02-requirements.md`. **Gate.**

**3 Plan.** Write `03-plan.md`: two or three options, a recommendation, and for the recommendation
the ADRs it rests on, the prior art it follows or leaves, rollout on dev then prod, verification
(pointing at `03-checks.md`), deletion safety, image architectures and the secrets path. Copy the
issue's Goal and Done when into it; the reviewers cannot run `gh`. If the plan needs the issue's
Done when changed, write the new wording in an "Amendments" block in the plan: it is approved with
the plan at the gate and applied to the issue at publish, never edited silently. Then the **review
loop**:
1. In one message, spawn three `hl-plan-reviewer` agents (Opus, set in the agent file). Each
   prompt's first line is `Lens: Falsifier`, `Lens: Saboteur` or `Lens: Newcomer`; the second line
   is the brief's path. From round 2 on, a third line names the text changed since the last round,
   the new surfaces first, so each lens starts where the risk is.
2. Act on every finding: fix the plan or the checks, or rebut it. When a finding turns on a tool's
   behaviour that a short run can settle, run it ("Experiments") and fix or rebut on the result.
   Every finding, fixed or rebutted, gets its line in `03-review.md` ([reference.md](reference.md),
   "Review log"), which keeps the whole history; the plan itself carries no log. A fix replaces the
   text it corrects; it does not add a paragraph beside it, or the brief grows with every round and
   the next round finds more. Prefer the fix that removes a mechanism to the one that adds one:
   every mechanism a fix adds is new text for the next round to break. When a fix does add one (a
   new script, hook, wrapper, config layer or guard), mark its log line `new surface`.
3. Repeat with all three lenses until all three pass. Rerun every lens, not only the ones that
   failed: a fix made for one lens can break what another lens passed. A lens passes on a round with
   no blocker or major; minors are fixed but do not hold the loop open (the reviewer agent's
   severity rubric). After each round, count the blockers and majors in `03-review.md`. If they have
   not fallen by at least 30% over the last two rounds, the plan is too big or too undecided: say so
   at the next gate, name the theme the recurring findings share, and recommend cutting an option,
   moving a part into its own issue, or deciding the open question with the operator, instead of
   writing more.
4. If the hook blocks a launch, the bound is reached: gate with Approve as is, More rounds, Revise
   yourself, Stop. Say in the brief's Open section which findings the last, unreviewed revision
   addresses, so the operator approves it knowing that.

Done when every lens passed, or the operator chose at the bound. **Gate.**

**4 Breakdown.** Cut the plan into **vertical slices**: each part verifiable alone on dev, on the
feature's branch. The parts are tickets of one feature: they land on the spec's integration branch
in dependency order and ship as one PR, so a part's prerequisites name that branch, never a merge.
A check that needs the feature on `main` (a required status check, a step in the operator clone, a
hook installed after the merge) is a **post-merge** check: it sits in the last part and runs once
the operator has merged. A part that only records a decision (an ADR update) is allowed, last, with static and
operator checks. Write `04-parts.md` as a table: part, what it delivers, depends on, tool choice
(`ADR-fixed: <ADR>` or `open`), runnable checks copied from `03-checks.md` and written out in the
cell. Breaking a plan down often finds it wrong in places: record each correction under
`## Plan amendments` with its source. An amendment that changes deletion safety, the fence, an
option or the recommendation is not a breakdown decision: run the Saboteur lens once on the
amended parts before the checkpoint (it counts toward the bound; if the bound blocks it, gate).
Mark an amendment `reviewed: Saboteur round <r>` only after that run returns, and do not reword it
afterwards; a reworded amendment is unreviewed again. Post the checkpoint comment only when the
brief is final; a later correction goes into the next brief. Done when every Done-when check of the
issue maps to a part and every part has at least one runnable check. **Checkpoint.**

**5 Adopt or build.** For each part whose tool choice is `open`, list the candidate tools (plus
"build" when building is realistic). In one message, invoke the `research` skill once per
candidate, asking for `docs/research/<tool>.md` scored on the checklist in
[reference.md](reference.md); each research agent runs on Sonnet (`model: sonnet` on the Agent
call). A prior-art note from stage 1 that already scored the tool is reused, not redone. Parts
fixed by an ADR cite it and get no verdict. A part is open when its tool column says `open`, and
it gets exactly one verdict (adopt one tool, build, or find another) however many candidates were
researched. Write the verdict table to `05-verdicts.md`. If a verdict reshapes the parts, go back
to stage 4. Done when every open part has one verdict. **Gate.**

**6 Publish.** Apply any amendments the plan gate approved to the issue body: write the new body
to a file, then `gh issue edit <n> --body-file <absolute path>` in a Bash call of its own. Post the
approved plan as one comment on the issue ([reference.md](reference.md), "Plan comment"); it is
what `to-tickets` reads. List the files this run changed in the working tree (research notes,
ADRs, glossary, the run record) and leave committing them to the operator. Set `stage` to
`publish` and `status` to `awaiting-operator`, then end your turn with:
`Type /to-tickets <n> to publish the tickets, then /hl-engineer resume <n>.`

**7 Close-out** (on resume after `to-tickets`). For each new sub-issue of `<n>`, check the four
headings, the parent link, that its native blocked-by edges match `04-parts.md`, and that its
`## Done when` kept the part's runnable checks word for word. Report every gap and the fix.
**Gate**; on Approve set `status` to `done` and name the next step: `/implement <ticket>` for one
ticket, `/implement-spec <n>` for all of them.

## Measuring the skill in use

This skill is judged on real issues, not on rehearsals. The run record
(`docs/agents/hl-engineer-runs.md`, tracked) collects one row per gate: what the operator answered,
how many review rounds and findings it took, how big the briefs were, how long the stage ran, and
the operator's words when they chose Revise. After every third run the operator types `/retro`
over that file and the assertions in `evals/evals.json`, and the skill changes only on what the
rows show. Record honestly: a row that flatters the skill hides the next fix.
