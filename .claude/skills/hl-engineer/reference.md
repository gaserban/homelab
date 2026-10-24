# hl-engineer reference

## Brief

One file per stage, `.flow/<n>/NN-<stage>.md`. A brief is decision-ready: pointers, not copies,
and nothing secret (the plan comment quotes from it, and the repo is public).

```markdown
# <NN> <Stage> for #<n>: <issue title>

## Decided
- <decision> (<why, or the ADR / research note it rests on>)

## Artifacts
- <path or issue link>: <what it holds>

## Open
- <question> (<who answers it, and by which stage>)

## Review log (stage 2 only)
- Round <r>, <lens>: <finding> → fixed: <how> | rebutted: <why>
```

## Plan comment

Posted once, at stage 5, on the source issue. `to-tickets` turns it into tickets, so each part
reads as a ticket's raw material.

```markdown
## hl-engineer: approved plan

**Recommendation:** <one paragraph>
**Rests on:** ADR <nnnn>, <research note>, ...

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
