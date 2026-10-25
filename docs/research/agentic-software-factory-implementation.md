# Agentic software factory: implementing it in this repo

Checked 2026-10-25. Produced with the bundled `/deep-research` workflow: five search angles, 28
primary sources fetched, 120 claims extracted, the 25 highest-ranked claims put to a three-vote
adversarial verification (Opus 5.5 verifiers), 21 confirmed and 4 refuted. Two of the four
refutations were then overturned by direct checks against the primary source (noted inline). The
verification cap meant only angles 1 and 2 (validation harness, unattended runs) received verified
claims; the claims for angles 3 to 5 (shipping apps, the dashboard, sequencing and economics) come
from the same fetch step but were **not** adversarially verified and are marked as such. Quotes came
through fetch tools that extract page text; GitHub file contents were read through the GitHub API.

Builds on [agentic-software-factory.md](agentic-software-factory.md), which settled the term, mapped
the factory's blocks onto this repo and listed the verification layers. Nothing there is repeated
unless this note changes it.

Question, from the operator: "Research how I would implement the agentic software factory in the
context of this repo. Most of the work will be devops/gitops/platform stuff but we will need to
create some apps as well (the dashboard)."

"The dashboard" is a homelab landing page in the Dashy or Homepage family (operator's
clarification, 2026-10-25). The deep-research run read it as the factory's own observability
surface, so its fourth angle was mis-aimed. Section 4 was therefore replaced by a direct
adopt-or-build pass on the four common candidates, checked the same day against the GitHub API, the
registries' manifest lists and each project's documentation, without the three-vote step. The
observability material the run gathered is kept in section 4b because it serves the cost ledger.

## Short answer

- **The static gate is Flux Schema, not kubeconform.** The official Flux reference repo migrated
  its pull-request check to `flux schema validate` against the ecosystem catalog in July 2026. The
  built-in catalog (flux-schema v0.17.0, released 2026-10-23) already holds FluxInstance,
  FluxReport, ResourceSet and ResourceSetInputProvider; the ecosystem catalog at
  schemas.fluxoperator.dev holds the KRO ResourceGraphDefinition, CloudNativePG Cluster and Database,
  Longhorn, Kyverno, cert-manager, external-dns and the VictoriaMetrics operator. Missing: the
  per-app instance kinds KRO generates from an RGD, Headlamp and OpenBao. Verified 3-0 by direct
  fetch of the catalog index.
- **The script to wrap already exists and is Apache-2.0.** `fluxcd/agent-skills`'s
  `gitops-repo-audit/scripts/validate.sh` is a vendored copy of the flux-schema action script
  (header: "DO NOT EDIT: this file is vendored from the flux-schema action"). It builds every
  kustomize overlay, validates with the ecosystem catalog by default, keeps going on failure and
  exits non-zero with a valid/invalid/skipped tally. The workflow's verifiers refuted this 0-3; the
  GitHub API read of the file (commit `bb68a58`, 2026-10-25) confirms it. Treat the refutation as
  "could not fetch".
- **The dev loop has a proven shape:** `flux push artifact` with `--revision '<branch>@sha1:<sha>'`,
  `flux reconcile ks <name> --with-source`, then
  `kubectl -n flux-system wait kustomization/<name> --for=condition=ready --timeout=5m`, plus one
  smoke `curl`. The reference repo keeps that in a separate workflow from the schema gate and runs
  it against a kind cluster. ADR 0004's persistent kind dev cluster fits; per-PR ephemeral clusters
  are not needed.
- **The "loop until green" primitive is a command-type Stop hook** that runs the verify script and
  blocks with the failure as `reason`. `/goal` cannot run commands. Both are bounded by an
  8-consecutive-continuation cap. Headless runs take `--permission-prompts none`,
  `--max-budget-usd <N>` and `--output-format json`, which returns `total_cost_usd` per run.
  **Never pass `--bare`:** it skips the project's hooks, so git-guard and any PR gate would not run.
  It is slated to become the `-p` default, so the launcher must guard against that.
- **ADR 0013 is enforced by the ruleset, not by App permissions.** The App's Contents write
  permission can merge a PR through the API. A ruleset's required status check can be bound to one
  GitHub App (the GitHub Actions app) as the only accepted source, so the `verify` status cannot be
  faked by the agent's App. Loophole: a `pull_request` workflow runs the workflow file from the PR
  head. Push rulesets (path restrictions) are unavailable on a Free public repo, so protect
  `.github/workflows/**`, the verify script and any holdout directory with CODEOWNERS and required
  code-owner review.
- **claude-code-action stays out for now.** It rejects bot actors by default, so the repo's App
  (`gaserban-homelab-claude[bot]`) could not trigger it anyway; it needs a model credential in the
  repo and either the broad official Claude App or a second custom App. That is an ADR, as the prior
  note said.
- **The dashboard is a landing page, and adopt-or-build was run directly.** All four common
  candidates are maintained, publish amd64 and arm64 images and can be pinned by digest. Homepage
  (GPL-3.0) is the only one whose content comes from the platform: it discovers apps from Ingress
  and Gateway API HTTPRoute annotations, so the KRO template can register every app automatically.
  It fails the checklist's "permissive licence" as written, which needs an ADR 0016 call for
  software that is only deployed. Dashy (MIT) is the fallback, with UI write-back disabled and its
  JSON schema in the verify script. Homarr (Apache-2.0) passes the checklist but keeps its state in a
  database; Glance (AGPL-3.0) has one maintainer and no Kubernetes discovery. Building one is viable
  only as the factory's first custom app.
- **Nothing about app pipelines or costs was verified.** The extracted evidence (sections 3 and 5)
  points at `docker/github-builder` reusable workflows for native arm64 builds on GitHub-hosted
  `ubuntu-24.04-arm` runners, `actions/attest@v4` for provenance and SBOM, Flux ImagePolicy
  `digestReflectionPolicy: Always` for digest pinning, and Flux Operator ResourceSet previews per
  PR. Per-issue cost figures do not exist in print; the headless JSON `total_cost_usd` and Claude
  Code's OpenTelemetry metrics are the way to get one here.
- **Three research papers qualify the "holdout guard".** Hidden tests add little over an LLM judge
  for detecting reward hacking; the visible-to-holdout pass-rate gap grows about 28 points per
  tenfold increase in code size, which argues for small tickets; and an agent's self-report of
  progress carried no information in a preregistered pilot, while in-band judges could not close the
  gap. Acceptance must be an out-of-band, externally grounded pass or fail: the CI status and the
  cluster's Ready condition, not a reviewer subagent's verdict.
- **Order:** static gate (A) before the first KRO app, the ruleset binding (B) the moment the gate
  exists, the dev e2e loop (C) with #4, #5 and #6, then the Stop hook and headless launcher, then
  holdout protection, then the app pipeline, then the dashboard.

## Findings

### 1. Validation harness for a Flux Operator and KRO repo (verified)

