# hl-engineer run record

One row per gate of a real run, appended by the conductor after the operator answers (the format
is in `.claude/skills/hl-engineer/reference.md`, "Run record"). Minutes count from the state file's
`started`; findings are per review round; friction is the operator's words when they chose Revise
or Stop. `/retro` reads this file every third run, and the eval set in
`.claude/skills/hl-engineer/evals/evals.json` is the checklist it grades the rows against. A row
that flatters the skill hides the next fix.

## Real runs

| Date | Issue | Stage | Answer | Rounds F/S/N | Findings | Plan words | Amendments | Minutes | Friction |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Rehearsals (skill-creator eval harness, 2026-10-25)

Unattended runs on fixtures, gates closed without an answer and counted as Stop, the review-bound
hook not registered, Opus as the conductor. Kept apart from real runs because no operator answered.

| Date | Issue | Stage | Answer | Rounds F/S/N | Findings | Plan words | Amendments | Minutes | Friction |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-25 | #6 | plan (iteration 1) | stop at bound | 2/3/3 | 35/29/19 | 8464 | - | 67 | plan doubled across the loop; revision 4 unreviewed; no stopped line |
| 2026-10-25 | #6 | plan (iteration 2) | stop at bound | 3/3/3 | 33/24/18 | 2862 | - | 64 | log compressed to fit the line cap; reviewers did not load the new agent text |
| 2026-10-25 | #6 | adopt-or-build (iteration 1) | stop at gate | 2/1/2 | - | - | 11, unreviewed | 31 | checkpoint comment said 9 of 11 amendments |
| 2026-10-25 | #6 | adopt-or-build (iteration 2) | stop at gate | 2/2/2 | 3 major, 5 minor (Saboteur on amendments) | - | 10 | 37 | Mealie fails the licence line; amendment labels written before the review |
| 2026-10-25 | #2 | close-out (iteration 1) | stop at gate | 1/1/1 | - | - | - | 5 | no sub-issues to check; progress line had no wording for a stop |
