# The hl-engineer flow: skill, subagent or workflow

Checked 2026-10-25 against the official Claude Code docs (code.claude.com/docs, fetched the same day),
the local skills in `.claude/skills/`, and the upstream repositories `mattpocock/skills` and
`anthropics/claude-code`. The design sketched in [harness.md](../agents/harness.md) ("The engineer
flow", "Flow model") was the hypothesis under test. ADRs [0014](../adr/0014-agent-harness.md) and
[0015](../adr/0015-skill-visibility-and-routing.md) frame it.

Question, from the operator: how to build the engineer/architect skill, agent or workflow that takes
a created issue (for example "add Flux") and then:

1. gathers all requirements;
2. plans the solution (checkpoint, review loop, operator gate);
3. breaks the solution into smaller parts (checkpoint);
4. researches, per part, whether to adopt a tool or build (checkpoint);
5. writes the plan the way the repo says (as issues), with a checkpoint and a gate.

## Short answer

- **Build a conductor skill, plus one read-only reviewer subagent and one hook. No workflow yet.**
  The operator gates need `AskUserQuestion` or a typed reply, and grilling needs a live exchange.
  Only the main conversation offers either. Subagents lose `AskUserQuestion` and `Workflow`.
  Workflows take no input mid-run. A `context: fork` skill runs as a subagent, so it has the same
  limits.
- **Scope: the flow runs from an issue to approved tickets and stops there.** The operator's flow
  ends at "write the plan as issues". The build, code-review and triage stages in harness.md stay
  out of it: `/implement` or `/implement-spec`, typed by the operator, take over from the tickets.
- **Only one stage needs the operator to type a skill: publishing the tickets (`/to-tickets`).**
  `grill-with-docs` is hidden, but all it does is call `grilling` and `domain-modeling`. Both are
  model-visible, so the conductor calls them itself. `research` is visible too.
- **The review loop reviews the plan, not code.** The conductor gives the draft to
  `hl-plan-reviewer`, a subagent that can read but not edit. It revises and repeats, for N rounds
  at most. The bound is a `PreToolUse` hook on `Agent` that counts rounds in the state file. A Stop
  hook would not work here: a skill's Stop hook stays registered for the rest of the session and
  fires at every turn end, including the operator gates.
- **Fix one prerequisite first: the tracker config.** `/setup-matt-pocock-skills` has not been
  run, so `docs/agents/issue-tracker.md` does not exist. The ticket templates of `to-tickets`,
  `to-spec` and `wayfinder` also lack the four headings, so `issue-template.sh` would block every
  issue they create. Map the templates to Goal / Done when / Out of scope / Depends on in
  `docs/agents/issue-tracker.md`. That file is the skills' documented extension point, so the
  downloaded skills stay unedited.
- **State: a local cursor plus one durable record.** `.flow/<issue>.json` is gitignored and works
  as a cursor. The durable record is the approved-plan comment on the source issue. It is also the
  input to `/to-tickets <issue>`, which makes each new ticket a sub-issue of the source issue.
- **Nothing exists that could be adopted whole.** Neither upstream repository has a planning
  conductor that ends in tickets. Two pieces are worth borrowing: the parallel architect angles from
  Anthropic's `feature-dev` plugin, and the checkpoint/brief vocabulary from mattpocock's in-progress
  `loop-me`.

### Files to create

| File | What |
| --- | --- |
| `.claude/skills/hl-engineer/SKILL.md` | The conductor: hidden, typed by the operator. Steps only; the important rules go near the top (see compaction below) |
| `.claude/skills/hl-engineer/reference.md` | Checkpoint brief template, the plan-review rubric, the adopt-or-build checklist (disclosed reference) |
| `.claude/agents/hl-plan-reviewer.md` | The read-only plan reviewer |
| `.claude/hooks/flow-review-bound.sh` | `PreToolUse` on `Agent`: increments the round, denies past N |
| `docs/agents/issue-tracker.md` | GitHub tracker plus the four-heading mapping (through `/setup-matt-pocock-skills` or by hand) |
| `docs/agents/harness.md` | Update "The engineer flow" (see "Where harness.md holds and where it changes" below) |

Frontmatter sketch:

```yaml
# .claude/skills/hl-engineer/SKILL.md
---
name: hl-engineer
description: Plan a deployment from a GitHub issue to approved, blocking-linked tickets, with checkpoints and operator gates.
disable-model-invocation: true
argument-hint: "<issue-number> | resume <issue-number>"
hooks:
  PreToolUse:
    - matcher: "Agent"
      hooks:
        - type: command
          command: "bash .claude/hooks/flow-review-bound.sh"
---
```

```yaml
# .claude/agents/hl-plan-reviewer.md
---
name: hl-plan-reviewer
description: Read-only review of an hl-engineer solution plan against the ADRs, CLAUDE.md repo facts and the issue. Returns pass, or numbered findings with the rule each breaks.
tools: Read, Grep, Glob, WebFetch
skills: [gitops-knowledge]
maxTurns: 30
---
```

The hook reads `tool_input.subagent_type` and exits 0 for any other agent type. For
`hl-plan-reviewer` it finds the run in `.flow/` with `status: running`, then denies with exit 2 and
"review bound reached: stop and ask the operator" once `round >= max_rounds`. Otherwise it
increments `round`. Because the hook keeps the count, the model never has to.

### Stage table

| # | Operator stage | Primitive | Gate | Checkpoint artifact |
| --- | --- | --- | --- | --- |
| 0 | Intake: `/hl-engineer <n>` | Conductor (main conversation). Reads the issue, `docs/adr/README.md` and CLAUDE.md | Refuses if the issue lacks the four headings | `.flow/<n>.json` (stage, status, round, max_rounds, links) |
| 1 | Gather requirements | `grilling` + `domain-modeling` through the Skill tool; Explore subagents look up facts | Operator: grilling's "shared understanding confirmed", then `AskUserQuestion` (Approve / Revise / Stop) | `.flow/<n>/01-requirements.md`; GLOSSARY/ADR edits from domain-modeling |
| 2 | Plan the solution | Conductor drafts 2-3 options and a recommendation, then the review loop with `hl-plan-reviewer`, at most N rounds | Review loop, then operator `AskUserQuestion` | `02-solution.md`, with the review log |
| 3 | Break into parts | Conductor, using vertical slices: each part deployable and verifiable alone | Checkpoint only; the operator can interject | `03-parts.md` (part, what it delivers, depends on) |
| 4 | Adopt or build, per part | `research` skill (background agents), one per part that has an open tool choice. A part whose tool an ADR already fixes (Flux: ADR 0002) cites the ADR and skips the verdict | Checkpoint. A verdict that changes the parts sends the flow back to stage 3 | `docs/research/<tool>.md` per tool; verdict table in `04-verdicts.md` |
| 5 | Write as issues | Conductor posts the consolidated plan as a comment on issue `<n>`. Then the operator types `/to-tickets <n>`, which quizzes the breakdown until the operator approves | Operator `AskUserQuestion` "publish?", then the typed command, then to-tickets' own quiz | Sub-issues of `<n>` with the four headings and native blocked-by edges |
| 6 | Close-out | Conductor checks every ticket for the headings, the parent link and the edges, then sets status `done` | Operator confirms | State `done`; next step `/implement` or `/implement-spec` (typed by the operator) |

## Findings

### Which primitive fits (question 1)

- **Hidden skills cannot be invoked by Claude, so other skills cannot reach them either.**
  Verified. `disable-model-invocation: true`: "Claude can't invoke the skill on its own ... If
  Claude tries anyway, Claude Code blocks the call and instructs it not to reproduce the deploy
  steps another way"
  ([skills: control who invokes](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill)).
  Such a skill also cannot be preloaded into a subagent: "You can't preload skills that set
  `disable-model-invocation: true`"
  ([sub-agents: preload skills](https://code.claude.com/docs/en/sub-agents#preload-skills-into-subagents)).
  So the conductor must not read `to-tickets/SKILL.md` and follow it either: that is "reproduce
  another way".
- **Visible skills can be called from the conductor.** "By default, Claude can invoke any skill
  that doesn't have `disable-model-invocation: true` set"
  ([skills: restrict access](https://code.claude.com/docs/en/skills#restrict-claudes-skill-access)).
  `grill-with-docs` (hidden) is the one line "Call the Skill tool twice, for "grilling" and
  "domain-modeling"" (local `.claude/skills/grill-with-docs/SKILL.md`), and both of those skills
  are visible.
- **Hidden skills can still be typed or named by the operator.** A name at the start of a message
  runs the skill. Placed after plain text, "the name counts as your permission for that message:
  Claude can run the skill while it responds"
  ([skills: where you write the skill's name](https://code.claude.com/docs/en/skills#where-you-write-the-skills-name)).
  A gate reply such as "approved, /to-tickets 14" would therefore be the operator's own consent.
  Unverified for hidden skills: the invocation table says only "Not on its own".
- **Workflows take no input mid-run.** Verified: "No mid-run user input ... For sign-off between
  stages, run each stage as its own workflow"
  ([workflows: behavior and limits](https://code.claude.com/docs/en/workflows#behavior-and-limits)).
  Workflows are for "more agents than one conversation can coordinate"; subagents suit "a few
  delegated tasks per turn"
  ([workflows: when to use](https://code.claude.com/docs/en/workflows#when-to-use-a-workflow)).
  A planning flow with one reviewer per round is the subagent case.
- **Subagents cannot hold gates.** Every subagent loses `AskUserQuestion`, `EnterPlanMode` and
  `Workflow`, even when they are listed in `tools`
  ([sub-agents: available tools](https://code.claude.com/docs/en/sub-agents#available-tools)). A
  `context: fork` skill "starts a new subagent ... doesn't see your conversation history" and runs
  in the background by default
  ([skills: run skills in a subagent](https://code.claude.com/docs/en/skills#run-skills-in-a-subagent)).
  The conductor therefore runs inline. `context: fork` fits only unattended steps.
- **Rejected alternatives.**
  - `/goal`: its evaluator "doesn't run commands or read files independently", and only one goal
    can be active per session ([goal](https://code.claude.com/docs/en/goal)).
  - Agent-type hooks: "experimental"
    ([hooks: agent-based hooks](https://code.claude.com/docs/en/hooks#agent-based-hooks)).
  - Plan mode: it blocks edits, so the conductor could not write its checkpoint files
    ([permission modes: plan mode](https://code.claude.com/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode)).

### Gates, checkpoints and the review loop (question 2)

- **Operator gate.** `AskUserQuestion` in the main conversation. "Questions stay open until you
  answer them" unless `askUserQuestionTimeout` is set. With the timeout set, the dialog closes and
  "Claude proceeds on its own judgment"
  ([tools reference: AskUserQuestion](https://code.claude.com/docs/en/tools-reference#askuserquestion-tool-behavior)).
  Keep the timeout unset, and state in the skill that a timed-out gate is not approval. Anthropic
  recommends the same tool for requirement interviews
  ([best practices: let Claude interview you](https://code.claude.com/docs/en/best-practices#let-claude-interview-you)).
- **Hooks in skill frontmatter exist.** Claude Code "registers them when you or Claude invoke the
  skill and keeps running them for the rest of the session". `once: true` is honoured only in
  skill frontmatter
  ([hooks: hooks in skills and agents](https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents);
  [common fields](https://code.claude.com/docs/en/hooks#common-fields)). That session-long lifetime
  is why the bound hook must key on the `.flow/` state and do nothing when no run is active.
- **Why not a Stop hook.** A Stop hook "runs when the main Claude Code agent has finished
  responding". It blocks with `decision: "block"`, and an "8-consecutive-continuation cap"
  applies ([hooks: Stop](https://code.claude.com/docs/en/hooks#stop)). A conductor Stop hook would
  fire at every gate, so it would have to read the state to stay out of the way. The `PreToolUse`
  input for `Agent` carries `subagent_type`
  ([hooks: PreToolUse Agent](https://code.claude.com/docs/en/hooks#agent)), so a counting hook
  there is simpler. Prior art for a state-file loop bound: Anthropic's `ralph-wiggum` Stop hook
  keeps `iteration`/`max_iterations` in `.claude/ralph-loop.local.md`
  ([stop-hook.sh](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/hooks/stop-hook.sh)).
- **Subagent fields exist as described.**
  - `tools` (allowlist), `disallowedTools`, `skills` ("The full skill content is injected"),
    `hooks` (a `Stop` hook there becomes `SubagentStop`), `maxTurns`
    ([sub-agents: frontmatter reference](https://code.claude.com/docs/en/sub-agents#frontmatter-reference);
    [hooks in subagent frontmatter](https://code.claude.com/docs/en/sub-agents#hooks-in-subagent-frontmatter)).
  - Omitting `Agent` from `tools` keeps a reviewer from spawning helpers
    ([sub-agents: nested](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents)).
  - Skill `context: fork` with `agent:` exists ("If omitted, uses `general-purpose`")
    ([skills](https://code.claude.com/docs/en/skills#run-skills-in-a-subagent)).
- **Why a fresh reviewer.** "A fresh context improves code review since Claude won't be biased
  toward code it just wrote" (Writer/Reviewer pattern,
  [best practices](https://code.claude.com/docs/en/best-practices)). The same reasoning applies to
  a plan.

### State and resume (question 3)

- "Sessions are independent. Each new session starts with a fresh context window"
  ([how Claude Code works](https://code.claude.com/docs/en/how-claude-code-works#work-with-sessions)).
  Auto memory is off here (ADR 0014), so state must live in files or issues. The `.flow/` idea
  holds.
- `.flow/` is in `.gitignore`, so it exists only on the operator's machine. Treat it as a cursor.
  The durable record is the approved-plan comment on the source issue.
  - `to-tickets` fetches an issue's "full body and comments" when given its number, and "If the
    source was an existing issue, make each ticket its sub-issue" (local `to-tickets/SKILL.md`).
  - The issue-template hook checks only `gh issue create|edit` bodies, so comments pass
    (`.claude/hooks/issue-template.sh`).
- Within a day, `claude -n hl-engineer-<n>` followed by `claude --resume hl-engineer-<n>` reopens
  the same conversation ([CLI reference](https://code.claude.com/docs/en/cli-reference)). Invoked
  skill content stays in context across turns.
  - After compaction, only "the first 5,000 tokens" of each skill are re-attached, within a shared
    25,000-token budget
    ([skills: content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle)).
    Keep `SKILL.md` short and put the gate rules first.
  - Across days, `/hl-engineer resume <n>` re-invokes the skill, which also re-registers its hooks.
- A workflow run resumes only "within the same Claude Code session"
  ([workflows: resume](https://code.claude.com/docs/en/workflows#resume-after-a-pause)). That is
  one more reason not to hold a gated flow in a workflow.

### Scope and the issue format (question 4)

- **The backlog is GitHub Issues with four headings.** CLAUDE.md says "Backlog: GitHub Issues.
  Every issue has Goal, Done when, Out of scope, Depends on". `issue-template.sh` enforces the
  headings on `gh issue create` and on any `gh issue edit` that touches the body.
  `.github/ISSUE_TEMPLATE/task.md` holds the template.
- **The existing issues follow a hand-adapted form.** The map (#2) and its tickets (#3 to #6, #11)
  are wayfinder issues rewritten into the four headings, with "Part of #2" in the text. The GitHub
  API shows no native sub-issues on #2 and no dependencies on #6 (checked 2026-10-25).
- **`to-tickets` cannot publish here unchanged.** It does produce blocking-linked tickets: "Use
  the platform's native blocking relationship". But its issue template is Parent / What to build /
  Acceptance criteria / Blocked by, and it says to omit "Blocked by" when native edges exist. The
  hook would block those issues. The tracker doc is where the skill looks up how to publish:
  "The issue tracker ... should have been provided to you. If not, tell the user to run
  `/setup-matt-pocock-skills`". So the mapping goes there:
  - What to build → Goal
  - Acceptance criteria → Done when
  - an added Out of scope
  - Blocked by → Depends on, always present, alongside the native edges
- **No `ready-for-agent` label exists yet** (`gh label list`). `to-tickets` applies one by default.
- **Scope recommendation: end at tickets.** Stages 5 to 7 of harness.md go: build, the code-review
  loop, and triage. Triage also contradicts the suite's own guidance: "Tickets that `/to-tickets`
  produced are already agent-ready, so don't triage them" (local `ask-matt/SKILL.md`).

### Adopt-or-build placement (question 5)

- harness.md runs research before breakdown; the operator runs it after. Both are needed, as two
  different things:
  - **Fact research inside stages 1-2.** `grilling` already says "Finding facts is your job ...
    dispatch a sub-agent".
  - **Adopt-or-build after breakdown, per part.** Each verdict applies to one part. A "build" or
    "find another" verdict can reshape the parts, so stage 4 may send the flow back to stage 3.
- **How the checklist applies per part.** Use the harness.md checklist: maintained within the last
  year, permissive licence, passing security audits, more than one maintainer, multi-architecture
  images, pinned by digest. A part whose tool an ADR already decided cites the ADR and gets no
  verdict, the same way `longhorn-arm64.md` handled ADR 0006. "Passing security audits" needs a
  concrete test before it can be applied (open question).
- **When a workflow earns its place.** Fan-out research with cross-checking is a documented
  workflow use. Its trigger is a breakdown with more parts than the conductor can coordinate. Two
  caveats:
  - `disableBundledSkills: true` "removes bundled skills and workflows entirely"
    ([settings reference](https://code.claude.com/docs/en/settings-reference#disablebundledskills)).
    Here that removes `/workflow-authoring` and `/deep-research`.
  - Saved project workflows still run, and the conductor can start one through the `Workflow`
    tool by `name` with `args`
    ([Agent SDK reference: Workflow](https://code.claude.com/docs/en/agent-sdk/typescript#workflow)).

### What exists to adopt (question 6)

Each candidate below was checked against the checklist.

- **mattpocock/skills** (MIT, last commit 2026-10-19). No planning conductor upstream. The closest
  skills are:
  - `wayfinder`: plans decisions, not deliverables, and "hands off, it doesn't build".
  - `implement-spec`: a build-graph runner.
  - `chief-of-staff`: one long session coordinating subagents.
  - `ask-matt`: a router that "can only hint, never fire" hidden skills.
  - In progress, `loop-me` gives usable vocabulary: **checkpoint** ("a human-in-the-loop point"),
    **push right** ("defer the checkpoint as far as it will go"), and **brief** ("a tight,
    decision-ready summary ... never the raw output")
    ([loop-me](https://github.com/mattpocock/skills/blob/main/skills/in-progress/loop-me/SKILL.md)).
    Use these as leading words in `hl-engineer`.
- **anthropics/claude-code `feature-dev` plugin.** Seven phases, from Discovery to Summary, with
  in-conversation gates ("DO NOT START WITHOUT USER APPROVAL"), parallel `code-architect` agents
  with different focuses, and read-only agent tool lists
  ([feature-dev.md](https://github.com/anthropics/claude-code/blob/main/plugins/feature-dev/commands/feature-dev.md)).
  It fails the checklist: the last change under `plugins/feature-dev` is 2025-10-17, more than a
  year ago, and the repository licence is "© Anthropic PBC. All rights reserved". It is also
  code-centric, keeps nothing durable, and produces no issues. Borrow its stage 2 pattern; do not
  install it.

## Where harness.md holds and where it changes

Holds:

- the conductor is hidden and typed by the operator;
- it never calls a hidden skill;
- workflows take no mid-run input;
- state across sessions lives in files and issues;
- reviewers cannot edit;
- orchestration stays inside Claude Code;
- the checklist.

Changes:

1. **Stage 1 is not a typed gate.** The conductor calls `grilling` and `domain-modeling` itself.
   Only `to-tickets` (and `to-spec` or `wayfinder`, if an effort needs them) must be typed.
2. **"Writes ... with the `handoff` skill" cannot work.** `handoff` is hidden and saves to
   `$TMPDIR`, not `.flow/` (local `handoff/SKILL.md`). The conductor writes its own checkpoint
   briefs instead.
3. **The review loop reviews the plan, and a `PreToolUse` hook bounds it.** harness.md calls
   stages 5-6 "workflows the conductor launches" and also says a "Stop hook refuses to end the
   turn". Those are two different mechanisms. Neither is needed once the build is out of scope.
4. **Scope ends at tickets.** Build, review and triage move out; `implement` and `implement-spec`
   remain the next step, typed by the operator.
5. **Fix the tracker prerequisite** (`docs/agents/issue-tracker.md` with the four-heading mapping)
   before the first run.
6. **Rule 8 ("A stage refuses to start without its predecessor's handover") is prose.** By
   CLAUDE.md it should be a hook if it must always hold. An optional second skill hook would do
   it: deny `gh issue create` while an active run's state lacks `plan_approved`.

## Open questions for the operator

- **N for the review loop.** 3 is suggested. At the bound the conductor stops and asks.
- **Checkpoint durability.** Keep stages 1-4 local in `.flow/` and post only the approved plan to
  the issue (recommended)? Or post a public comment at every checkpoint?
- **Where research notes and ADRs land before any PR.** On a throwaway `research/<slug>` branch,
  the way wayfinder does it? Or with the first ticket's PR?
- **Native GitHub sub-issues and dependencies.** Adopt them now, or keep the text "Part of" and
  "Depends on" form the existing issues use?
- **The tracker doc.** Run `/setup-matt-pocock-skills`, which also adds an "## Agent skills" block
  to CLAUDE.md? Or write `docs/agents/issue-tracker.md` by hand and point to it from the existing
  "Backlog" line?
- **"Passing security audits".** It needs a concrete test (for example an OpenSSF Scorecard
  threshold or a CVE scan of the pinned digest) before stage 4 can apply it.
- **The scope narrowing.** Record it as a new ADR, or as a harness.md edit only? ADR 0014/0015
  already describe hl-engineer only as a gated conductor.

## Not verified

- Whether naming a hidden skill after plain text (for example "approved, /to-tickets 14") lets
  Claude run it. The docs describe the permission in general terms, and the table says "Not on its
  own".
- Whether skill frontmatter hooks survive `claude --resume` without re-invoking the skill. The docs
  say "the rest of the session" and do not cover resume. Re-invoking with `/hl-engineer resume`
  avoids the question.
- The `if: "Agent(<type>)"` hook filter. The sketch matches `Agent` and checks `subagent_type` in
  the script instead.
- The response shape a `PostToolUse` hook would get from `AskUserQuestion`. That shape would allow
  recording approvals deterministically.
- The options `agent()` accepts inside workflows (agent type, tools). The workflows page documents
  only `label` and `schema`. The full reference is in `/workflow-authoring`, which this repo
  disables.
- Whether `to-tickets` follows a tracker-doc instruction to keep "## Depends on" next to native
  edges. If it does not, the hook blocks the create and it retries.
- Native sub-issue and dependency calls with the App token. Not exercised.

## Sources

- Claude Code docs, fetched 2026-10-25:
  - [skills](https://code.claude.com/docs/en/skills)
  - [sub-agents](https://code.claude.com/docs/en/sub-agents)
  - [hooks](https://code.claude.com/docs/en/hooks)
  - [workflows](https://code.claude.com/docs/en/workflows)
  - [tools reference](https://code.claude.com/docs/en/tools-reference)
  - [goal](https://code.claude.com/docs/en/goal)
  - [how Claude Code works](https://code.claude.com/docs/en/how-claude-code-works)
  - [CLI reference](https://code.claude.com/docs/en/cli-reference)
  - [settings reference](https://code.claude.com/docs/en/settings-reference)
  - [permission modes](https://code.claude.com/docs/en/permission-modes)
  - [best practices](https://code.claude.com/docs/en/best-practices)
  - [Agent SDK TypeScript reference](https://code.claude.com/docs/en/agent-sdk/typescript)
- Upstream repositories:
  - [mattpocock/skills](https://github.com/mattpocock/skills) (tree listing and `loop-me`)
  - [anthropics/claude-code plugins](https://github.com/anthropics/claude-code/tree/main/plugins)
    (`feature-dev`, `ralph-wiggum`); licence and commit dates through the GitHub API
- Local:
  - `.claude/skills/{grill-with-docs,grilling,wayfinder,to-spec,to-tickets,implement,implement-spec,research,handoff,triage,ask-matt,setup-matt-pocock-skills,writing-for-agents}`
  - `.claude/settings.json`, `.claude/hooks/issue-template.sh`, `.gitignore`
  - issues #2, #6 and #11, and labels, through `gh`