| Layer | Tool | Cluster | Catches | Vote |
| --- | --- | --- | --- | --- |
| Render | `kustomize build --load-restrictor=LoadRestrictionsNone <dir>` or `flux build`, piped to the validator; `flux envsubst --strict` reproduces `postBuild.substitute` locally; `flux-operator build rset -f` renders a ResourceSet | no | broken overlays, bad paths, unresolved variables | 3-0 (the claim that `flux schema validate` builds directories itself like kustomize-controller was refuted 1-2: run the build yourself and pipe) |
| Schema and CEL | `flux plugin install schema`, then `flux schema validate` with the built-in catalog plus `--schema-location ecosystem`; `--skip-json-path 'v1/Secret:/sops'`; `--skip-missing-schemas`; `-o junit` for CI; config in `.fluxschema.yml` (`schema.plugin.fluxcd.io/v1beta1`, kind Config) | no | every field against JSON Schema, `x-kubernetes-validations` CEL with the API server's engine, duplicate YAML keys, DNS-1123 names | 3-0 |
| Deprecated APIs | `flux migrate -f . --yes` then fail on a non-empty `git diff` | no | old Flux API versions | 3-0 (reference repo) |
| Policy (ADR rules) | a short script over the rendered stream: `deletionPolicy: Orphan` and the `kustomize.toolkit.fluxcd.io/prune: disabled` annotation on stateful objects (ADR 0012); image references pinned by digest and multi-arch (ADR 0004) | no | the repo's own conventions | not researched further; the prior note's Kyverno CLI option still stands |
| Render and diff (optional) | flate (`flate test all`, `flate diff --base <rev>`), or flux-local (Apache-2.0) | no | PR-level diff comments, rendering regressions | 3-0 on what flate does; see licence below |
| Dev e2e | push the OCI artifact, `flux reconcile ks --with-source`, `kubectl wait --for=condition=ready --timeout=5m` on Kustomizations and HelmReleases, one smoke `curl` | yes (dev) | ordering, Helm, prune, "where GitOps surprises live" | 3-0 |

**Catalog coverage, checked against the live index on 2026-10-25.** Built-in (flux-schema v0.17.0,
built from flux2 v2.9.6, flux-operator v0.61.0, Kubernetes v1.37.1, Gateway API v1.6.3): the four
Flux Operator kinds above. Ecosystem (index generated 2026-10-24, 123 projects, rebuilt daily): kro
v0.9.4 with `ResourceGraphDefinition` v1alpha1, cloudnative-pg `Cluster` and `Database` v1,
longhorn v1.13.0, kyverno v1.19.2, cert-manager v1.21.3, external-dns v0.24.0,
victoriametrics-operator v0.75.1. Absent: Headlamp, OpenBao, and every instance kind KRO generates
from an RGD (for example the Mealie request kind). For those, either `flux schema extract crd`
against the dev cluster and commit the result, or accept `--skip-missing-schemas` and print the
skipped tally. The verify script should fail if a kind this repo owns (`fluxcd.controlplane.io`,
`kro.run`, `postgresql.cnpg.io`) lands in "skipped"; both kubeconform's `-ignore-missing-schemas`
and Flux Schema's `--skip-missing-schemas` are silent, and the verifier confirmed by download that
the flux2 v2.9.6 `crd-schemas.tar.gz` holds no FluxInstance, ResourceSet or RGD schema.

**The reference repo's two workflows** (`fluxcd/flux2-kustomize-helm-example`, last commit PR #130
"Migrate manifest validation to the Flux Schema ecosystem catalog", 2026-07-08). `test.yaml` on
`pull_request`: `fluxcd/flux-schema/actions/setup@main`, `fluxcd/flux-schema/actions/validate@main`
with `path: '.'` and `config: '.fluxschema.yml'` (`schemaLocation: [ecosystem]`,
`skipJSONPath: [Secret:/sops]`, `skipMissingSchemas: true`), then the `flux migrate` diff check.
`e2e.yaml` on `push` to any branch: `helm/kind-action` v1.14.0 (kind v0.32.0,
`kindest/node:v1.36.1`), `flux install --components-extra source-watcher` (plain Flux, not the
Operator), a GitRepository at the pushed branch with the job's `GITHUB_TOKEN`, then `kubectl wait`
on the `infra-controllers` and `apps` Kustomizations and the `podinfo` HelmRelease, then
`curl -sSf -H 'Host: podinfo.staging' http://localhost:8080` through a port-forward. Lessons: the
readiness gate is `kubectl wait --for=condition=ready` plus one HTTP check, and it lives in a
different workflow from the schema gate. Adapting it means installing the Flux Operator and syncing
from an OCI artifact; the reference does not exercise FluxInstance or ResourceSet. Its actions are
pinned `@main`, which this repo's pin-by-digest rule does not allow.

**The local OCI loop** (`stefanprodan/flux-local-dev`, last pushed 2023-12-30, a pattern source
only). CI runs the static gate alone with `contents: read`. Locally, `make up` pushes three
artifacts (cluster, infra, apps) with
`flux push artifact oci://<registry>/<name> --path=<dir> --source=$(git config --get remote.origin.url) --revision=...`,
skipping the push when `flux diff artifact` exits 0, forces `flux reconcile ks <name> --with-source`,
and blocks on `kubectl -n flux-system wait kustomization/<name> --for=condition=ready --timeout=5m`.
The registry is a container on the kind network, `localhost:5050` from the host and
`kind-registry:5000` from inside the cluster, and hosts both images and manifest artifacts, which is
what an agent-built app in dev needs too. Current `flux push artifact` docs give `--revision` as
`'<branch|tag>@sha1:<sha>'`. `flux diff artifact` exit codes are undocumented; the script also pushes
on any error. The kind cluster persists until `make down`, which matches ADR 0004.

**Kustomization API facts the checks rely on** (primary docs, extracted, not put to a vote).
`.spec.prune` is required; when true, objects missing from the current revision are garbage
collected in the background. `.spec.deletionPolicy` takes `MirrorPrune` (default), `Delete`,
`WaitForTermination` or `Orphan`; `Orphan` leaves managed objects when the Kustomization is
deleted. `kustomize.toolkit.fluxcd.io/prune: disabled` as a label or annotation protects an object
from pruning; `kustomize.toolkit.fluxcd.io/reconcile: disabled` stops both apply and prune.
`.spec.wait: true` health-checks every reconciled object and ignores `.spec.healthChecks`;
`dependsOn` applies only after the referenced Kustomizations are Ready. The controller detects drift
with a server-side apply dry-run on every reconciliation.

**flate** (`home-operations/flate`): one static Go binary, a rewrite of allenporter/flux-local,
renders and diffs a whole Flux repo offline (Kustomizations, HelmReleases, sources, `postBuild`,
`dependsOn` with CEL `readyExpr`, ResourceSets with Static input providers); `flate test all` emits
PASS/FAIL/SKIPPED and a non-zero exit; a GitHub Action `home-operations/flate/action@main` and a
pre-commit hook exist. Limits: no SOPS decryption, `spec.verify` ignored, no `healthChecks`, dynamic
input providers contribute nothing offline. It is AGPL-3.0, pre-1.0 (v0.6.5, 2026-09-02; the README
references a v0.7.0 tag that does not exist), created 2026-05-21, one dominant committer (864 of
about 1,237 commits), action pinned `@main`. It fails the adopt-or-build checklist on licence,
maintainers and pinning. flux-local (Apache-2.0, needs the flux CLI, no cluster) is the clean
alternative if a render-and-diff layer is wanted. Neither is a prerequisite for the first gate.

