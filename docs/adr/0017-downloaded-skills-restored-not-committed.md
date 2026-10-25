# 0017 Downloaded skills are restored per checkout, not committed

Date: 2026-10-25

## Context

ADR 0014 made skills-lock.json the list of downloaded skills; their folders were committed under
`.claude/skills/`. Checked on 2026-10-25 against the upstream repositories, the Claude Code docs and
the `skills` CLI source (vercel-labs/skills at `a80e4c9`):

- The repo is public, so the 30 committed skills (147 files) are copies it redistributes. MIT
  (mattpocock/skills, vercel-labs/skills) and Apache-2.0 (fluxcd/agent-skills, anthropics/skills,
  antonbabenko/terraform-skill) require the licence and copyright notices in copies; only
  skill-creator carried one. The three plugin-dev guides come from anthropics/claude-code, whose
  licence is "© Anthropic PBC. All rights reserved" and grants no redistribution.
- `npx skills experimental_install` restores skills-lock.json, but only into `.agents/skills/`,
  which Claude Code does not read, from the default branch, without checking `computedHash`. It is
  experimental.
- Plugins declared in `.claude/settings.json` (`enabledPlugins`) are not downloaded for
  collaborators; each one still runs `claude plugin install`. Plugin skills are renamed
  `plugin:skill` and "are not affected by `skillOverrides`", so the ADR 0016 overrides would stop
  working. Bundles install whole: every mattpocock skill, all of plugin-dev's agents and commands.
  `find-skills` and `terraform-skill` are in no marketplace.
- A `package.json` `skills` field with `skills experimental_sync` is experimental too, adds Node to
  the repo, and runs only when someone runs `npm install`.
- `computedHash` comes in two schemes, both ordering files like JavaScript `localeCompare`: the
  CLI's folder hash (relative path, then contents, per file) for git-clone installs, and the
  skills.sh snapshot hash (path, NUL, contents, NUL) for downloads through skills.sh. 26 of the 30
  lock values matched neither scheme for any upstream version, although all 30 folders equalled
  upstream; they were refreshed to the snapshot hash skills.sh serves, which is what the CLI writes
  on a new install.

## Decision

- Downloaded skill folders are gitignored (`.claude/skills/*` except `hl-*`). skills-lock.json
  stays the list and is the only committed record of them.
- A SessionStart hook, `.claude/hooks/skills-restore.sh`, restores each missing or changed folder
  from its author's GitHub repository (a sparse clone at the entry's `ref`, else the default
  branch) and keeps it only if its hash equals `computedHash` under either scheme. On a mismatch it
  keeps the local copy, or installs nothing, and tells the operator. A stamp holding the lock's
  hash skips all work until the lock changes or a folder goes missing.
- Taking an upstream change stays deliberate: review it, reinstall with `npx skills add`, commit the
  new skills-lock.json. Adding and removing skills stays with the skills CLI.
- Not plugins, `package.json` or `experimental_install`, for the reasons above.

## Consequences

- A PR that updates a downloaded skill shows only a new hash, not the changed text. The upstream
  diff is reviewed before the reinstall.
- The first session in a fresh clone needs github.com: about 10 seconds for the six sources.
  Later sessions cost a stamp check.
- When upstream moves past the lock, a fresh clone lacks that skill until the operator reinstalls
  it; the hook names it at every session start until then.
- Removing a skill from the lock does not delete its folder in other checkouts; `npx skills remove`
  there does.
- Commits from here on carry no third-party skill text, so no notices file is needed. Earlier
  commits still hold the copies; removing them is a separate history rewrite that only the operator
  can run.
