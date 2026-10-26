# homelab

A single-operator homelab built through GitOps, with Claude Code as the main builder.

## Language

**Gate**:
A stop in a flow where the operator approves, revises or stops before the flow moves on.
_Avoid_: checkpoint (a stop that records without asking), check

**Check**:
An automated pass-or-fail verdict on a change, run at commit time, in Bazel or in CI; a required check is one the branch ruleset makes a merge wait for.
_Avoid_: gate, guard (reserved for the merge guard hook)