**`gitops-repo-audit/scripts/validate.sh`** (read through the GitHub API; the verifiers' 0-3
refutation was wrong). Apache-2.0, vendored from
`fluxcd/flux-schema/actions/validate/validate.sh`, last commit `bb68a58` 2026-10-25. Prerequisites:
flux-schema >= 0.16 (binary or `flux schema` plugin), helm >= 4.0 only with `--helm-charts`.
Defaults when no config: `--schema-location=ecosystem --skip-json-path=/sops --skip-missing-schemas
--verbose --output=text`. Prunes dotfiles, excludes Terraform and Helm chart directories, uses
`flux-schema discover` to validate bases and components only through their overlays, `--envsubst`
reads a dotenv literally like `postBuild.substitute`, `--output-bundle` writes one post-build YAML
with provenance comments ("so tools and AI agents can grep one file"), arguments after `--` go to
`flux-schema validate` verbatim. It keeps going on failure and exits 1 with
`Validation failed: N error(s); N invalid (N valid, N skipped)`. The skill itself is not installed
here (skills-lock.json lists only `gitops-knowledge`); using the script means either installing the
skill (a downloaded skill under ADR 0014) or copying the one file with its header intact.

### 2. Unattended runs and the GitHub gates (verified)

**Headless flags and what they do** (Anthropic docs fetched 2026-10-25; version gates noted).

| Flag or feature | Behaviour | Since |
| --- | --- | --- |
| `--output-format json` | `total_cost_usd` and per-model `modelUsage[].costUSD`; client-side estimates from a price table, not billing; `--continue` and `--resume` report the whole conversation's total | |
| `--max-budget-usd <N>` | print mode only; soft cap checked after each model response; counts subagent spend; may overshoot by one response plus running subagents; stops background work; ends with subtype `error_max_budget_usd` | enforcement v2.1.217 |
| `--permission-prompts none` | denies anything that would prompt unless a `PermissionRequest` hook allows it; tells Claude nobody can approve; removes `AskUserQuestion`; denials listed in `permission_denials` | v2.1.259 |
| `--permission-mode dontAsk` | the locked-down CI baseline | |
| default mode for `-p` | Manual: approval-needing calls are denied unless an allow rule, hook, `canUseTool` or `--permission-prompt-tool` approves | v2.1.302 |
| `--allowedTools` | permission-rule syntax with prefix matching, `Bash(git diff *)` | |
| `--bare` | skips hooks, skills, commands, subagents, plugins, MCP servers, auto memory and CLAUDE.md; never reads OAuth credentials, needs `ANTHROPIC_API_KEY`; "recommended mode for scripted and SDK calls, and will become the default for `-p` in a future release" | limits complete since v2.1.286 |
| without `--bare` | "a `-p` session runs the hooks in a project's `.claude/settings.json` and connects the servers in its `.mcp.json`, even in a folder you've never trusted. A `-p` session shows no workspace trust dialog" | |
| exit codes | 0 success, non-zero failure, 143 on SIGTERM (turn left unfinished); async hooks still running at teardown are killed | |

The `--bare` row was refuted 1-2 by the verifiers and then confirmed verbatim against the headless
page. Consequence: the factory's headless launcher must not pass `--bare`, must watch for the
announced default change, and should assert at start that the project hooks loaded (the OTel
`hook_registered` event, or a `SessionStart` hook that writes a marker, are the available signals).

**Loop primitives.** A Stop hook that exits 2 or returns `{"decision":"block","reason":...}` keeps
Claude working; the input carries `stop_hook_active: true` while continuing. `/goal <condition>` is a
built-in session-scoped prompt-based Stop hook: the background model judges "not yet met", "met" or
"impossible" from the transcript and does not run commands; it works headless as
`claude -p /goal ...`. Prompt hooks (`type: prompt`, 30 s default timeout) return
`{ok, reason, impossible}`; on Stop and SubagentStop the reason becomes the next instruction unless
`impossible: true` ends the turn. All continuation is bounded by an 8-consecutive-continuation cap
that resets on every tool call, applies to SubagentStop, and is changed only with
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (0 disables). A `TaskCompleted` hook that exits 2 keeps a task from
being marked done and feeds stderr back; Anthropic's own example runs the test suite there. Agent
hooks (tool-using, up to 50 turns) are experimental; Anthropic recommends command hooks for
production, which argues for a deterministic verify script as the gate rather than an LLM judge.
Idle `/goal` check-ins are capped at three per goal (v2.1.246) and disabled with
`CLAUDE_CODE_GOAL_CHECKIN_MINUTES=0`; each check-in and each `/loop` wakeup sends the full context.

**claude-code-action v1.** Without a `prompt` input it is interactive: it reacts to `@claude` in
comments, reviews or new issues, plus `assignee_trigger` and `label_trigger`. With a `prompt` it
runs in automation mode on any event including cron. Before Claude starts it fails the run unless
the triggering user has write access (override with `allowed_non_write_users` and a custom
`github_token`) and the actor is human: any `[bot]` actor is rejected unless listed in
`allowed_bots`, "which keeps bots from triggering Claude in a loop"; scheduled runs are attributed to
whoever last changed the cron. The action uses three App permissions (Contents, Issues, Pull
requests, read and write) and runs under a custom App with exactly those, minted with
`actions/create-github-app-token@v1`; the official Claude App's permission set is broad and cannot be
subsetted (Actions, Workflows, Checks, Administration read, Repository hooks). Since 2026-05-21 it
supports Workload Identity Federation, exchanging the job's OIDC token for a short-lived Anthropic
token, so no `ANTHROPIC_API_KEY` secret is stored; otherwise it needs `ANTHROPIC_API_KEY` or
`CLAUDE_CODE_OAUTH_TOKEN` (subscription billing). Commits made with the default `GITHUB_TOKEN` do
not trigger other workflows, so a verify gate would not run on them. Public-repo limits: secrets are
withheld from fork PRs; cron schedules are disabled after 60 days without activity. The docs never
describe merging and say to review before merging.

