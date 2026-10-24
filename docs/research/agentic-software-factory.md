# Agentic software factory: what the term means, and where hl-engineer fits

Checked 2026-10-25 against the first-party sources below (Dan Shapiro's blog, StrongDM's
factory.strongdm.ai and the `strongdm/attractor` repository, Simon Willison's weblog, Anthropic's
engineering posts, code.claude.com/docs, fluxcd.io, and the `fluxcd/agent-skills` repository through
the GitHub API), and against this repo: [ADR 0013](../adr/0013-github-access-and-merge-guard.md),
[0014](../adr/0014-agent-harness.md), [0015](../adr/0015-skill-visibility-and-routing.md),
[0016](../adr/0016-engineer-flow-and-skill-divergence.md), [harness.md](../agents/harness.md),
`.claude/skills/hl-engineer/`, `.claude/agents/hl-plan-reviewer.md`,
`.claude/hooks/flow-review-bound.sh`, and the prior notes [hl-engineer-flow.md](hl-engineer-flow.md)
and [skill-divergence.md](skill-divergence.md).

Quotes from web pages came through a fetch tool that extracts text. The code.claude.com and GitHub
quotes are from raw page text; the others are as extracted and were not checked against a second copy.

Question, from the operator: "Double check our engineering skill. I found out the term for what I want
to build: an agentic software factory."

## Short answer

- **The term has no stable definition.** "Software factory" goes back to the 1960s and was reused by
  Microsoft (2004) and the US DoD's DevSecOps pipelines. The agentic sense dates from January and
  February 2026. Dan Shapiro's "five levels" puts the "dark software factory" at the top, and
  StrongDM's AI team published the only working definition. Simon Willison made both widely known.
  "Agentic software factory" as a phrase appears only in vendor marketing, and vendors use it to mean
  different things.
- **The working definition:** "non-interactive development where specs + scenarios drive agents that
  write code, run harnesses, and converge without human review" (StrongDM). The loop is "Seed →
  Validation harness → Feedback loop. Tokens are the fuel." The other sources describe the same
  thing: verification is the bottleneck, and intent-shaping work is kept apart from fully specified
  work.
- **`hl-engineer` is the right first stage.** StrongDM's "Shift Work" technique splits work into an
  interactive part ("generate, clarify, generate, approve, correct") and a non-interactive part
  ("Tasks that are already fully specified"). `hl-engineer` is the interactive part. `/implement-spec`
  is the non-interactive part, and the ticket graph is the handover between them.
- **This repo is a "lit" factory at Shapiro's Level 4, and it should stay one.** Level 5 ("Code must
  not be reviewed by humans") conflicts with ADR 0013 ("the merge is the operator's alone"). Nothing
  here proposes overriding it.
- **The biggest gap is the validation harness.** The factory has no tests yet. The repo has no
  manifests, no CI and no verify script; the only test is `.claude/hooks/test.sh`. `/implement-spec`
  runs `tdd` per ticket, and `tdd` needs test seams. For a GitOps repo, the "tests" are layered: a
  static build and schema check, policy checks for the ADR rules, and a sync on the kind dev cluster
  with smoke checks.
- **Change `hl-engineer` now, in a small way.** Every part's "Done when" must be a check an agent can
  run, written as the command plus the expected signal plus where it runs (static or dev). StrongDM
  puts it as "Spec + Test Suite = Complete Intent"; Anthropic says specs should "end with an end-to-end
  verification step". This also gives `tdd` its pre-agreed seams. `tdd` runs inside implementer
  subagents, and those subagents cannot ask the operator.
- **Build next, in this order, each when its trigger appears:**
  1. a static verify script, plus CI that runs it;
  2. a dev end-to-end check;
  3. a hook that refuses to open a PR until verify passes;
  4. a guard that keeps checks from being rewritten to pass.

## Findings

### 1. Where the term comes from

