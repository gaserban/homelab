# 0001 The repo is public because the branch ruleset needs it

Date: 2026-10-24

## Context

GitHub offers branch rulesets (require a pull request, require approval, block force pushes and
deletion, restrict updates) on private repositories only under paid plans. On the Free plan they
are available on public repositories. An earlier decision kept the previous homelab repository
private.

## Decision

`gaserban/homelab` is public. The reason is the ruleset, not publication for its own sake. Secret
scanning push protection is on, and it is the real control against leaked secrets; the line in
CLAUDE.md is a reminder.

## Consequences

- Nothing that must stay private may be committed, including hostnames that reveal the internal
  network layout beyond what the tunnel already exposes.
- If rulesets become affordable on a private repository, revisit.