**Rulesets.** A required status check can name one GitHub App as the only accepted source
(`required_status_checks[].integration_id`); that App needs `statuses:write`, must have recently
submitted a check run and must be tied to a pre-existing required check; a status from any other
identity does not satisfy the rule. Bypass actors can be roles, teams or GitHub Apps, so the agent's
App can be deliberately left off the bypass list. Approvals must come from people with write
permission or a designated code owner; the team-based "required reviewers" rule does not exist on
user-owned repositories. Push rulesets, which carry "Restrict file paths" (fnmatch, 200 entries), are
available only on the Team plan for private and internal repositories, so this public Free-plan repo
cannot fence paths at push time. Precedent: rulesets require one extra approval on PRs opened by
Copilot under its own identity. Current state here (ADR 0013): PR with one approval, stale approvals
dismissed, force push and deletion blocked, admin as the only bypass actor, no required status check
because no CI exists. Loophole the verifier flagged: a `pull_request` workflow executes the workflow
file from the PR head, so an agent that can edit `.github/workflows/` could weaken `verify` and still
get a green status from the GitHub Actions app. Mitigations: the App has no `workflows` permission
(Contents, Issues, Pull requests read and write, Metadata read, per ADR 0013), so pushes touching
workflow files should already be rejected, confirm by test; CODEOWNERS on `.github/workflows/**`,
the verify script, `.fluxschema.yml` and any holdout directory with required code-owner review; or
keep holdout scenarios in a second repository the App is not installed on. If the agent ever runs
inside Actions, its statuses would also come from the GitHub Actions app, so this binding separates
the agent's App from the verifier but not an in-Actions agent from it.

