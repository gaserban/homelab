# 0013 GitHub access through an App; the merge is the operator's alone

Date: 2026-10-24

## Context

Claude works through a GitHub App installed on this repository only (Contents, Pull requests and
Issues read and write; Metadata read). Clusters read the repository with a separate read-only key.
Once a PR is approved, any writer may merge, so Claude, holding the App key, could merge right
after approval. A CLAUDE.md line is a request; GitHub's ruleset and a hook are enforcement.

## Decision

- The main ruleset: require a pull request with one approval, dismiss approvals on new commits,
  block force pushes and deletion, and Restrict updates with the repository admin as the only
  bypass actor, for pull requests only. Effect: nobody pushes to main directly, only the operator
  merges, and the App can still push branches and open PRs.
- A PreToolUse hook (`.claude/hooks/git-guard.sh`) blocks merge commands, pushes to main, force
  pushes and destructive local git, so Claude does not waste turns on refusals and local history is
  protected.
- Verification includes: the operator approves, the App attempts a merge, GitHub refuses.

## Consequences

- The App key still grants branch pushes and PR creation, which is its intended scope. Rotate on
  suspicion.
- The hook guards Claude Code's own tool calls only; the ruleset covers every other path.

## Bootstrap exception (2026-10-24)

The bootstrap pull request (#1) and the first issues (#2 to #6) were created from the operator's
Windows machine under the operator's own GitHub account, because the App credential exists only in
the WSL setup that the pull request itself introduces. This is a one-time exception: from the first
WSL session on, Claude acts as the App, and the operator's account is used only to approve and
merge. The App key is not installed on the Windows machine.
