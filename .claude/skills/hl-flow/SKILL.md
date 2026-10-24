---
name: hl-flow
description: Single entry point for research, planning, breakdown and documenting. Calls exactly one skill per stage.
disable-model-invocation: true
argument-hint: "<research|plan|breakdown|document> <what>"
---

You are the router. Read `$ARGUMENTS`, pick the stage, and call the Skill tool with exactly one
skill from the table. Do not combine skills, do not use plan mode, deep research, or any other
skill for these stages. If the stage is unclear, ask one question and stop.

| Stage word | Call this skill | When |
| --- | --- | --- |
| research | `research` | facts, docs, candidate tools; the result is a findings file under `docs/research/` with sources and an adopt-or-build verdict |
| plan | `wayfinder` | work too big for one session; produces a map issue and decision tickets |
| plan | `grill-with-docs` | one decision or design to settle now; produces ADRs and glossary entries |
| breakdown | `to-spec`, then `to-tickets` | a settled plan into a spec issue and tickets with blocking edges, in the four-part template |
| document | `grill-with-docs` | a decision that needs an ADR; `domain-modeling` is reached through it, never called directly |

For `plan`, choose `wayfinder` when the request names more than one decision or an outcome that
needs several sessions; otherwise `grill-with-docs`. Say which you chose in one line before
calling it.

Before calling the skill, read `docs/adr/README.md` so the stage respects decisions already made.