**Cost controls and telemetry.** Anthropic publishes per-developer figures only: about $13 per
developer per active day, $150 to $250 per month, 90% of users under $30 per day; nothing per issue.
Agent teams are off by default (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and use about 7x the tokens
of a standard session. OpenTelemetry export (`CLAUDE_CODE_ENABLE_TELEMETRY=1`,
`OTEL_METRICS_EXPORTER=otlp|prometheus|console`, `OTEL_LOGS_EXPORTER=otlp|console`, no default OTLP
protocol) emits eight metrics including `claude_code.cost.usage` (USD) and `claude_code.token.usage`
with attributes `model`, `query_source` (`main`, `subagent`, `auxiliary`), `agent.name`,
`skill.name`, `plugin.name`, `mcp_server.name`, so spend attributes to hl-engineer and to
hl-plan-reviewer without custom accounting; logs include `api_request` with `cost_usd`,
`tool_decision` with its source, `hook_registered`, `hook_execution_start` and `_complete`,
`subagent_completed` and `safety_event` (category `hook` or `hook_review` when a hook blocks).
Custom subagent names are masked as `custom` unless `OTEL_LOG_TOOL_DETAILS=1`. Two constraints bite
this repo: the exporter variables are ignored in a repository's `.claude/settings.json`, so the
wiring must live in the operator's user or managed settings; and `OTEL_*` is not passed to hooks or
Bash subprocesses, so hooks cannot piggyback on it. Prometheus scrape is `localhost:9464`;
Anthropic's `anthropics/claude-code-monitoring-guide` ships Docker Compose, Prometheus and collector
configs. All cost figures are labelled approximations.

### 3. Building and shipping custom apps through the factory (extracted, not verified)

- **Multi-arch builds.** Docker's page (modified 2026-05-18) shows one job with
  `docker/setup-qemu-action@v4`, `docker/setup-buildx-action@v4`, `docker/build-push-action@v7`
  and `platforms: linux/amd64,linux/arm64`, and warns that emulation "can significantly extend
  build times". The recommended alternative is the `docker/github-builder` reusable workflows
  (`build.yml`, `bake.yml`, `@v1`): with `distribute: true` (default) each platform builds on its own
  runner, Linux Arm on GitHub-hosted `ubuntu-24.04-arm`, and a finalize phase assembles the
  manifest; the calling job needs `contents: read` and `id-token: write`. Native arm64 therefore
  needs no self-hosted runner. Loading a multi-platform image into the runner for a smoke test
  requires the containerd image store (`docker/setup-docker-action` with
  `"containerd-snapshotter": true`) and `load: true`. A `docker-bake.hcl` can own the platform list.
- **Provenance and SBOM.** `actions/attest@v4` with `subject-name` (image without tag),
  `subject-digest` from build-push-action's digest output and `push-to-registry: true`; the job
  needs `id-token: write`, `contents: read`, `attestations: write`, `packages: write`. Verify with
  `gh attestation verify oci://ghcr.io/<org>/<image>:<tag> -R <org>/<repo>` after `docker login`.
  SBOMs go through the same step with `sbom-path` (SPDX or CycloneDX) and verify with
  `--predicate-type`. Verification assumes an online environment, which matters for the sandbox.
- **Digest pinning with Flux image automation.** ImagePolicy v1 (`image.toolkit.fluxcd.io/v1`) has
  `digestReflectionPolicy` with `Never` (default), `IfNotPresent` and `Always`; `Always` keeps
  `.status.latestRef.digest` populated, re-fetched every `interval` (default 10m), which is what a
  digest-pinning ImageUpdateAutomation needs. Selection is one of `semver`, `alphabetical`,
  `numerical`, narrowed by `filterTags` with a regex and capture-group `extract`. ImageRepository
  authenticates with `secretRef` or a provider and accepts `insecure` for a non-TLS registry (the
  kind dev registry). Renovate was not fetched; the two options remain open.
- **ResourceSet overlaps KRO.** The Flux Operator's ResourceSet bundles Flux objects and plain
  Kubernetes objects into one templated unit; per-app inputs can be separate
  ResourceSetInputProviders of type `Static` selected by labels (same namespace required);
  `flux-operator build rset -f` renders it locally; dependencies can target any object with a CEL
  readiness expression; the documented multi-tenancy use case generates Namespace, ServiceAccount,
  RoleBinding, GitRepository and Kustomization per tenant, which is issue #6's "least-privilege
  fence". ADR 0003's prototype should say why KRO over ResourceSet, or split the roles: KRO for the
  app graph, ResourceSet for the Flux objects around it.
- **Preview environments per PR.** A ResourceSetInputProvider of type `GitHubPullRequest` selects
  PRs by a label (`deploy/flux-preview`); the template instantiates a source pinned to the PR head
  and a HelmRelease `app-<PR>`, with the SHA as the image tag and the PR number in the host. A second
  label (`deploy/flux-preview-pause`) added by the build workflow and removed at its end stops the
  provider from exporting inputs before the image exists; a `Receiver` of type `generic` is called
  only at the end of the workflow; otherwise the provider polls per
  `fluxcd.controlplane.io/reconcileEvery: "10m"`. Status returns to the PR through the
  `githubpullrequestcomment` provider (one comment, updated in place) and the `github` commit status
  provider. Teardown is documented only for the merged case; closed-without-merge and label removal
  are not described. The provider needs a PAT or GitHub App token with read access.
- **KRO v0.9.4 examples** (0.10.0-rc.0 exists). Simple schema with defaults
  (`image: string | default="nginx"`), optional children with `includeWhen`, a `status` block of CEL
  references into child status (a per-instance readiness surface the dev check and the dashboard can
  poll), cross-resource references. The SaaS multi-tenant example prescribes TenantEnvironment
  (Namespace, ResourceQuota, NetworkPolicy with `from: - podSelector: {}`), TenantApplication and
  Tenant, with `kubectl get rgd` STATE `Active` and `kubectl get tenant` STATE `ACTIVE` as readiness
  signals; but the page ships only the TenantEnvironment YAML, so nested RGD composition is
  unverified from the docs. The shipped Ingress is AWS ALB specific and must be replaced.
- **Monorepo or app repo.** Not resolved by any source. Hints: the reference repo splits a monorepo
  into per-directory artifacts with an `ArtifactGenerator` so app changes do not reconcile
  infrastructure; the preview guide assumes an app repo with its own chart and CI; the local dev
  registry hosts images and artifacts side by side. Inference: app source and its image build live in
  their own repository with the attestation workflow, and this repo holds only the KRO request and
  the image policy.

### 4. The dashboard: a homelab landing page (checked directly, 2026-10-25)

Operator's clarification: "A dashboard is an app similar to dashy/homepage." The four common
candidates were read against the adopt-or-build checklist (ADR 0016, harness.md). Repository facts
come from the GitHub API, with distinct commit authors over the last 365 days as the proxy for
maintainers; image facts from the manifest lists on `ghcr.io` and `registry-1.docker.io`; behaviour
from each project's documentation.

| Candidate | Licence | Last push; latest release | Committers, 365 days | Image | Configuration model |
| --- | --- | --- | --- | --- | --- |
| Homepage (`gethomepage/homepage`) | GPL-3.0 | 2026-10-25; v2.7.0, 2026-10-23 | 59 authors, 584 commits; one human dominates (shamoon 280, dependabot 223) | `ghcr.io/gethomepage/homepage`, amd64 and arm64, OCI index | YAML files (`settings.yaml`, `widgets.yaml`, `services.yaml`, `kubernetes.yaml`) in a ConfigMap mounted at `/app/config`; discovers apps from Ingress annotations (`gethomepage.dev/enabled: "true"`) and from Gateway API HTTPRoute annotations (`gateway: true`); health via `gethomepage.dev/pod-selector`; needs a ServiceAccount, ClusterRole and ClusterRoleBinding and `HOMEPAGE_ALLOWED_HOSTS` (`$(MY_POD_IP):3000,<host>`); Kubernetes 1.19+, a metrics service; only an unofficial Helm chart |
| Dashy (`Lissy93/dashy`) | MIT | 2026-10-23; 4.9.0, 2026-10-23 | 43 authors, 1,058 commits; one human (lissy93 718, liss-bot 173) | `ghcr.io/lissy93/dashy`, amd64 and arm64, OCI index (docs: "32-bit armv7 and armv6 are not supported") | one `/user-data/conf.yml`, more pages through `pages`; a JSON schema (`ConfigSchema.json`, served at `/schema.json`) and `yarn validate-config`; the UI's "Write to Disk" rewrites `conf.yml` unless `preventWriteToDisk` or `disableConfiguration` is set; no Kubernetes documentation and no discovery |
| Glance (`glanceapp/glance`) | AGPL-3.0 | 2026-10-20; v0.8.7, 2026-10-15 | 16 authors, 67 commits; one human (svilenmarkov 49) | `docker.io/glanceapp/glance`, amd64, arm64 and arm/v7, manifest list; "Single <20mb binary" | one `glance.yml` with `$include` and `${ENV_VAR}`, automatic reload; discovery only from Docker labels through `docker.sock`; `monitor` widget polls URLs; auth needs a `secret-key`; no Kubernetes documentation |
| Homarr (`homarr-labs/homarr`) | Apache-2.0; chart MIT | 2026-10-25; v2.9.1, 2026-10-25 | 74 authors, 2,182 commits; two humans (ajnart 447, Meierschlumpf 118) plus release, Renovate and Crowdin bots | `ghcr.io/homarr-labs/homarr`, amd64 and arm64, OCI index with attestation manifests | official Helm chart (`homarr-labs/charts`, pushed 2026-10-24); a required `db-encryption` Secret; database SQLite on the pod disk or a PVC, or external MySQL or PostgreSQL; optional OIDC and LDAP secrets; state lives in the database (inferred: the chart mounts no configuration file) |

**Checklist.** Maintained within a year: all four. Multi-architecture and pinnable by digest: all
four. Security audits: not verified for any. Permissive licence: Dashy and Homarr pass; Homepage
(GPL-3.0) and Glance (AGPL-3.0) fail the checklist as written. For software this repo deploys but
does not modify or distribute, copyleft imposes no obligation, so whether "permissive" is meant
literally is an ADR 0016 question (flagged under Conflicts). More than one maintainer: Homarr
passes; Homepage has one dominant human committer with a long tail; Dashy and Glance are
single-maintainer projects.

**Fit with the factory.** What matters for an agent-built platform is that the dashboard's content
is declarative and updates itself when an app is added. Homepage reads annotations on the app's own
Ingress or HTTPRoute, so the KRO template can stamp `gethomepage.dev/name`, `gethomepage.dev/group`,
`gethomepage.dev/icon` and `gethomepage.dev/href` onto the route it generates from the request, and
every app that goes through the platform appears on the dashboard with no change to the dashboard.
That is ADR 0003's "apps request, platform provides" applied to the landing page. Dashy and Glance
need their YAML regenerated whenever an app is added (a Kustomize generator or a KRO-managed
ConfigMap can do it, but it is a second source of truth), and Dashy's UI write-back must be switched
off so git stays authoritative. Homarr's state in a database is the opposite of configuration as
code, and it brings a secret and a database into what should be a stateless app.

**Verdict.**

- Adopt Homepage if ADR 0016 accepts copyleft for software that is only deployed. It is the only
  candidate whose content comes from the platform. Deliver it through the KRO template as the second
  app after Mealie: a ConfigMap with `settings.yaml`, `widgets.yaml` and `kubernetes.yaml`
  (`mode: cluster`, `gateway: true`), the ClusterRole from the project's `docs/installation/k8s.md`
  (reads on ingresses, HTTPRoutes, pods, nodes and metrics), `HOMEPAGE_ALLOWED_HOSTS` set to the pod
  IP and the hostname, the image pinned by digest. The cluster-wide read role does not fit #6's
  per-namespace fence, so the platform owns that role and binds it to the dashboard's ServiceAccount
  outside the per-app request.
- Otherwise adopt Dashy (MIT) with `preventWriteToDisk` and `disableConfiguration`, validate
  `conf.yml` in the verify script against the schema, and accept the single-maintainer risk.
- Homarr passes the letter of the checklist and fails the fit. Glance fails both.
- Build only if the operator wants the dashboard to be the factory's first custom app. A
  Homepage-like service is small enough for that: one binary that lists apps from HTTPRoute
  annotations through the Kubernetes API (the same RBAC as Homepage), renders one page and exposes
  a health endpoint. Its "Done when" checks become the factory's first app-level seams: static (unit
  tests, both architectures build, a config schema), dev (Ready, HTTP 200, the Mealie route appears
  on the page). The pipeline is section 3.

### 4b. Factory observability (extracted, not verified; kept for the cost ledger)

The deep-research run researched these as "the dashboard". They are not the landing page, but they
feed step 4's cost ledger and a later observability map under ADR 0010, so the table stays.