| Source | Date | What it says | Kind |
| --- | --- | --- | --- |
| Bob Bemer, "The economics of program production" | 1968 | Credited as the origin of "software factory" by [Osmani](https://addyosmani.com/blog/software-factories/) | historical; original not read (**unverified**) |
| Greenfield and Short, *Software Factories* (Wiley) | 2004 | "Software Factories significantly increase the level of automation in application development at medium to large companies" ([softwarefactories.com](https://softwarefactories.com/TheBook.html)) | pre-LLM; model-driven code generation |
| US DoD DevSecOps "software factories" (Kessel Run, 2017 on) | 2017– | A software factory is a CI/CD pipeline plus a team; the DoD PDF returned 403, so only secondary sources were read (**unverified**) | pre-LLM |
| [Dan Shapiro, "The Five Levels"](https://www.danshapiro.com/blog/2026/01/the-five-levels-from-spicy-autocomplete-to-the-software-factory/) | 2026-01-23 | Level 4: "You write a spec. You argue with it about the spec." and "Then you leave for 12 hours, and check to see if the tests pass." Level 5: "It's a black box that turns specs into software." "Dark Factory" comes from Fanuc's robot factory: "It's dark, because it's a place where humans are neither needed nor welcome." | primary; coins the levels |
| [Simon Willison on the five levels](https://simonwillison.net/2026/Jan/28/the-five-levels/) | 2026-01-28 | Level 5: "The dark software factory, like a factory run by robots where the lights are out because robots don't need to see." "Nobody reviews AI-produced code, ever." | secondary; popularised it |
| [StrongDM, "Software Factories and the Agentic Moment"](https://factory.strongdm.ai) (Justin McCarthy, CTO) | 2026-02-06 | "Code **must not be** written by humans"; "Code **must not be** reviewed by humans"; "If you haven't spent at least $1,000 on tokens today per human engineer, your software factory has room for improvement" | primary; the one operational definition |
| [Simon Willison on StrongDM](https://simonwillison.net/2026/Feb/7/software-factory/) | 2026-02-07 | "Having the agents write tests only helps if they don't cheat and `assert true`." | secondary, with critique |
| [Eran Kahana, Stanford Law](https://law.stanford.edu/2026/02/08/built-by-agents-tested-by-agents-trusted-by-whom/) | 2026-02-08 | "When the builder and the inspector share the same blind spots"; "Existing legal frameworks assume someone, somewhere, looked at the work. Here, nobody did." | critique |
| [Addy Osmani, "Software Factories, Light and Dark"](https://addyosmani.com/blog/software-factories/) | 2026-07-20 | "A software factory is many harnessed loops running at once."; "Verification, not generation, is the real constraint on a factory." A lit factory keeps people "where judgment lives". | essay; light/dark distinction |
| [Factory (factory.ai → factory.com)](https://factory.com/) | current | "Factory is an agent-native software development platform"; the phrase "Build Your Software Factory" appears only in the page title | vendor marketing |
| [TrueFoundry](https://www.truefoundry.com/blog/software-factory-agentic-enterprise-guide), [Gravitee](https://gravitee.io/corpus/gen-2260/software-factory/ai-agent-software-factory.html) | 2026 | One uses the phrase for an AI-built delivery pipeline, the other for governing fleets of agents (search-result summaries only) | vendor marketing; definitions conflict |

Anthropic does not use the term. A search of anthropic.com and claude.com found only customer stories
about the company Factory ([anthropic.com/customers/factory](https://www.anthropic.com/customers/factory)).
No GitHub primary source using "software factory" for Copilot or Agent HQ was found.

### 2. The building blocks the sources describe

- **Seed (intent intake).** "Every piece of software needs an initial seed." A seed can be a PRD, a
  spec, a few sentences, or an existing codebase ([StrongDM principles](https://factory.strongdm.ai/principles)).
- **Interactive versus non-interactive work.** Interactive work is "The familiar cadence: generate,
  clarify, generate, approve, correct." Non-interactive work is "Tasks that are already fully
  specified." And: "Spec + Test Suite = Complete Intent" ([Shift Work](https://factory.strongdm.ai/techniques/shift-work)).
- **A validation harness as the gate.** "Your validation harness must be end-to-end, as close to the
  real environment as possible." The loop runs "until the holdout scenarios pass (and stay passing)"
  ([principles](https://factory.strongdm.ai/principles)).
- **Scenarios as a holdout set.** "We repurposed the word scenario to represent an end-to-end 'user
  story', often stored outside the codebase." The reason: "Tests can be reward hacked" and "A test,
  stored in the codebase, can be lazily rewritten to match the code." The result is scored
  probabilistically: "We use the term satisfaction to quantify this validation"
  ([factory.strongdm.ai](https://factory.strongdm.ai)).
- **Digital twins of dependencies.** "Behavioral clones of the third-party services our software
  depends on." These allow tests "at volumes and rates far exceeding production limits", and tests of
  "failure modes that would be dangerous or impossible against live services"
  ([DTU](https://factory.strongdm.ai/techniques/dtu)).
- **A feedback loop.** "A sample of the output, fed back into the inputs"
  ([principles](https://factory.strongdm.ai/principles)).
- **An orchestration engine with gates and checkpoints.** StrongDM's own pipeline spec includes human
  gates and resume. A `wait.human` node is a "Human-in-the-loop gate. Blocks until a human selects an
  option." The engine "saves a serializable checkpoint" after each node. A `goal_gate` node "must reach
  `SUCCESS` or `PARTIAL_SUCCESS` before the pipeline can exit"
  ([attractor-spec.md](https://github.com/strongdm/attractor/blob/main/attractor-spec.md), Apache-2.0,
  last pushed 2026-03-17). Even a dark factory keeps human gates on intent.
- **The human role and autonomy levels.** At Level 4, "You plan schedules. You review plans."
  ([Shapiro](https://www.danshapiro.com/blog/2026/01/the-five-levels-from-spicy-autocomplete-to-the-software-factory/)).
  Engineers move "from building the code to building and then semi-monitoring the systems that build
  the code" ([Willison](https://simonwillison.net/2026/Feb/7/software-factory/)).
- **Cost.** StrongDM's $1,000 a day per engineer, quoted above. Willison: "If these patterns really do
  add $20,000/month per engineer to your budget they're far less interesting to me."

### 3. What Anthropic says that bears on building one with Claude Code

- **Give the agent a check it can run.** "Give Claude a check it can run: tests, a build, a screenshot
  to compare. It's the difference between a session you watch and one you walk away from." And: "The
  `/goal` and Stop hook versions are what let an unattended run finish correctly without you"
  ([best practices](https://code.claude.com/docs/en/best-practices)).
- **Write the spec around its proof.** "The most useful specs are self-contained: they name the files
  and interfaces involved, state what is out of scope, and end with an end-to-end verification step
  that proves the feature works." And: "Once the spec is complete, start a fresh session to execute
  it." (same page).
- **Keep the worker and the judge apart.** "Separating the agent doing the work from the agent judging
  it proves to be a strong lever"; "tuning a standalone evaluator to be skeptical turns out to be far
  more tractable". Before building, the agents agree on "what 'done' looked like for that chunk of
  work before any code was written". The full harness cost "over 20x" a solo run ($200 and about 6
  hours, against $9 and 20 minutes). And: "every component in a harness encodes an assumption about
  what the model can't do on its own"
  ([harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps),
  2026-03-24).
- **Work one feature at a time and end in a clean state.** Agents were asked "to work on only one
  feature at a time", because "Claude declares victory on the entire project too early". A "clean
  state" means "the kind of code that would be appropriate for merging to a main branch"
  ([effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents),
  2025-11-26).
- **Start simple.** "finding the simplest solution possible, and only increasing complexity when
  needed". On coding agents, human review "remains crucial for ensuring solutions align with broader
  system requirements"
  ([building effective agents](https://www.anthropic.com/engineering/building-effective-agents),
  2024-12-19).
- **Parallel agents cost a lot and suit coding less.** "multi-agent systems use about 15× more tokens
  than chats"; "most coding tasks involve fewer truly parallelizable tasks than research"
  ([multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system),
  2025-06-13).
- **Agent teams are experimental.** "Agent teams are experimental and disabled by default." For
  "sequential tasks, same-file edits, or work with many dependencies, a single session or subagents
  are more effective" ([agent teams](https://code.claude.com/docs/en/agent-teams)).
- **What a `/goal` evaluator can judge.** The evaluator "doesn't run commands or read files
  independently". A good condition has "One measurable end state" and "A stated check"
  ([goal](https://code.claude.com/docs/en/goal)).
- **Running Claude in CI.** `claude-code-action` can "turn issues into pull requests". It needs an
  `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` repository secret, and the official Claude GitHub
  App asks for broader permissions, including Workflows and Actions write
  ([GitHub Actions](https://code.claude.com/docs/en/github-actions)).

### 4. Mapping: factory block → this repo

| Block | Status here | Evidence |
| --- | --- | --- |
| Seed / intent intake | present | issue with Goal, Done when, Out of scope, Depends on; `.claude/hooks/issue-template.sh`; `hl-engineer` stage 0 refuses an issue missing a heading |
| Interactive shaping (Shift Work, interactive half) | present (draft) | `hl-engineer` stage 1 (`grilling`, `domain-modeling`), with `AskUserQuestion` gates (ADR 0016) |
| Spec / plan | present (draft) | stage 2 brief `02-plan.md`; plan comment template in `reference.md` |
| Independent judge of the plan | present (draft) | `hl-plan-reviewer`, three lenses, read-only tools; bounded at 3 rounds by `flow-review-bound.sh` |
| Decomposition into a task graph | present | stage 3 vertical slices; `to-tickets` native sub-issues and blocking links (ADR 0016) |
| Adopt-or-build research | present (draft) | stage 4; checklist in `reference.md` |
| "Done" agreed before build (sprint contract) | partial | plan comment has "Done when, per part: observable checks"; nothing requires them to be runnable, and stage 6 does not check that they survived `to-tickets` |
| Parallel implementation agents | present upstream, operator-typed | `implement-spec`: implementer subagents in worktrees, a merger subagent, a frontier of ready tickets |
| Validation harness, static | **missing** | no manifests, no `.github/workflows/`, no verify script; `git ls-files` shows only docs, hooks and `tools/gh*` |
| Validation harness, dev end to end | planned, not built | ADR 0004 (kind plus local OCI artifact); issues #4, #5, #6 open |
| Holdout scenarios outside the code | missing | the nearest thing is "Done when" in issues, which the App can edit (ADR 0013 grants Issues write) |
| Digital twin of dependencies | partial by design | dev is a twin of prod ("One cluster recipe for all environments", ADR 0004); no twins for Cloudflare, HCP Terraform or GitHub; qa deferred |
| Feedback loop until green (build) | missing | the tools are documented (`/goal`, Stop hook; harness.md "Loops" row), but there is no check for them to run |
| Code review agent | present upstream | `implement` and `implement-spec` call `code-review` |
| Human role / autonomy level | deliberately Level 4, lit | ADR 0013 (operator merges, ruleset plus `git-guard.sh`); ADR 0016 gates |
| Guardrails | present | mandatory sandbox, denied reads (ADR 0014); `git-guard.sh`; push protection |
| State, checkpoint, resume | present (draft) | `.flow/<issue>.json` and briefs; `/hl-engineer resume <n>` |
| Pipeline engine | deliberately Claude Code | conductor skill, not Attractor or LangGraph; the Agent SDK only if code orchestration is ever needed (ADR 0015) |
| Event-triggered or CI agents | not adopted | no `claude-code-action`; would need a model-key secret and another App identity (needs an ADR; see Conflicts) |
| Observability and evals of the factory | missing | the trace is the issue's progress comments; no run log, no eval set for `hl-engineer`; `retro` and `skill-creator` evals are available |
| Cost controls | partial | review-round bound only; no token or turn budget per run |

### 5. Verification for a GitOps repo: what the factory's tests would be

| Layer | Tool and what it does | Needs a cluster | Catches | Exists today |
| --- | --- | --- | --- | --- |
| Render | `flux build kustomization --dry-run`: "Build in dry-run mode without connecting to the cluster"; "variable substitutions from Secrets and ConfigMaps are skipped in dry-run mode" ([docs](https://fluxcd.io/flux/cmd/flux_build_kustomization/)) | no | broken Kustomize, bad paths | no |
| Schema | kubeconform, "A FAST Kubernetes manifests validator, with support for Custom Resources!"; `-strict`: "disallow additional properties not in schema or duplicated keys"; CRDs need their schemas supplied ([repo](https://github.com/yannh/kubeconform)) | no | typos, wrong API versions | no |
| Repo audit | `fluxcd/agent-skills` `gitops-repo-audit` (Apache-2.0, pushed 2026-10-24): "runs Kubernetes schema validation, detects deprecated Flux APIs"; its `validate.sh` "exit[s] non-zero with a count of invalid resources and failed builds". Requires `flux`, `flux-schema`, and `kustomize` or `kubectl` | no | deprecated Flux APIs, RBAC and secrets smells | no (sister skill `gitops-knowledge` is installed) |
| Policy (the ADR rules) | Kyverno CLI, "validate and test policy behavior to resources prior to adding them to a cluster" ([docs](https://kyverno.io/docs/kyverno-cli/)); or a short script | no (implied; **unverified**) | missing `deletionPolicy: Orphan` or the prune-disabled annotation (ADR 0012); amd64-only images (ADR 0004) | no |
| Diff against dev | `flux diff kustomization`: "does a build, then it performs a server-side dry-run and prints the diff"; exit 0 means no diff, 1 means changes, more than 1 means an error ([docs](https://fluxcd.io/flux/cmd/flux_diff_kustomization/)) | yes (dev) | unintended prunes and drift before sync | no |
| Sync on dev | push the OCI artifact; wait for Kustomizations and HelmReleases to be Ready (ADR 0004) | yes (dev) | ordering, Helm and prune behaviour, "where GitOps surprises live" (ADR 0004) | no; cluster not built (#4, #5) |
| Smoke and scenario checks | the per-part "Done when" commands; Kyverno Chainsaw if declarative e2e is wanted ("Stronger end-to-end testing tool", [docs](https://kyverno.github.io/chainsaw/latest/)) | yes (dev) | the behaviour the issue asked for, such as #6's "an attempt to create anything else is refused by Kubernetes" | no |

The holdout idea maps onto infra checks cleanly. The issue's "Done when" is written before the build,
outside the branch, so an implementer cannot quietly weaken it. It is not a true holdout, though: the
implementer can still read it, and the App can edit it.

## Recommendations

### Is `hl-engineer` the right first stage?

Yes. Every source puts the human at intent and specs (Shapiro's Level 4; StrongDM's interactive
shift; Anthropic's "interview me ... write a complete spec", then "a fresh session to execute it").
`hl-engineer` already matches the documented structure: planner, an independent bounded judge,
decomposition into a graph, checkpoints and resume. Stopping at tickets (ADR 0016) lines up with the
Shift Work boundary. What it lacks is the factory's "Complete Intent": a spec without its test suite.

### Change in `hl-engineer` now (small, no new ADR)

1. **Runnable "Done when".** In `reference.md` ("Plan comment"), replace `<observable checks>` with
   `<check>: \`<command>\` → <expected signal> (static | dev | operator)`. In SKILL.md stages 2 and 3,
   require one such check per part and mark anything only a person can judge as `operator`. This is
   StrongDM's "Spec + Test Suite = Complete Intent" and Anthropic's "end with an end-to-end
   verification step".
2. **Name the seams.** `tdd` says "No test is written at an unconfirmed seam" and tells the agent to
   confirm seams "with the user". Under `implement-spec`, `tdd` runs inside implementer subagents,
   which cannot ask the operator ([hl-engineer-flow.md](hl-engineer-flow.md)). Writing the checks into
   the approved plan makes them the pre-agreed seams. (Whether `tdd` treats them that way is
   **unverified**.)
3. **Newcomer lens.** In `hl-plan-reviewer.md`, add: flag any part whose "Done when" an agent could not
   run without this conversation, or whose check could pass while the goal fails.
4. **Stage 6 close-out.** Also check that each ticket's "Done when" kept the commands from
   `03-parts.md`. `to-tickets` may paraphrase them into prose.

### Next pieces, in order, each with its trigger (harness.md: "nothing is built up front")

1. **Static verify script plus CI.** Trigger: the first PR that adds Flux manifests (issue #6's track).
   One script, for example `tools/verify`, runs render, schema, and the ADR 0012 and ADR 0004 policy
   checks. A GitHub Actions job runs the same script on every PR, with no model and no secrets, which
   gives the operator's merge a gate that does not depend on Claude. Run adopt-or-build first:
   `gitops-repo-audit`'s `validate.sh` against kubeconform plus a short policy script.
2. **Dev end-to-end check.** Trigger: the dev cluster exists (#4 and #5 closed). This is the same
   script's `dev` mode: push the artifact, wait for Ready, run the `dev` checks from the ticket, and
   run `flux diff` before sync. This is the "harness as close to the real environment as possible".
3. **PR gate hook.** Trigger: once 1 exists. This is a rule that must hold every time (harness.md
   rule 2), so it is a hook and not a sentence. It is a `PreToolUse` hook on `gh pr create` that
   blocks unless verify passed on `HEAD`. During `/implement`, the operator can add
   `/goal tools/verify exits 0` for the loop.
4. **Holdout guard.** Trigger: the first time an implementer edits a check to make it pass (the
   failure Willison and StrongDM name). This is a `PreToolUse` hook that denies edits to the verify
   script and policy files on build branches, or that moves scenario checks out of the branch. It is
   rung 2 of the ADR 0016 ladder.

Already planned and unchanged: `hl-add-app` as a saved workflow after the KRO prototype. After two or
three real `hl-engineer` runs, run `retro` and remove harness pieces that no longer earn their cost
("every component in a harness encodes an assumption").

### Conflicts with ADRs (flagged, not overridden)

- **Level 5, the dark factory.** No human review conflicts with ADR 0013. Recommendation: stay lit.
- **`claude-code-action` in CI.** It adds a model-credential secret and either the broad official
  Claude App or a custom one, which is a second agent identity beside ADR 0013's App. That needs its
  own ADR. CI that runs only `tools/verify` needs neither and conflicts with nothing.
- **Adopting `gitops-repo-audit`.** Installing it is a new downloaded skill under ADR 0014 (lock file,
  never edited). Its `flux-schema` binary needs its download host on the sandbox allowlist (ADR 0014:
  "grows one line per tool").
- **Agent teams or an external engine like Attractor.** Both are outside ADR 0015 ("Orchestration
  stays inside Claude Code"), and teams are experimental. Not recommended.

## Open questions

- **Where do checks live so the implementer cannot rewrite them?** In the issue (the App can edit
  it), in the branch (the implementer can edit it), or in a hook-protected path? Settle at piece 4.
- **Boolean or probabilistic acceptance?** StrongDM's "satisfaction" fits fuzzy user behaviour; infra
  checks look mostly pass or fail. Revisit if smoke checks turn out flaky.
- **Budget.** What spend per run does the operator accept? Anthropic's harness ran at 20x a solo run;
  StrongDM targets $1,000 a day per engineer. A turn or token bound per stage is cheap to add once a
  number exists.
- **Digital twins for external services** (Cloudflare, HCP Terraform, external-dns). qa is deferred
  (ADR 0004), so this is open until then.

## Not verified

- Bemer (1968) as the origin of "software factory". Only Osmani's attribution was read.
- The DoD definition. The DoD CIO PDF returned HTTP 403, so only secondary write-ups were seen.
- The title of Shapiro's post. The fetched page reads "…to the Dark Factory"; the URL slug and
  Willison's link read "…to the Software Factory".
- The TrueFoundry and Gravitee definitions. These come from search-result summaries; the pages were
  not fetched.
- That the Kyverno CLI's `apply` and `test` run without a cluster. The docs imply it but do not state
  it.
- That kubeconform and `flux-schema` have schemas for the Flux Operator and KRO CRDs this repo will
  use.
- `gitops-repo-audit`'s maintainer count and security posture (adopt-or-build checklist). Only the
  licence and the last push were checked.
- Whether `tdd`, run inside `implement-spec` subagents, treats checks written in a ticket as
  pre-agreed seams.

## Sources

- Term and practice:
  - Dan Shapiro, [The Five Levels](https://www.danshapiro.com/blog/2026/01/the-five-levels-from-spicy-autocomplete-to-the-software-factory/), 2026-01-23
  - StrongDM: [factory.strongdm.ai](https://factory.strongdm.ai), [principles](https://factory.strongdm.ai/principles), [techniques](https://factory.strongdm.ai/techniques), [Shift Work](https://factory.strongdm.ai/techniques/shift-work), [DTU](https://factory.strongdm.ai/techniques/dtu), [strongdm/attractor](https://github.com/strongdm/attractor) (`attractor-spec.md`, read through the GitHub API)
  - Simon Willison, [the five levels](https://simonwillison.net/2026/Jan/28/the-five-levels/) and [software factory](https://simonwillison.net/2026/Feb/7/software-factory/)
  - Addy Osmani, [Software Factories, Light and Dark](https://addyosmani.com/blog/software-factories/), 2026-07-20
  - Eran Kahana, [Built by Agents, Tested by Agents, Trusted by Whom?](https://law.stanford.edu/2026/02/08/built-by-agents-tested-by-agents-trusted-by-whom/), 2026-02-08
  - [softwarefactories.com](https://softwarefactories.com/TheBook.html) (Greenfield and Short, 2004); [factory.com](https://factory.com/); [TrueFoundry](https://www.truefoundry.com/blog/software-factory-agentic-enterprise-guide); [Gravitee](https://gravitee.io/corpus/gen-2260/software-factory/ai-agent-software-factory.html)
- Anthropic:
  - [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps), 2026-03-24
  - [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), 2025-11-26
  - [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents), 2024-12-19
  - [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system), 2025-06-13
  - Claude Code docs, fetched 2026-10-25: [best practices](https://code.claude.com/docs/en/best-practices), [goal](https://code.claude.com/docs/en/goal), [agent teams](https://code.claude.com/docs/en/agent-teams), [GitHub Actions](https://code.claude.com/docs/en/github-actions)
- Verification tools:
  - Flux CLI: [flux build kustomization](https://fluxcd.io/flux/cmd/flux_build_kustomization/), [flux diff kustomization](https://fluxcd.io/flux/cmd/flux_diff_kustomization/)
  - [kubeconform](https://github.com/yannh/kubeconform); [Kyverno CLI](https://kyverno.io/docs/kyverno-cli/); [Chainsaw](https://kyverno.github.io/chainsaw/latest/)
  - [fluxcd/agent-skills](https://github.com/fluxcd/agent-skills) at `742d224` (`gitops-repo-audit`, `gitops-cluster-debug`; licence and push date through the GitHub API)
- Local:
  - ADRs 0004, 0012, 0013, 0014, 0015, 0016; `docs/agents/harness.md`, `docs/agents/issue-tracker.md`
  - `.claude/skills/{hl-engineer,implement,implement-spec,tdd}`, `.claude/agents/hl-plan-reviewer.md`, `.claude/hooks/{flow-review-bound.sh,test.sh}`, `.claude/settings.json`
  - issues #2 and #6 through `gh`
