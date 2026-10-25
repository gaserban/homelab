# hl-engineer reference

## Brief

One file per stage, `.flow/<n>/NN-<stage>.md`. A brief is decision-ready: pointers, not copies,
and nothing secret (the plan comment quotes from it, and the repo is public). The plan brief stays
under 3,000 words and the others under 2,000; past that, the brief is copying what it should cite.

```markdown
# <NN> <Stage> for #<n>: <issue title>

## Decided
- <decision> (<why, or the ADR / research note it rests on>)

## Artifacts
- <path or issue link>: <what it holds>

## Open
- <question> (<who answers it, and by which stage>)

## Plan amendments (stage 4 only)
- <what the plan said> → <what the breakdown found> (<source>; reviewed: Saboteur round <r> | not reviewed, why)
```

## Prior-art brief

`01-prior-art.md`, written at the stage 1 checkpoint. One block per question; the plan cites the
block or says why it deviates.

```markdown
## <question a practitioner would have answered>
- Established solution: <what is commonly run or done, in one or two sentences>
- Source: <docs/research/<topic>.md | ADR <nnnn> | <upstream URL>, dated>
- For this issue: <what it settles, or what it rules out>
- Agent: <haiku lookup | sonnet research>
```

## Review log

`03-review.md`, one file for the whole loop, so the plan brief stays short and the history stays
whole. Every finding from every round has a line, including the ones that were cut from scope.

```markdown
# Review log for #<n>

## Round <r>
Brief as reviewed: <words> words, <bytes> bytes.
- <lens> <k> [blocker|major|minor]: <finding> → fixed: <what replaced what> | rebutted: <why> | cut: <moved where>
```

## Plan comment

Posted once, at stage 6, on the source issue. `to-tickets` turns it into tickets, so each part
reads as a ticket's raw material: behavioural rather than procedural, durable (no file paths or
line numbers that go stale), with acceptance criteria and a scope boundary, as the downloaded
`triage` skill's `AGENT-BRIEF.md` describes an agent-ready brief.

```markdown
## hl-engineer: approved plan

**Recommendation:** <one paragraph>
**Rests on:** ADR <nnnn>, <research note>, <prior-art block>, ...

### Parts
| # | Part | Delivers | Depends on | Tool |
| --- | --- | --- | --- | --- |
| 1 | <name> | <observable result on dev> | nothing | <tool, ADR or verdict link> |

### Done when, per part
Each check is runnable: `command → expected signal (static | dev | operator)`. `to-tickets` copies
them into each ticket's `## Done when`, and `tdd` tests at them.

1. `<command>` → `<expected signal>` (static)
2. `<command>` → `<expected signal>` (dev)

### Out of scope
- <what no ticket may do>
```

## Adopt-or-build checklist

Score each candidate on every line, with the source that shows it. A candidate that fails any line
gets "build" or "find another".

| Criterion | Pass when |
| --- | --- |
| Maintained | a release or commit within the last 12 months |
| Licence | permissive (Apache-2.0, MIT, BSD, MPL-2.0) |
| Security | no open critical advisory; cite the audit or the OpenSSF Scorecard if one exists, otherwise mark it unverified |
| Maintainers | more than one active maintainer |
| Images | multi-architecture: amd64 and arm64 |
| Pinning | images and charts can be pinned by digest or exact version |

A part whose tool an ADR already fixes cites the ADR in place of a verdict.

## Run record

`docs/agents/hl-engineer-runs.md`, tracked in git, one row per gate, appended after the operator
answers. Minutes count from the state file's `started`. Findings are per round, as `r1/r2/r3`.
Friction is the operator's words when they chose Revise or Stop, or `-`.

```markdown
| Date | Issue | Stage | Answer | Rounds F/S/N | Findings | Plan words | Amendments | Minutes | Friction |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-25 | #6 | plan | approve at bound | 3/3/3 | 33/24/18 | 2,900 | - | 64 | reviewers repeat themselves after round 2 |
```