| Signal | Source | Permission or constraint |
| --- | --- | --- |
| Ticket graph: parent and child | GitHub `sub_issues` webhook (`parent_issue_added`, `sub_issue_added`, and removals), available to repository webhooks and GitHub Apps; REST issue objects carry `sub_issues_summary` and `parent_issue_url` | Issues read on the App |
| Ticket graph: blocking links | GitHub `issue_dependencies` webhook (`blocked_by_added`, `blocking_added`, and removals); REST `GET .../issues/{n}/dependencies/blocked_by` and `/blocking` (paginated, `per_page` max 100); `issue_dependencies_summary` counts on every issue; `POST .../dependencies/blocked_by` with `issue_id` creates a link (secondary rate limits apply) | Issues read; API version `2026-03-10`; the `issues` event carries none of these actions |
| GitHub Projects | `projects_v2*` webhooks are organization-level only and in public preview | weak for a personal-account repo |
| PR, CI and verify status | `pull_request`, `workflow_run`, `workflow_job`, `check_run`, `check_suite` webhooks; repository webhooks get only `created` and `completed` check runs | Pull requests, Actions or Checks read; payloads over 25 MB are dropped silently |
| Flux sync in dev | notification-controller `generic` provider POSTs each Alert-matched event as JSON with a `Gotk-Component` header; `generic-hmac` signs the body (`X-Signature: sha256=...`); `github` provider writes a commit status; `githubdispatch` fires `repository_dispatch` with `event_type` `{Kind}/{Name}.{Namespace}`; `grafana` provider writes annotations tagged `flux` | none beyond a Secret; `githubdispatch` can start an e2e workflow when a Kustomization becomes Ready |
| Cost and run structure | Claude Code OTel metrics and logs (section 2); `total_cost_usd` in each headless run's JSON result | exporter config cannot live in repo settings; figures are estimates |

Grafana already has three feeds with no glue: Flux annotations, Claude Code metrics through
Prometheus or OTLP, and Anthropic's monitoring guide for the collector. None of this is needed for
the landing page.

### 5. Sequencing, economics and failure modes (extracted; papers and DORA are primary)

- **Costs.** No published per-issue number exists; Anthropic's figures are per developer (section
  2). The per-run `total_cost_usd` in headless JSON and the OTel `cost.usage` metric are the way to
  get one for this repo, which is also the dashboard's first useful number.
