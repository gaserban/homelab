# Diverging from downloaded skills: skillOverrides and the divergence ladder

Checked 2026-10-25 against the official Claude Code docs (code.claude.com/docs, fetched the same
day), the `skills` CLI source (vercel-labs/skills at
[`a80e4c9`](https://github.com/vercel-labs/skills/tree/a80e4c9d12d607631249d4d7d059f835d4b2f13a),
2026-10-19), and mattpocock/skills at
[`5beb35b`](https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2)
(2026-10-19). The local copies of `setup-matt-pocock-skills`, `to-tickets`, `to-spec`,
`wayfinder`, `handoff`, `implement` and `triage` are byte-identical to that upstream commit
(`diff -rq`), so nothing has been edited so far. Frames: CLAUDE.md, ADRs
[0014](../adr/0014-agent-harness.md) and [0015](../adr/0015-skill-visibility-and-routing.md),
[harness.md](../agents/harness.md), and the prior note [hl-engineer-flow.md](hl-engineer-flow.md).

Question, from the operator: "Seeing as those skills are not compatible with our philosophy, is it
accepted to enable skillOverrides for small tweaks? What is the suggested approach for
divergences"

## Short answer

- **`skillOverrides` cannot make tweaks.** It sets one of four visibility states per skill
  (`on`, `name-only`, `user-invocable-only`, `off`) and nothing else. It cannot change a skill's
  text or template, and it does not apply to plugin skills.
- **It cannot un-hide an author-hidden skill.** The docs frame it as a way to "Hide or collapse a
  skill", and a skill absent from the map "is treated as `"on"`". A skill absent from the map that
  has `disable-model-invocation: true` stays hidden, so `"on"` does not override the frontmatter.
  This is inferred from those two statements; no page states the precedence outright, and it was
  not tested (settings are read-only here). So `setup-matt-pocock-skills` stays operator-typed.
- **Using it to restrict is already accepted** (ADR 0014: "overlapping downloaded skills are
  demoted with skillOverrides"). Each new entry must follow the ADR 0015 visibility rule.
- **The author's customization surface is the repo, not the skill.** The `docs/agents/*.md` files
  "are the only thing that varies between repos"; preferences "belong in your `CLAUDE.md` as plain
  instructions"; anything else goes "in a fork (skills.sh gives you an editable copy)".
- **Approach: climb a divergence ladder.** Configure first (docs/agents, CLAUDE.md), then enforce
  (hooks), then restrict (skillOverrides), then route around it (own `hl-` step, accept the gate,
  or drop the skill), and fork as an `hl-` copy only as a last step, under a new ADR.
- **None of the four current divergences needs a fork.** Two are config plus the existing hook,
  one is "don't use handoff in the flow", and one is a gate the repo's own rule would keep even on
  a fork.
- **Record the ladder in a new ADR 0016.** It changes how two lines of ADR 0015 read (see the ADR
  section below).

## The divergence ladder

Start at rung 1. Move up only when the rung below has been tried and has failed (a dry run, or a
hook block that repeats), and write down which failure moved it up.

| Rung | Mechanism | Use when | Cost |
| --- | --- | --- | --- |
| 1 Configure | `docs/agents/*.md` (issue-tracker, triage-labels, domain), CLAUDE.md lines | The skill already reads a repo doc for this concern (tracker, labels, formats, preferences) | None: the downloaded skill stays unedited and updates freely |
| 2 Enforce | A hook that blocks and explains (`PreToolUse`), or one that adds context when a skill is typed (`UserPromptExpansion` with `additionalContext`) | A rule must hold every time (CLAUDE.md), or rung 1 is ignored on a dry run | One script; deterministic. Hooks check or inform. They do not silently rewrite a skill's output |
| 3 Restrict | `skillOverrides`: `name-only`, `user-invocable-only`, `off` | The skill's visibility is wrong for this repo by the ADR 0015 rule (it acts on the world, overlaps, or routes to absent skills) | One settings line. It can only restrict |
| 4 Route around | (a) our own `hl-` skill does the step, composing only model-visible skills; (b) accept the hidden skill as an operator gate; (c) drop the skill from the flow, or uninstall it | The divergence is in what the skill does, not how it is configured | (a) we own that step's text; (b) one typed command per gate; (c) none |
| 5 Fork | Vendor `hl-<name>` as a copy; keep the original installed but `off` as the tracked baseline; record the upstream commit and `computedHash` in the copy's `metadata` | Rungs 1-4 fail and the skill's content is still worth keeping | Manual re-sync on every upstream change. Needs a new ADR (ADR 0015: "it is a new decision with a maintenance cost") |
| Side track | Upstream issue or PR | An observed failure that is not specific to this repo | Upstream rejects config options and per-workflow tweaks (SCOPE.md), so expect it only for real bugs |

Two limits apply at every rung:

- **A wrapper cannot call a hidden skill.** "If Claude tries anyway, Claude Code blocks the call and
  instructs it not to reproduce the deploy steps another way"
  ([skills: control who invokes](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill)).
  The suite has the same invariant: "A user-invoked skill may invoke model-invoked skills, but it
  can never reach another user-invoked skill"
  ([invocation.md](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/.agents/invocation.md)).
- **A fork does not remove a gate on its own.** ADR 0015 hides any skill that "acts on the world
  (issues, branches, PRs, installs)". An `hl-to-tickets` fork still creates issues, so it is still
  hidden and still typed. Forking changes content, not who may run it.

### Applied to the known divergences

| Divergence | Rung | What to do | Why not a higher rung |
| --- | --- | --- | --- |
| `setup-matt-pocock-skills` is author-hidden, so Claude and `hl-engineer` cannot run it | 4b: accept the gate, once per repo | The operator types `/setup-matt-pocock-skills` once. It is interactive by design ("Explore, present what you found, confirm with the user, then write") and it creates labels, so it acts on the world. `hl-engineer` intake checks that `docs/agents/issue-tracker.md` exists and names the command if not. Alternative: the operator asks Claude to write `docs/agents/*.md` by hand from the seed templates, which the skill itself allows ("they can edit `docs/agents/*.md` directly later") | `skillOverrides` cannot un-hide it. A fork to save one command, once, fails the maintenance test. Upstream marks it hidden "on purpose" |
| `to-tickets`, `to-spec`, `wayfinder` templates lack Goal / Done when / Out of scope / Depends on | 1 + 2 | Rung 1: a "Body format" section in `docs/agents/issue-tracker.md` that maps each template to the four headings (CLAUDE.md already states the rule). Rung 2: `issue-template.sh` already blocks a body that lacks them. If a dry run shows the inline template still wins, add a `UserPromptExpansion` hook matching `to-tickets\|to-spec\|wayfinder` that adds the mapping as `additionalContext` | The skills read the tracker doc for how to publish, and the hook guarantees the outcome. Fork only if the hook keeps blocking after both |
| `handoff` is hidden and writes to `$TMPDIR`, not `.flow/` | 4a + 4c | `hl-engineer` writes its own checkpoint briefs to `.flow/<run>/`. `handoff` drops out of the flow and stays an operator tool for its documented purpose (work that has to "travel"). Update the harness.md line that names it | Its location is in the skill body, and no doc reads it. Its purpose (portability) differs from a state cursor |
| Hidden suite skills (`wayfinder`, `to-spec`, `to-tickets`, `implement`) force human gates in a conductor | 4b: accept the gate (ADR 0015) | The conductor writes the handover and names the command; the operator's typed `/to-tickets <n>` is the gate. `grill-with-docs` needs no gate: the conductor calls `grilling` and `domain-modeling` directly | They act on the world, so by ADR 0015 even a fork stays hidden. Removing the gate would need the conductor to publish issues itself (4a), which is a new ADR |

Two template details for the rung-1 mapping:

- `to-spec` writes `## Out of Scope` (capital S). `issue-template.sh` uses `grep -qF "## Out of
  scope"`, which is case-sensitive, so that spec body is blocked as written.
- `to-tickets` says to omit "Blocked by" "when blockers were set as native edges". The hook still
  requires `## Depends on`, so the mapping must say: always write `## Depends on`, in addition to
  the native edges.

## Findings

### What `skillOverrides` supports (question 1)

- **Four values, visibility only.** "Each key is a skill name and each value is one of four
  states": `"on"` (listed to Claude with name and description, in `/` menu), `"name-only"` (name
  only, in menu), `"user-invocable-only"` (hidden from Claude, in menu), `"off"` (hidden from both)
  ([skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings)).
  The settings reference describes it as "Hide or collapse a skill without editing its
  `SKILL.md`", scope "Any file", default "unset, so every skill is `"on"`"
  ([settings reference: skillOverrides](https://code.claude.com/docs/en/settings-reference#skilloverrides)).
- **`off` also blocks typed invocation.** "Invoking a hidden skill by its full name returns the
  `skillOverrides` error instead of running it" (skills page, same section).
- **Not for plugin skills.** "Plugin skills are not affected by `skillOverrides`. Manage those
  through `/plugin` instead" (skills page). Relevant because upstream's recommended Claude Code
  install is a plugin (`claude plugin install mattpocock-skills@claude-plugins-official`,
  [README](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/README.md)).
  This repo uses the skills.sh copy, so overrides do apply here.
- **No promotion over frontmatter.** No page says a settings value overrides
  `disable-model-invocation: true`. What the pages do say:
  - "A skill that is absent from `skillOverrides` is treated as `"on"`" (skills page).
  - The default for an author-hidden skill is "Claude can invoke: Not on its own" (invocation
    table, [control who invokes](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill)).
  - "By default, Claude can invoke any skill that doesn't have `disable-model-invocation: true` set"
    ([restrict Claude's skill access](https://code.claude.com/docs/en/skills#restrict-claudes-skill-access)).
  - For aliases: "You can only restrict a skill further through an alias, never make it more
    visible" (skills page).

  So `"on"` equals the default, which for an author-hidden skill is hidden. Inference, not tested.
- **Permission rules do not promote either.** `Skill(name)` allow and deny rules control approval
  ("Allow or deny specific skills using permission rules", restrict section). Nothing says an
  allow rule lifts `disable-model-invocation`. Not tested.
- **Other documented mechanisms, and why they don't help here:**
  - *Shadowing by name.* "Enterprise over personal, and personal over project"
    ([resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)).
    A `~/.claude/skills/to-tickets` would shadow the project copy, but only on one machine and
    outside git. That breaks ADR 0014 ("Knowledge lives in git"). Rejected.
  - *Hooks on typed skills.* `UserPromptExpansion` "fires on that direct path" (typing
    `/skillname`), "matches on `command_name`", and can "inject context for a particular skill ...
    a hook matching a review skill can append the team's review checklist as `additionalContext`"
    ([hooks: UserPromptExpansion](https://code.claude.com/docs/en/hooks#userpromptexpansion)). A
    `PreToolUse` hook on `Skill` "fires only when Claude calls the tool" (same section). This is
    the rung-2 way to steer a typed hidden skill without editing it.
  - *Rewriting tool input.* `PreToolUse` `updatedInput` "Modifies the tool's input parameters
    before execution" ([hooks: PreToolUse decision control](https://code.claude.com/docs/en/hooks#pretooluse-decision-control)).
    Rewriting issue bodies this way is possible but invisible to the model and fragile. Not
    recommended: block with a reason instead, as `issue-template.sh` does.
  - *Frontmatter `hooks`, `context: fork`, `metadata`.* These exist only in a skill's own
    frontmatter ([frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference)),
    so they are available to `hl-` skills only. `metadata` is a "Free-form YAML map for your own
    key-value data ... Claude Code doesn't act on its contents". That is where a fork can record
    its upstream baseline.

### What the installer does to a modified skill (question 2)

- **Update compares upstream against the lock, never against disk.** `update` hashes each skill in
  a fresh clone and skips it when `latestHash === skill.entry.computedHash`
  ([update.ts L904-L940](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/update.ts#L904-L940)).
  It never hashes the installed folder, so local edits raise no warning. The lock's hash is
  "computed from all files in the skill folder", at install time
  ([local-lock.ts L36-L41](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/local-lock.ts#L36-L41)).
- **When upstream changed, local edits are deleted.** The update re-runs `add <source> --skill
  <name> -y` (same file), and the installer calls `cleanAndCreateDirectory`, which does
  `rm(path, { recursive: true, force: true })` before copying
  ([installer.ts L198-L205](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/installer.ts#L198-L205)).
  When upstream has not changed, the edits survive silently. Either way only `git diff` would show
  them. This is the mechanical reason behind "never edited".
- **No fork or patch mechanism is documented.** I searched the README and `docs/*.md` for fork,
  patch and customize and found none. The supported route is a different source: "GitHub shorthand
  (owner/repo)", "Any git URL", "Local path"
  ([commands.md: source formats](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/docs/commands.md)).
  A fork published to its own repository installs and updates like any other source.

### What the author intends as the customization surface (question 3)

- **Config docs, not skill edits.** "Those files are the only thing that varies between repos. The
  skills themselves are identical everywhere. They read `docs/agents/issue-tracker.md` at run time
  and do what it says ... why you never edit a skill file to point it at another tracker"
  ([docs: setup-matt-pocock-skills](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/docs/engineering/setup-matt-pocock-skills.md)).
- **Preferences go in CLAUDE.md.** "[S]kills stay opinionated and take no per-user config.
  Preferences belong in your `CLAUDE.md` as plain instructions, which every skill already reads"
  (same page). Those three config files are the whole surface: "It configures three things:
  tracker, labels, doc layout."
- **Forks are the stated escape hatch.** Upstream rejects "a config option, a harness-specific
  branch, or a tweak to suit one person's workflow. Those belong in your own `CLAUDE.md` /
  `AGENTS.md`, or in a fork (skills.sh gives you an editable copy)"
  ([SCOPE.md](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/SCOPE.md)).
  The README says "Hack around with them. Make them your own", and that skills.sh "copies editable
  files into your project, and you update them by hand". The author tolerates edits; this repo
  forbids them for update safety (above).
- **The setup skill is hidden on purpose.** "Its metadata marks it non-invokable on purpose, so no
  other skill can fire it for you" (setup docs page). Upstream also declined a separate verify mode:
  "run `/setup-matt-pocock-skills` and tell it to verify your current setup"
  ([setup-skill-verify-mode.md](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/.out-of-scope/setup-skill-verify-mode.md)).
  An upstream PR to make it model-invocable would contradict
  [invocation.md](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/.agents/invocation.md).
- **Which skills read which doc.** `to-tickets`, `to-spec` and `triage` say "The issue tracker and
  triage label vocabulary should have been provided to you. If not, tell the user to run
  `/setup-matt-pocock-skills`". `wayfinder` reads the tracker doc's "Wayfinding operations" section
  (local SKILL.md files). The seed GitHub tracker doc has a "When a skill says 'publish to the
  issue tracker'" section, which is the natural place for the four-heading mapping. But each skill
  also carries an inline `<issue-template>`, and no upstream text says the tracker doc overrides
  it. Hence the dry run and the rung-2 backstop.

## Does this need an ADR? (question 5)

Yes, a new ADR 0016, "Diverging from downloaded skills". ADRs are "never edited in place"
([ADR index](../adr/README.md)), and the ladder changes how two lines of ADR 0015 read:

- **Supersede** ADR 0015's "`skillOverrides` demotes only `prototype` ... and `find-skills` ...;
  `ask-matt` is off". The list is already stale: settings also set `plugin-authoring` to `off`
  (commit 83af61f). Replace the list with the rule (rung 3: restrict only, by the visibility rule)
  and let settings hold the list.
- **Supersede** ADR 0015's consequence "Downloaded skills are not forked to make them callable. If
  that ever becomes necessary, it is a new decision". Replace it with rung 5: forks are allowed
  as `hl-` copies, for content only. A fork follows the same visibility rule, the original stays
  installed and `off` as the baseline, and a re-sync runs on every `npx skills check` hit.
- ADR 0014's "never edited" and "our own carry the hl- prefix" stand. The ladder refines them.

The CLAUDE.md line "wrap them in an `hl-` skill instead" could then point to the ADR. harness.md
composition rule 6 gains a pointer to the ladder.

## Open questions for the operator

- **The setup skill.** Type `/setup-matt-pocock-skills` once (it also adds an `## Agent skills`
  block to CLAUDE.md and runs `gh label create`), or have Claude write `docs/agents/*.md` by hand
  on your instruction and keep CLAUDE.md untouched?
- **Wayfinder tickets.** A decision ticket's body is `## Question` only. Map it into the four
  headings, as issues #2 to #6 were by hand, or exempt `wayfinder:*`-labelled issues in the hook?
  CLAUDE.md currently says "Every issue".
- **Fork re-sync cadence**, if rung 5 is ever used: on every `npx skills check`, or only when a
  forked skill misbehaves?
- **Hook strictness.** Make the heading check case-insensitive (it would admit `to-spec`'s `## Out
  of Scope`), or keep exact casing and map it in the tracker doc?

## Not verified

- That `skillOverrides: "on"` cannot un-hide an author-hidden skill. This is inferred from the
  docs, not tested: settings are not writable in this session.
- That a `Skill(name)` allow rule does not lift `disable-model-invocation`. No doc says either way.
- That `to-tickets`, `to-spec` and `wayfinder` follow a tracker-doc body format over their inline
  templates. This needs a dry run against a scratch issue.
- That a `UserPromptExpansion` hook's `additionalContext` changes which template the skill uses.
  It is documented to add context, not to win over the skill body.
- That Claude writing `docs/agents/*.md` by hand is not treated as "reproducing" the hidden setup
  skill. The block message is documented only for an attempted invocation.
- The local `computedHash` values were not recomputed: no node or python in the sandbox. The
  byte-identical upstream diff stands in for that check.

## Sources

- Claude Code docs, fetched 2026-10-25:
  - [skills](https://code.claude.com/docs/en/skills): override skill visibility from settings,
    control who invokes a skill, restrict Claude's skill access, resolve skills that share a name,
    frontmatter reference, remove a skill
  - [settings reference: skillOverrides](https://code.claude.com/docs/en/settings-reference#skilloverrides)
  - [hooks](https://code.claude.com/docs/en/hooks): UserPromptExpansion, PreToolUse decision control
  - [permissions](https://code.claude.com/docs/en/permissions)
- vercel-labs/skills at `a80e4c9`: `src/update.ts`, `src/installer.ts`, `src/local-lock.ts`,
  `README.md`, `docs/commands.md`
- mattpocock/skills at `5beb35b`: `README.md`, `SCOPE.md`, `CLAUDE.md`, `.agents/invocation.md`,
  `.out-of-scope/setup-skill-verify-mode.md`, `.out-of-scope/harness-name-collisions.md`,
  `docs/engineering/setup-matt-pocock-skills.md`, `docs/engineering/to-tickets.md`,
  `docs/productivity/handoff.md`
- Local: `CLAUDE.md`, `skills-lock.json`, `.claude/settings.json`, `.claude/hooks/issue-template.sh`,
  `.github/ISSUE_TEMPLATE/task.md`, `.claude/skills/{setup-matt-pocock-skills,to-tickets,to-spec,wayfinder,handoff,implement,triage,grill-with-docs}`,
  ADRs 0014 and 0015, `docs/agents/harness.md`, git history of `.claude/skills`