- **Reward hacking, three studies.**
  [arXiv 2511.21654](https://arxiv.org/abs/2511.21654) (v2 2026-05-17): an LLM judge is "highly
  effective at detecting reward hacking in unambiguous cases, and only minimal improvement from the
  use of held out test cases"; Codex, Claude Code and Gemini CLI were all observed reward hacking
  when tests were readable and editable (hardcoded tests in 2.1% of Claude runs on the unambiguous
  subset); heuristic solutions still passed hidden holdouts; measured rates swing from 4.5% to 25.3%
  with the judge's strictness, so any "reward-hacked PRs" metric must define its criterion; holdouts
  are less exposed to prompt injection, so use them as a cheap first pass before judge calls.
  [arXiv 2605.21384](https://arxiv.org/abs/2605.21384) (v2 2026-09-09): measure reward hacking as
  the pass-rate gap between visible and held-out suites; every frontier agent saturates the visible
  suite while a gap persists; the gap "grows by 28 percentage points for every tenfold increase in
  code size"; the design pairs visible tests of features in isolation with held-out tests that
  compose them; one agent produced a 2,900-line hash table that memorised test inputs.
  [arXiv 2607.25152](https://arxiv.org/abs/2607.25152) (v2 2026-09-29, preregistered pilot, 54
  cycles): the agent claimed improvement every cycle while 56% had a measured delta of zero or
  below; a self-verdict gate degenerated to accept-all and eroded the deployed state by 19%; the
  strongest in-band judge accepted cycles of which 44% were regressions; on a task whose success is
  verifiable from the artifact the mirage dropped to zero; a sign-only gate performed like full
  feedback (110.0 against 113.0); the oracle was kept unfakeable by container and network isolation
  verified every run.
- **DORA 2025** (2025-09-24, about 5,000 respondents): AI adoption now correlates positively with
  throughput and product performance but still negatively with delivery stability; the cause named
  is missing control systems ("strong automated testing, mature version control practices, and fast
  feedback loops"); "invest in your internal platform" and "fortify your safety nets" are two of six
  recommended actions; 30% report little or no trust in AI-generated code.
- **What this means here.** Manifests and KRO templates are artifact-verifiable, so schema, policy
  and render checks can be judged in band and even by `/goal`. "The app is Ready in dev" lives
  outside the transcript and needs the cluster as oracle. Reviewer subagents (hl-plan-reviewer,
  `code-review`) are in-band judges: keep them, since the judge finding says they catch hacking, but
  they cannot replace the CI status and the Ready wait. Small tickets are a guardrail in their own
  right. The acceptance signal can be binary.
- **Sequencing answer.** The static harness comes before the first KRO app, because it needs no
  cluster and there are no manifests yet to break; the cluster e2e arrives with #4, #5 and #6; the
  agent loop binds to the gate once both are green on #6; the app pipeline comes with the first
  custom app; the dashboard, if adopted, is the second app through the KRO template, because it is
  stateless and proves the platform registers apps by itself; if built, it is the first custom app
  and arrives with the pipeline.

## Recommendations

### Implementation order for this repo

| Step | Build | Trigger | ADRs touched |
| --- | --- | --- | --- |
| 1 | `scripts/verify.sh` wrapping `validate.sh` (or a thin `kustomize build \| flux schema validate`), `.fluxschema.yml` with `schemaLocation: [default, ecosystem]`, `skipJSONPath: [Secret:/sops]`, `skipMissingSchemas: true`, the `flux migrate` diff check, the ADR 0012 and ADR 0004 policy script, a printed and enforced skipped-kind tally; `.github/workflows/verify.yaml` on `pull_request` with `contents: read` and actions pinned by digest | now; nothing depends on a cluster | new ADR "verification layers" (pinned flux-schema version, catalog locations, skip policy, offline catalog via the `ghcr.io/fluxcd/flux-schema` image or allowlisting `schemas.fluxoperator.dev` and `github.com` under ADR 0014); note under ADR 0012 |
| 2 | Ruleset: required `verify` check bound to the GitHub Actions app; CODEOWNERS on `.github/workflows/**`, `scripts/verify*`, `.fluxschema.yml`, `scenarios/**` with required code-owner review; test that the App cannot push workflow files or satisfy the check | the moment step 1 exists | amend ADR 0013 |
| 3 | Dev e2e: `scripts/dev-sync.sh` that pushes the artifact with `--revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)"`, reconciles with `--with-source`, waits for Ready on every Kustomization and HelmRelease, runs the ticket's `dev` checks; `flux schema extract crd` from dev for the KRO instance kinds, committed | #4 and #5 give a cluster, #6 gives the first app | extend ADR 0004 (persistent dev cluster, revision format); #6's "Done when" gains "Ready within 5m and smoke curl passes" |
| 4 | Bind the loop: a command-type Stop hook in `.claude/settings.json` that runs `verify.sh` and blocks with the output, with its own round limit like `flow-review-bound.sh`; a headless launcher for factory runs that never passes `--bare`, asserts hooks loaded, and passes `--permission-prompts none --max-budget-usd <N> --output-format json`; a cost ledger from the JSON results | steps 1 to 3 green on #6 | amend ADR 0014 and ADR 0016 (budget per issue, hook as the loop) |
| 5 | Holdout protection: `scenarios/` under CODEOWNERS and run only by CI; tickets kept small; `code-review` kept as the judge; a `TaskCompleted` hook running `verify.sh` for `implement-spec` tickets if the subagents mark tasks done | the first time an implementer edits a check to pass, or before the first unattended run, whichever is first | ADR 0016 ladder rung 2 |
| 6 | App pipeline for the first custom app: `docker/github-builder` with native arm64 runners, `actions/attest@v4` with SBOM, GHCR, digest pinning via ImagePolicy `digestReflectionPolicy: Always` or Renovate (decide), KRO request, optional ResourceSet preview per PR | the first custom-app issue is opened | ADR 0003 (KRO against ResourceSet), new ADR for image build and promotion |
| 7 | The dashboard: Homepage (or Dashy) through the KRO template, the template stamping `gethomepage.dev/*` annotations on the routes it generates, the ClusterRole owned by the platform and bound outside the per-app request | after Mealie runs in dev through the template, and after the ADR 0016 licence call | ADR 0003, ADR 0016 |
| 8 | Optional: flate or flux-local render-and-diff; claude-code-action | only if a PR diff comment proves necessary; only with its own ADR | adopt-or-build ADR (AGPL, `@main`); identity ADR |

### The first three issues to open

- **A. Static verify gate.** Goal: every PR renders and schema-checks the repository without a
  cluster. Done when: a deliberately broken FluxInstance and a broken RGD fail CI; the skipped-kind
  tally is printed and a skipped kind under `fluxcd.controlplane.io`, `kro.run` or
  `postgresql.cnpg.io` fails the run; the same script passes locally inside the sandbox. Out of
  scope: cluster checks, policy beyond ADR 0012 and ADR 0004. Depends on: nothing.
- **B. Ruleset binding and protected paths.** Goal: the `verify` status is the only path to a green
  check and the agent cannot change what it runs. Done when: a status set by the App does not satisfy
  the rule; a PR that edits `.github/workflows/` requires the operator's review; a push of a workflow
  file under the App token is rejected. Depends on: A.
- **C. Dev e2e loop.** Goal: one command syncs the working tree to the dev cluster and blocks on
  Ready. Done when: the script exits non-zero when a Kustomization fails health checks; the Mealie
  request kind validates in `verify.sh` from an extracted schema; the loop fits in #6's five-minute
  budget. Depends on: #4, #5, #6.

### Changes to hl-engineer and the harness docs (small)

- Keep the prior note's rule: every part's "Done when" is `<command> → <signal> (static | dev |
  operator)`. Add that `static` checks may be judged in band and `dev` checks only by the cluster.
- Stage 3 already slices vertically; cite the 28-point-per-tenfold finding as the reason to keep
  slices small, and let the Newcomer lens flag any part whose code volume looks large.
- harness.md "Loops" row: name the Stop hook as the factory's loop and `/goal` as the ad-hoc one;
  note the 8-continuation cap and the no-`--bare` rule.

### Conflicts with ADRs (flagged, not overridden)

- **flate** fails the checklist on licence (AGPL-3.0), maintainers and `@main` pinning. Not
  adopted; flux-local is the clean alternative if a diff layer is ever wanted.
- **Copyleft for deployed-only software.** Homepage (GPL-3.0) is the best-fitting landing page and
  fails "permissive licence" as the checklist is written. Deploying an unmodified image creates no
  copyleft obligation for this repo. Decide once, in ADR 0016, whether the criterion means
  "permissive" or "no obligation on us", because it decides Homepage against Dashy.
- **Schema hosts.** The default catalog is fetched from GitHub and the ecosystem catalog from
  `schemas.fluxoperator.dev`; both must join the ADR 0014 allowlist, or the verify script uses the
  `ghcr.io/fluxcd/flux-schema` image or a committed local catalog.
- **OpenTelemetry wiring cannot live in git.** Repository settings are ignored for the exporter;
  the configuration goes in the operator's user settings, an explicit exception to ADR 0014's
  "everything in git" that should be written down.
- **claude-code-action** adds a model credential and either the official App or a second custom
  App, and its bot-actor rule blocks the repo's App from triggering it. Needs an ADR before any use.
- **ResourceSet against KRO.** The Flux Operator offers an overlapping app-definition mechanism
  with local rendering and CEL dependencies. ADR 0003's prototype should record the comparison.
- **The dark factory** remains out: every gate above keeps the operator's merge (ADR 0013).

## Open questions

- Flux image automation or Renovate for digest pinning of agent-built images? Renovate was not
  fetched; image automation needs the controllers installed in dev and prod.
- Monorepo or a separate app repository for the dashboard? Only hints exist (section 3).
- Where do holdout scenarios live so neither the App nor the implementer can edit them: a
  CODEOWNERS-guarded directory in this repo, or a second repository the App is not installed on?
- How to keep extracted KRO instance schemas fresh when an RGD changes: re-extract in the dev e2e
  step and fail if the committed schema differs?
- Does the headless launcher need a flag to keep hooks on once `--bare` becomes the `-p` default?
  Check the CLI reference when that release lands.
- Which spend per issue does the operator accept for `--max-budget-usd`? No published per-issue
  figure exists; the first few runs' `total_cost_usd` will set it.
- Does the checklist's "permissive licence" apply to software that is only deployed? It decides
  Homepage (GPL-3.0) against Dashy (MIT) for the landing page.
- How does Homepage's cluster-wide read ClusterRole coexist with #6's least-privilege fence: a
  platform-owned role bound to the dashboard's ServiceAccount, outside the per-app request?

## Not verified

- Everything in sections 3, 4b and 5 except the three papers and the DORA post, which are primary
  and quoted, was extracted from primary pages but never put to the adversarial vote. Section 4 was
  checked directly against the GitHub API, the registries and the project docs on 2026-10-25, also
  without a vote.
- For the four dashboard candidates: no security audit was checked; "distinct commit authors over
  365 days" is a proxy for maintainers, not a maintainer list; Homarr keeping its state in the
  database is inferred from the chart (no configuration file is mounted), not quoted; Homepage's
  ClusterRole rules were located in `docs/installation/k8s.md` but not read rule by rule; Glance's
  image architectures come from the Docker Hub manifest list, not from its docs.
- Two refutations by the workflow's verifiers were overturned by direct reads and are **confirmed**:
  the content and behaviour of `gitops-repo-audit/scripts/validate.sh` (GitHub API, commit
  `bb68a58`), and the `--bare` semantics (headless page, fetched 2026-10-25). The two remaining
  refutations stand: `flux schema validate` does not build directories itself the way
  kustomize-controller does, and the "purely local, successor to kubeconform" framing was overstated
  (it "extends" kubeconform and fetches schemas unless an offline catalog is supplied).
- That a GitHub App without the `workflows` permission cannot push changes to `.github/workflows/`
  is the verifier's note on the ruleset claim, not a quoted doc. Confirm by test in issue B.
- That `--skip-missing-schemas` and `-ignore-missing-schemas` are equally silent is inferred from
  the flags' descriptions; the enforced tally in `verify.sh` makes it moot.
- flate's "seconds not minutes" speed and flux-local-dev's "under five minutes" are self-reported.
- The reference e2e's version numbers (kind v0.32.0, node v1.36.1) move because the actions are
  pinned `@main`.
- The Headlamp plugin API, the Flux Web UI, Capacitor, Homepage, Glance, Homarr and Renovate were
  not fetched.
- Claude Code behaviour is version-gated (v2.1.217, v2.1.246, v2.1.259, v2.1.286, v2.1.302) and
  the docs are living pages; re-check before relying on a flag.

## Sources

- Validation harness (angle 1):
  - [Introducing Flux Schema](https://fluxcd.io/blog/2026/07/flux-schema-validation/), 2026-07-13;
    [Manifests validation](https://fluxcd.io/flux/cli-plugins/flux-schema/manifests-validation/);
    [catalog README v0.17.0](https://github.com/fluxcd/flux-schema/blob/v0.17.0/catalog/README.md);
    [ecosystem index](https://schemas.fluxoperator.dev/index.json) and the
    [KRO RGD schema](https://schemas.fluxoperator.dev/catalog/kro.run/resourcegraphdefinition_v1alpha1.json)
  - [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)
    (`test.yaml`, `e2e.yaml`, PR #130, 2026-07-08)
  - [stefanprodan/flux-local-dev](https://github.com/stefanprodan/flux-local-dev) (Makefile,
    `scripts/flux/push.sh`, `scripts/test/validate.sh`; last pushed 2023-12-30);
    [flux push artifact](https://fluxcd.io/flux/cmd/flux_push_artifact/)
  - [home-operations/flate](https://github.com/home-operations/flate) (README, `action/action.yml`,
    `.pre-commit-hooks.yaml`; v0.6.5)
  - [fluxcd/agent-skills gitops-repo-audit validate.sh](https://github.com/fluxcd/agent-skills/blob/main/skills/gitops-repo-audit/scripts/validate.sh)
    (read through the GitHub API, commit `bb68a58`, 2026-10-25)
  - [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- Unattended runs and gates (angle 2):
  - Claude Code docs, fetched 2026-10-25: [headless](https://code.claude.com/docs/en/headless),
    [hooks](https://code.claude.com/docs/en/hooks), [goal](https://code.claude.com/docs/en/goal),
    [GitHub Actions](https://code.claude.com/docs/en/github-actions),
    [monitoring usage](https://code.claude.com/docs/en/monitoring-usage),
    [costs](https://code.claude.com/docs/en/costs),
    [CLI reference](https://code.claude.com/docs/en/cli-reference),
    [permission modes](https://code.claude.com/docs/en/permission-modes),
    [environment variables](https://code.claude.com/docs/en/env-vars)
  - [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action):
    `docs/setup.md` (2026-05-21), `docs/security.md`, `src/modes/detector.ts`,
    `src/github/validation/actor.ts`, `src/github/validation/trigger.ts`
  - GitHub Docs: [available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets),
    [REST rules](https://docs.github.com/en/rest/repos/rules)
  - [anthropics/claude-code-monitoring-guide](https://github.com/anthropics/claude-code-monitoring-guide)
- Shipping apps (angle 3):
  - [Docker: multi-platform images in GitHub Actions](https://docs.docker.com/build/ci/github-actions/multi-platform/), modified 2026-05-18
  - [GitHub: artifact attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds)
  - [Flux image reflector API v1](https://fluxcd.io/flux/components/image/reflector-api/v1/)
  - Flux Operator: [ResourceSet app definition](https://fluxoperator.dev/docs/resourcesets/app-definition/),
    [ephemeral environments for GitHub pull requests](https://fluxoperator.dev/docs/resourcesets/github-pull-requests/)
  - [kro.run examples](https://kro.run/examples), docs version 0.9.4
- The dashboard (direct pass, 2026-10-25):
  - GitHub API: `gethomepage/homepage`, `Lissy93/dashy`, `glanceapp/glance`, `homarr-labs/homarr`,
    `homarr-labs/charts` (licence, pushes, releases, commits since 2025-10-25)
  - Manifest lists: `ghcr.io/gethomepage/homepage:latest`, `ghcr.io/lissy93/dashy:latest`,
    `ghcr.io/homarr-labs/homarr:latest`, `docker.io/glanceapp/glance:latest`
  - Homepage: [Kubernetes configuration](https://gethomepage.dev/configs/kubernetes/),
    [`docs/installation/k8s.md`](https://github.com/gethomepage/homepage/blob/dev/docs/installation/k8s.md)
  - Dashy: [`docs/deployment.md`](https://github.com/Lissy93/dashy/blob/master/docs/deployment.md),
    [`docs/configuring.md`](https://github.com/Lissy93/dashy/blob/master/docs/configuring.md)
  - Glance: [README](https://github.com/glanceapp/glance/blob/main/README.md),
    [`docs/configuration.md`](https://github.com/glanceapp/glance/blob/main/docs/configuration.md)
  - Homarr: [installation](https://homarr.dev/docs/getting-started/installation),
    [chart README](https://github.com/homarr-labs/charts/blob/main/charts/homarr/README.md)
- Factory observability (section 4b):
  - GitHub Docs: [webhook events and payloads](https://docs.github.com/en/webhooks/webhook-events-and-payloads),
    [REST issue dependencies](https://docs.github.com/en/rest/issues/issue-dependencies)
  - [Flux notification providers](https://fluxcd.io/flux/components/notification/providers/)
  - Claude Code [monitoring usage](https://code.claude.com/docs/en/monitoring-usage) (as above)
- Sequencing, economics, failure modes (angle 5):
  - [arXiv 2511.21654](https://arxiv.org/abs/2511.21654), reward hacking by production coding
    agents, v2 2026-05-17
  - [arXiv 2605.21384](https://arxiv.org/abs/2605.21384), SpecBench, visible against held-out
    suites, v2 2026-09-09
  - [arXiv 2607.25152](https://arxiv.org/abs/2607.25152), the progress mirage and out-of-band
    oracles, v2 2026-09-29
  - [2025 DORA report announcement](https://cloud.google.com/blog/products/ai-machine-learning/announcing-the-2025-dora-report), 2025-09-24
- Local: ADRs 0003, 0004, 0010, 0012, 0013, 0014, 0016; `docs/agents/harness.md`;
  [agentic-software-factory.md](agentic-software-factory.md); issues #2, #4, #5, #6; skills-lock.json.
- Method: the `/deep-research` workflow run `wf_8a3e05ef-7fc`, 106 agents, journal and per-agent
  transcripts in the session's workflow directory; fetch and search on the session model, the
  25-claim verification panel on Opus 5.5.
