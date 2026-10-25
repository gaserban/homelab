# Monorepo layout: apps, packages, Flux manifests, OpenTofu, tooling

Checked 2026-10-25. Sources are the Flux docs and example repos, the Flux Operator docs, the
`gitops-knowledge` skill's references, the Nx, Turborepo, moon, Pants and Bazel docs, the GitHub
docs for CODEOWNERS and workflow path filters, the Docker build docs, the Claude Code docs, and the
live trees of three public homelab repos. Every fetch was made on 2026-10-25; page dates are given
where the page shows one.

Question, from the operator: what is the established top-level layout for a polyglot monorepo that
also holds Flux manifests and OpenTofu? Where do apps, shared packages, cluster manifests, IaC and
repo tooling go, and what are the known failure modes? Context: solo operator, public repo.
[ADR 0004](../adr/0004-environments-and-dev-loop.md) (dev syncs from a folder pushed as an OCI
artifact, prod from GitHub), [ADR 0007](../adr/0007-external-resources-and-interfaces.md) (OpenTofu
for Cloudflare and B2), [ADR 0012](../adr/0012-deletion-safety.md), multi-arch images. Today the repo
has `.claude/`, `docs/` and `tools/`, and no cluster manifests.

This note recommends a tree. It does not change an ADR. Where a statement is my inference rather
than a source's, it says so.

## Short answer

- **No source defines one layout for this mix.** Each camp covers one slice. Flux's guides cover
  manifests, the monorepo tools cover app source, and OpenTofu covers modules. Public homelab repos
  cover manifests and IaC but I found none that also holds app source. So the combined tree below is
  a synthesis, and the seams between the slices are where the failure modes sit.
- **Two names collide: `apps/`.** Flux's examples use `apps/` for deployment manifests; Turborepo,
  Nx and moon use `apps/` for app source. Fix it by parent folder: all Flux packages go under one
  `kubernetes/` folder (what onedr0p/home-ops and ajgon/home-ops do), and app source gets the
  top-level `apps/`.
- **`kubernetes/` is the only folder Flux ever packages.** In dev, push a staged copy of it, not the
  repo root. In prod, a `.sourceignore` allowlist keeps the rest out of the GitRepository artifact.
  That is how the Flux folder stays free of app source (and of `.state/`, which holds cluster-admin
  credentials).
- **Keep the in-artifact paths identical in dev and prod.** A Flux `Kustomization.spec.path` is
  relative to the source artifact root. If dev's root is `kubernetes/` and prod's is the repo root,
  every path differs. Stage the dev artifact so its root also contains `kubernetes/`.
- **Top failure modes:** renaming a folder that a directory-driven pipeline derives names from (it
  deletes and recreates the deployment), path filters that leave a required check pending,
  CODEOWNERS and `.sourceignore` patterns that go stale after a move, cross-imports between apps,
  and nesting deeper than the tools support.

## Recommended tree

Folders marked (now) exist today. The rest are created by the first change that needs them; git
does not track empty folders, so there is no placeholder.

```text
homelab/
├── .claude/        (now)  Claude Code: settings.json, hooks/, hl-* skills, agents/
├── .github/        (now)  ISSUE_TEMPLATE/, workflows/, CODEOWNERS
├── apps/                  source of things this repo builds: one folder per deployable
│   └── <app>/             own manifest (go.mod, package.json, ...), Containerfile, tests
├── packages/              libraries shared by two or more apps, per language
│   └── <lib>/
├── kubernetes/            everything Flux applies; YAML only; the only packaged folder
│   ├── clusters/<cluster>/    FluxInstance, flux-vars, root Kustomizations (dev, prod)
│   ├── infra/                 controllers and their configs, ordered by dependsOn
│   └── apps/<app>/{base,envs/<env>}   deployment manifests for apps/<app>
├── opentofu/              external resources (ADR 0007)
│   ├── modules/<purpose>/     one module per external purpose (edge, storage, ...)
│   └── envs/<env>/            root modules: backend block, provider config, module calls
├── tools/          (now)  self-contained helpers for the workstation and agent; may carry a Containerfile
├── scripts/               thin entry points that CI and hooks call (verify.sh, dev-sync.sh)
├── docs/           (now)  adr/, agents/, research/, operator-setup.md
├── GLOSSARY.md, CLAUDE.md, README.md, skills-lock.json, .sourceignore, .gitignore
```

One line per top-level folder:

| Folder | What belongs there | What does not |
| --- | --- | --- |
| `.claude/` | Settings, hooks, own `hl-` skills, subagent definitions. One root copy. | Downloaded skills (restored per ADR 0017), anything Flux applies. |
| `.github/` | Workflows, issue template, CODEOWNERS. | Logic. Workflows call `scripts/`. |
| `apps/` | One folder per thing built into an image or binary: source, tests, `Containerfile`. | Kubernetes YAML. |
| `packages/` | Code imported by two or more apps. Promoted here when the second user appears. | Anything with one user; anything deployable. |
| `kubernetes/` | Flux and Kustomize YAML only. | Source, scripts, Terraform, docs, credentials. |
| `opentofu/` | OpenTofu modules and per-environment roots, plus the committed `.terraform.lock.hcl`. | State, `*.tfvars`, `.terraform/`. |
| `tools/` | Programs and runtime support the operator or agent runs locally, each self-contained (today: `gh`, `gh-app-token`, `hl-runtime`, `sandbox-tunnel/`, `kind-dev.yaml`). | Code that ships to a cluster. |
| `scripts/` | Short entry points that CI, hooks and the dev loop call. | Programs with their own config or container. |
| `docs/` | ADRs, research, agent docs, operator setup. | Anything Flux applies. |

### How the tree keeps `kubernetes/` free of app source

1. **Source and manifests live in different folders.** The deploy manifests for `apps/foo` are
   `kubernetes/apps/foo/`. The Flux repository-structure guide treats "app source code and
   deployment manifests share a repository" as its own pattern (repo per app), where the config
   repo points at the app repo's manifests. It does not put source inside the folder that Flux
   syncs. ([Flux, Ways of structuring your repositories](https://fluxcd.io/flux/guides/repository-structure/),
   page last modified 2024-05-13.)
2. **The packaged unit is one folder.** The `gitops-knowledge` skill's directory-driven monorepo
   pushes the whole `kubernetes/` tree as one artifact, `flux push artifact oci://<registry>/flux-cluster:<cluster> --path ./kubernetes`,
   with the cluster entry at `clusters/<cluster>/`
   (skill: `references/monorepo-delivery.md`, "Validation and Publishing"; `references/repo-patterns.md`,
   "Directory-Driven Monorepo"). `flux push artifact` "creates a tarball from the given directory"
   ([flux push artifact](https://fluxcd.io/flux/cmd/flux_push_artifact/)).
3. **Prod reads from Git, so an allowlist is needed there.** A GitRepository artifact is the whole
   checkout minus default exclusions (`.git/`, images and archives, CI configs such as `.github/`,
   `.sops.yaml`). `.claude/`, `docs/`, `apps/` and `tools/` are not in that default list
   ([GitRepository, ignore](https://fluxcd.io/flux/components/source/gitrepositories/)). The Flux
   example repo handles this with a root `.sourceignore` that excludes everything with `/*` and
   re-includes only its manifest folders (`/apps/`, `/clusters/`, `/infrastructure/`)
   ([flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)). Here the
   file would re-include only `/kubernetes/`. `.sourceignore` is read recursively and `spec.ignore`
   overrides it ([GitRepository](https://fluxcd.io/flux/components/source/gitrepositories/)).
   The FluxInstance `spec.sync` field index has no ignore field, so `.sourceignore` in the repo
   is the lever (field index: `gitops-knowledge` `assets/schemas/fluxinstance-fluxcd-v1.fields.txt`).
4. **Per-app artifacts.** If the repo grows, an `ArtifactGenerator` with `pathPattern` splits the
   source artifact so a change to one app's folder reconciles only that app
   ([flux2-kustomize-helm-example README](https://github.com/fluxcd/flux2-kustomize-helm-example):
   "Changes outside the `apps/` directories do not trigger an apps reconciliation"; skill:
   `references/monorepo-delivery.md`). This limits reconciliation, not what is in the artifact, so it
   is not a substitute for the allowlist.

### Dev and prod must share one artifact root

`Kustomization.spec.path` is "the path to the directory in the Source Artifact", defaulting to the
artifact root ([Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)). The
skill's dev recipe pushes `--path ./kubernetes`, so the artifact root is `kubernetes/` and paths read
`clusters/dev`, `./infra/...`. A GitRepository's root is the repo root, so the same paths would read
`kubernetes/clusters/prod`, `./kubernetes/infra/...`. ADR 0004's "one recipe, only the source differs"
breaks the first time a child Kustomization carries a path.

Inference, not documented by any source: make both roots the same by pushing a staged copy.

```sh
stage=$(mktemp -d); mkdir "$stage/kubernetes"; cp -a kubernetes/. "$stage/kubernetes/"
flux push artifact oci://<registry>/flux-cluster:dev --path "$stage" --source ... --revision ...
```

Then dev's FluxInstance uses `sync.path: kubernetes/clusters/dev`, prod's uses
`kubernetes/clusters/prod`, and every child path is identical in both. The same step is why dev must
not push `--path .`: `flux push artifact` has a default ignore list of Git metadata and common media
extensions, it does not document reading `.gitignore` or `.sourceignore`, and `.state/` (kind
kubeconfig with cluster-admin) and `.env` files are not in it
([flux push artifact](https://fluxcd.io/flux/cmd/flux_push_artifact/)). A staged copy of
`kubernetes/` cannot contain them. Whether `--ignore-paths` accepts the same negation patterns as
`.sourceignore` is not shown on that page; test before relying on it.

### Where `.claude/`, `docs/adr/` and image build contexts sit

- **`.claude/`**: root only. Claude Code reads project `CLAUDE.md` from `./CLAUDE.md` or
  `./.claude/CLAUDE.md`, loads subdirectory `CLAUDE.md` files on demand, and does not inherit
  `.claude/settings.json` from parent directories ([memory](https://code.claude.com/docs/en/memory),
  [large codebases](https://code.claude.com/docs/en/large-codebases)). For a solo repo one root
  `.claude/` is enough. Add `apps/<app>/CLAUDE.md` only when an app has its own stack and
  conventions; the docs suggest targeting under 200 lines per file and moving area-specific rules to
  per-directory files or path-scoped `.claude/rules/`. A per-folder `.claude/settings.json` must be
  self-contained, so avoid them.
- **`docs/adr/`**: stays at `docs/adr/`. Docs are not packaged, so they never reach a cluster. Nx
  suggests each grouping folder map to a CODEOWNERS entry ([Nx, folder structure](https://nx.dev/docs/kb/folder-structure)),
  which is how ADRs would be guarded if that is wanted.
- **Image build contexts**: the `Containerfile` sits in `apps/<app>/`, and the context is that
  folder. This repo already does the same for tooling: `tools/sandbox-tunnel/Containerfile`. A
  build context is "the set of files that your build can access", `COPY` reads only from it, and
  `.dockerignore` at the context root strips files before they reach the builder
  ([Docker, build context](https://docs.docker.com/build/concepts/context/)). If an app imports
  `packages/<lib>`, the context must widen to the repo root, with a per-Dockerfile ignore file
  (`<name>.dockerignore` beside the Dockerfile takes precedence over the root `.dockerignore`, same
  page) and an allowlist ignore so the context does not carry `.state/` or `docs/`. Docker names that
  file after the Dockerfile; I did not check how Podman names it for a file called `Containerfile`.
- **Multi-arch**: a multi-platform image is a manifest list pointing at per-platform manifests.
  Docker lists QEMU emulation, native builder nodes and cross-compilation (`BUILDPLATFORM` and
  `TARGETPLATFORM` in a multi-stage build) as the three ways to build one
  ([Docker, multi-platform](https://docs.docker.com/build/building/multi-platform/)). This does not
  affect folder layout, but it decides whether `apps/<app>/Containerfile` needs platform args.

## What the conventions say

### Flux

- Four documented shapes: monorepo, repo per environment, repo per team, repo per app. For a
  monorepo, "the separation between apps and infrastructure makes it possible to define the order in
  which a cluster is reconciled", environments are cluster directories that reference overlays, and
  base plus `production`/`staging` overlays is the recommended Kustomize shape. The page warns that
  anyone who can read a monorepo can read production config
  ([Flux guide](https://fluxcd.io/flux/guides/repository-structure/)). That warning matters for a
  public repo: nothing secret goes in any folder (CLAUDE.md already says so).
- `fluxcd/flux2-kustomize-helm-example` (read 2026-10-25) is `apps/{base,production,staging}`,
  `clusters/{production,staging}`, `infrastructure/{controllers,configs}`, `scripts/`,
  `.sourceignore`, `.fluxschema.yml`. Ordering is `infra-controllers`, then `infra-configs`
  (`dependsOn`, so CRDs exist first), then `apps`
  ([repo](https://github.com/fluxcd/flux2-kustomize-helm-example)).
- `fluxcd/flux2-multi-tenancy` (read 2026-10-25) is `clusters/`, `policies/`, `tenants/`, each with
  `base` and per-environment overlays, plus `.sourceignore` and `.fluxschema.yml`. Policies must
  reconcile before tenants ([repo](https://github.com/fluxcd/flux2-multi-tenancy)).
- Both example repos hold manifests only. Neither holds app source or IaC.
- The `gitops-knowledge` skill's directory-driven layout, which fits ADR 0004, is
  `kubernetes/{clusters/<cluster>, infra/{reconcilers,core,components/<name>/{controllers,configs}}, apps/{reconcilers,<app>/{base,envs/<app_env>}}}`
  (skill: `references/repo-patterns.md`). Use it as the inside of `kubernetes/`; it needs Flux 2.9 or
  later with `source-watcher` (skill: `references/monorepo-delivery.md`, "Prerequisites").
- Flux Operator's OCI sync is `FluxInstance.spec.sync` with `kind: OCIRepository`, `url`, `ref`,
  `path`, `pullSecret` ([Flux Operator, cluster sync](https://fluxoperator.dev/docs/instance/sync/)).
  An `OCIRepository` has `spec.insecure` for plain-HTTP registries (the local dev registry) and
  `spec.ignore`; `ref` defaults to `latest` ([OCIRepository](https://fluxcd.io/flux/components/source/ocirepositories/)).
  The Flux Operator sync page says nothing about local or insecure registries or about ignore paths.

### Monorepo tools (apps, packages, tools)

| Tool | Convention | Source |
| --- | --- | --- |
| Turborepo | `apps/` for applications and services, `packages/` for everything else; globs `apps/*` and `packages/*`; nested `apps/**` is unsupported (a package inside another errors); group with `packages/group/*` and no `package.json` in `group`. Avoid reaching across package boundaries. | [Structuring a repository](https://turborepo.dev/docs/crafting-your-repository/structuring-a-repository) |
| Nx | No required layout. Flat `packages/`, or grouped `apps/` plus `libs/`. Keep apps thin (target: most code in `libs/`), group libraries by domain not by type, promote to `shared` when a second domain needs it. Local plugins and generators sit in `tools/`. Nx identifies projects by `package.json` or `project.json`, not by folder. | [Monorepo folder structure](https://nx.dev/docs/kb/folder-structure); [search summary for `tools/`](https://nx.dev/docs/extending-nx/creating-files) |
| moon | `projects` is a list of globs such as `apps/*` and `packages/*`, or an explicit map. Globbing "does risk the chance of collision" because project ids come from folder names; cycles "must be avoided". | [workspace config](https://moonrepo.dev/docs/config/workspace) |
| Pants | Source roots tell Pants where imports start. `src/<lang>` is common in polyglot repos; third-party requirements go in `3rdparty/`. A flat root "often does not scale ... such as adding new languages". Build helpers live in `build-support/` in the Pants repo itself. | [source roots](https://www.pantsbuild.org/stable/docs/using-pants/key-concepts/source-roots); [pantsbuild/pants](https://github.com/pantsbuild/pants/tree/main/build-support) |
| Bazel | One package, target and `BUILD` file per directory; minimise visibility; a single version of each third-party dependency (the one-version rule). | [Dependencies](https://bazel.build/basics/dependencies) |

What carries over: `apps/` for deployables and `packages/` for shared code is the common core
(Turborepo, Nx, moon all accept it). Polyglot repos either keep per-language roots (Pants
`src/<lang>`) or put the language inside the project folder. With the app count this repo will have,
the second is simpler: `apps/<app>/` holds whatever language the app uses, and the language
toolchain's workspace file lives in the app (and at the root only if one toolchain spans apps).

### `tools/` versus `scripts/`

No source defines the split, so this is a judgement from the evidence:

- Nx puts local plugins and generators, which are programs that extend the build tool, in `tools/`.
- The Flux example repo has `scripts/` next to its manifests for CI glue
  ([repo](https://github.com/fluxcd/flux2-kustomize-helm-example)). ajgon/home-ops and
  khuedoan/homelab also have `scripts/`; onedr0p/home-ops has neither (it uses a `.justfile`).
- Pants uses `build-support/` for repo-internal build helpers.

Recommendation, consistent with what is already here and with the planned CI checks in
[agentic-software-factory-implementation.md](agentic-software-factory-implementation.md)
(`scripts/verify.sh`, `scripts/dev-sync.sh`, CODEOWNERS on `scripts/verify*`):

- **`tools/`** holds things that are programs or runtimes: they have their own config, may carry a
  `Containerfile`, and are run by the operator or the agent on the workstation (`hl-runtime`,
  `sandbox-tunnel/`, `kind-dev.yaml`, the `gh` wrappers). Each is self-contained so it can move
  without breaking a neighbour. Reason: these change on their own schedule and are reviewed as code.
- **`scripts/`** holds short entry points that a workflow, hook or Makefile-style command calls so the
  command line lives in one reviewed place, not inside YAML. Reason: CI logic belongs in a file you
  can run locally, and a small, named folder is easy to put under CODEOWNERS.
- **Rule of thumb**: if it needs its own folder, config or container, it is a tool. If it is one
  file a pipeline calls, it is a script. If there is only one or two such files, keep them in
  `tools/` and add `scripts/` when the CI entry points arrive. Two homes for scripts is itself a
  failure mode (see below).

### OpenTofu

- Standard module structure: the root module is the only required piece; `main.tf`, `variables.tf`,
  `outputs.tf` recommended; `modules/` for nested modules; `examples/` at the root. Nested modules
  should be composable by the caller, not call each other, to avoid a deep tree
  ([OpenTofu, module structure](https://opentofu.org/docs/language/modules/develop/structure/)).
  `opentofu/modules/<purpose>/` plus `opentofu/envs/<env>/` follows this and ADR 0007's "one
  implementation folder per purpose".
- Commit `.terraform.lock.hcl` ("You should include this file in your version control repository",
  [dependency lock](https://opentofu.org/docs/language/files/dependency-lock/)). Ignore `.terraform/`,
  `*.tfstate*`, `*.tfvars` and override files
  ([github/gitignore Terraform.gitignore](https://github.com/github/gitignore/blob/main/Terraform.gitignore)).
  State is in HCP Terraform per ADR 0007, so no state file should ever appear in the tree.
- Coupling to the cluster goes through the vault, not files: ADR 0007 writes OpenTofu outputs to the
  vault and External Secrets delivers them. So nothing in `kubernetes/` references a path in
  `opentofu/`, and the Flux artifact never needs it.

## Public homelab repos, checked 2026-10-25

| Repo | Top level (as listed on GitHub) | Newest commit | Holds app source or IaC? |
| --- | --- | --- | --- |
| [onedr0p/home-ops](https://github.com/onedr0p/home-ops) (Flux) | `.agents/skills`, `.github`, `.mise`, `.vscode`, `bootstrap`, `kubernetes`, `talos`, plus dotfiles (`.justfile`, `.lefthook.toml`, `.renovaterc.json5`). `kubernetes/` is `apps`, `components`, `mod.just`; `kubernetes/apps/` is one folder per namespace including `flux-system`. `.github/` has `workflows`, `CODEOWNERS` (one owner), `labels.yaml`. | 2026-10-25 (commits atom) | No app source. No Terraform folder visible. README documents only `kubernetes/{apps,components}`. |
| [ajgon/home-ops](https://github.com/ajgon/home-ops) (Flux, OpenTofu) | `.agents/`, `.forgejo/`, `.renovate/`, `ansible/`, `bootstrap/`, `docker/`, `kubernetes/`, `opentofu/`, `scripts/`, `talos/`, `devenv.nix`, `.justfile`. `kubernetes/` is `apps` (base templates shared across clusters), `clusters`, `components`. README: Flux watches `kubernetes/clusters/<cluster>` and applies the topmost `kustomization.yaml` in each directory found. `opentofu/` is plans for external services such as Cloudflare. | 2026-10-25 (commits page) | OpenTofu yes. `docker/` is Compose files for machines Kubernetes does not manage, not app source. |
| [khuedoan/homelab](https://github.com/khuedoan/homelab) (ArgoCD, not Flux) | `.woodpecker/`, `apps/`, `docs/`, `external/`, `metal/`, `platform/`, `scripts/`, `system/`, `test/`, `Dockerfile`, `Makefile`, `flake.nix`. `external/` has `main.tf`, `variables.tf`, `versions.tf`, `modules/`. | 2026-06-06 (commits atom) | Terraform yes (`external/`). `apps/` lists 12 well-known self-hosted apps; I did not open them, so whether they are source or definitions is not verified. |

What this shows:

- The Flux homelab repos put all Flux YAML under one `kubernetes/` folder, split into `apps`,
  `components`, and in ajgon's case `clusters`. That supports the `kubernetes/` boundary.
- Both repos with IaC give it its own top-level folder named for the tool or purpose (`opentofu/`,
  `external/`). Neither nests it under the cluster folder.
- None of the three holds first-party app source. "A homelab that also builds its own apps in the
  same repo" has no well-known public example that I found; the layout for that part rests on the
  monorepo tools' conventions, not on homelab precedent.
- Only onedr0p/home-ops has a CODEOWNERS file I could see (single owner, so it is a notification
  list, not a control). I could not see its workflow path filters; the page listing did not show
  workflow contents.
- onedr0p's repo has no `tools/` or `scripts/`; it uses a task runner file and a `mise` folder
  instead. That is a third option: no folder, a `.justfile`.

## CODEOWNERS and path filters

### CODEOWNERS ([GitHub docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners))

- The file lives in `.github/`, the root or `docs/`; the first found in that order wins, and the
  base branch's copy is the one used for a PR.
- The last matching pattern wins. Patterns follow gitignore rules except no `!` negation, no `[ ]`
  ranges and no escaped leading `#`. Paths are case sensitive. Lines with invalid syntax are skipped.
  The file must be under 3 MB.
- The docs do not say what happens when a path moves. The base branch's file is matched against the
  new path, so a pattern that names the old folder silently stops protecting it. That is my reading
  of those two statements, not a documented behaviour.
- What the tree buys: one folder per concern means one CODEOWNERS line per concern. The folders worth
  guarding for a solo operator whose agent opens the PRs (ADR 0013) are `.github/workflows/`,
  `.claude/hooks/` and `.claude/settings.json`, `scripts/`, `tools/`, `kubernetes/clusters/prod/`,
  `opentofu/`, `.sourceignore`, `.fluxschema.yml` and `docs/adr/`. Deeper nesting would need more
  lines and more to keep in step. Nx describes the same one-grouping-folder-one-entry mapping
  ([Nx](https://nx.dev/docs/kb/folder-structure)).

### Workflow path filters ([GitHub docs](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions))

- `paths` and `paths-ignore` cannot both be used for one event in one workflow; use `!` patterns
  inside `paths` instead, and order matters. Filters are not evaluated for tag pushes. Patterns are
  repo-root-relative globs.
- **Skipped workflow, required check pending.** "If a workflow is skipped due to path filtering ...
  checks associated with that workflow will remain in a 'Pending' state", and a PR that requires them
  is blocked. In this tree that bites when a required `verify` workflow is filtered to `kubernetes/**`:
  a docs-only PR can never merge. Fix (inference): keep the required check on an unfiltered
  workflow that detects changes inside the job, or on a final gate job.
- Diff limits: pushes of more than 1,000 commits always run the workflow; if the diff has more than
  3,000 files and matches fall outside the first 3,000, the workflow does not run. Not a concern at
  this size.
- Filter globs are paths, so they are the third place (with CODEOWNERS and `.sourceignore`) that
  names the folders. Keep a short list, one folder per concern, so a move is a three-line change.

## Failure modes others hit

Each is tied to a source. Items marked inference are mine.

1. **Deep nesting.** Turborepo rejects nested packages (`apps/**`, a package inside a package) and
   offers `packages/group/*` for one level of grouping ([Turborepo](https://turborepo.dev/docs/crafting-your-repository/structuring-a-repository)).
   moon's folder-name project ids collide; conflicting projects are skipped with a warning and the
   fix is a longer id ([moon](https://moonrepo.dev/docs/config/workspace)). Nx gives no depth rule
   but says a flat folder stops showing structure past a few dozen projects
   ([Nx](https://nx.dev/docs/kb/folder-structure)). OpenTofu advises composition over deep module
   trees ([OpenTofu](https://opentofu.org/docs/language/modules/develop/structure/)). Flux shapes
   already reach three levels (`apps/<app>/envs/<env>`). Limit here: top-level folder, then a
   project folder, then at most base/envs inside it (inference).
2. **Cross-imports.** Nx tags projects and enforces `depConstraints`; untagged projects may depend on
   nothing unless a rule allows it ([Nx boundaries](https://nx.dev/docs/features/enforce-module-boundaries)).
   Turborepo says to avoid reaching across package boundaries and instead install the dependency
   ([Turborepo](https://turborepo.dev/docs/crafting-your-repository/structuring-a-repository)).
   Bazel minimises visibility and enforces one version per third-party dependency
   ([Bazel](https://bazel.build/basics/dependencies)); moon warns that dependency cycles are not
   ordered ([moon](https://moonrepo.dev/docs/config/workspace)); Pants suggests `pants dependents`
   in CI to limit cross-project imports ([Pants](https://www.pantsbuild.org/stable/docs/using-pants/key-concepts/source-roots)).
   Rules for this repo (inference): apps import only from `packages/`, never from another app;
   `packages/` imports nothing from `apps/`; `kubernetes/` and `opentofu/` import nothing from either.
   Without a tool-enforced boundary, a path-based CI grep is the only check.
3. **Flux path drift when folders move.**
   - A `Kustomization.spec.path` and a `FluxInstance.spec.sync.path` are literal paths from the
     artifact root ([Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/);
     the field index says "Path is the path to the source directory"). Moving a folder without
     updating them fails the Kustomization, and changing the artifact root (dev versus prod above)
     changes every path at once.
   - A directory-driven pipeline derives object names from folder names, and "adding a directory
     deploys it, removing it tears the deployment down" (skill: `references/monorepo-delivery.md`).
     So renaming `kubernetes/apps/foo` to `kubernetes/apps/bar` is a remove plus an add. Flux
     garbage-collects a Kustomization's objects when it is deleted, and prunes objects that leave the
     source ([Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/); ADR 0012).
     ADR 0012's `deletionPolicy: Orphan` and the `kustomize.toolkit.fluxcd.io/prune: disabled`
     annotation are the safety net, so move stateful folders only after both are in place, and
     suspend first (ADR 0012).
   - If the `.sourceignore` allowlist stops matching the moved folder, the artifact loses it. The
     same applies to the dev staging step.
   - Kustomize's own file loader refuses `resources:` outside the kustomization root with "is not in or
     below". Secondary sources (GitHub issues and PRs, not Flux docs; I did not find it in the
     official Flux or Kustomize pages) report that kustomize-controller does not apply that
     restriction the same way, so a path that Flux accepts can fail `kustomize build` locally. Keep
     every `resources:` entry inside the same folder tree and validate with the same renderer CI uses
     (skill: `references/monorepo-delivery.md` builds with `--load-restrictor=LoadRestrictionsNone`).
4. **A second home for scripts.** Two folders with overlapping purpose (`tools/`, `scripts/`) drift
   into duplicates unless the rule above is written down. Put the rule in `docs/agents/harness.md` or
   a short ADR, not CLAUDE.md alone (this repo's rule: a rule that must hold is a hook, not a
   sentence).
5. **Leaking through packaging.** Dev pushing `--path .` sends everything not in the default ignore
   list to the registry. Push only the staged `kubernetes/` copy.
6. **Public repo, one tree.** The Flux guide's caveat that Git cannot restrict file-level access is
   absolute here: the repo is public (ADR 0001), so the folder split protects nothing secret. It only
   controls what is packaged and who reviews.
7. **Stale CODEOWNERS or path filters** after a move, covered above. Add one check that every folder
   named in CODEOWNERS, `.sourceignore` and workflow `paths` still exists (inference; no source
   provides this).

## Open questions

- **ADR needed?** The layout is a decision. A short ADR would record: `kubernetes/` boundary, the
  `apps/` name split, the staged dev push, and the `tools/` versus `scripts/` rule. This note does not
  write it.
- **`apps/` naming.** `apps/` for source and `kubernetes/apps/` for manifests is what the skill and
  the homelab repos use, but the same word means two things. The alternative is another name for
  source (`src/`, `services/`), at the cost of departing from Turborepo, Nx and moon. Operator's call.
- **Flag behaviour not checked.** Whether `flux push artifact --ignore-paths` accepts negation
  patterns; how Podman names a per-Containerfile ignore file; whether `flux push artifact` ever
  reads `.sourceignore`. The staged copy avoids all three.
- **Local registry sync.** The Flux Operator sync page does not cover plain-HTTP registries; the
  `OCIRepository` page documents `spec.insecure`, but the FluxInstance field index shows no way to set
  it, so a `kustomize.patches` entry on the generated source is probably needed (the Operator reference
  shows that patch style for Cosign; not tested for `insecure`).
- **Self-approval on CODEOWNERS.** Not checked here. See the earlier note for the PR-author and
  required-review interaction.
- **Not read:** the contents of khuedoan/homelab `apps/`, onedr0p/home-ops workflow files, the Nx
  `tools/` convention on a first-party page (found via search summary only), and any official
  statement about kustomize-controller's load restrictor.

## Sources

Fetched 2026-10-25 unless noted.

- Flux: [Ways of structuring your repositories](https://fluxcd.io/flux/guides/repository-structure/)
  (page last modified 2024-05-13);
  [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example);
  [flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy) (neither shows a last-commit
  date); [Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/);
  [GitRepository](https://fluxcd.io/flux/components/source/gitrepositories/);
  [OCIRepository](https://fluxcd.io/flux/components/source/ocirepositories/);
  [flux push artifact](https://fluxcd.io/flux/cmd/flux_push_artifact/).
- Flux Operator: [cluster sync](https://fluxoperator.dev/docs/instance/sync/); the local
  `gitops-knowledge` skill (`.claude/skills/gitops-knowledge/references/{repo-patterns,monorepo-delivery,gitless-gitops}.md`
  and `assets/schemas/fluxinstance-fluxcd-v1.fields.txt`), which is a downloaded skill and therefore
  a secondary summary of the Flux Operator docs.
- Monorepo tools: [Turborepo](https://turborepo.dev/docs/crafting-your-repository/structuring-a-repository),
  [Nx folder structure](https://nx.dev/docs/kb/folder-structure),
  [Nx module boundaries](https://nx.dev/docs/features/enforce-module-boundaries),
  [moon workspace](https://moonrepo.dev/docs/config/workspace),
  [Pants source roots](https://www.pantsbuild.org/stable/docs/using-pants/key-concepts/source-roots),
  [Bazel dependencies](https://bazel.build/basics/dependencies).
  The Nx `tools/` statement comes from a search summary of Nx pages, not a page I read.
- OpenTofu: [module structure](https://opentofu.org/docs/language/modules/develop/structure/),
  [dependency lock](https://opentofu.org/docs/language/files/dependency-lock/),
  [github/gitignore Terraform](https://github.com/github/gitignore/blob/main/Terraform.gitignore).
- GitHub: [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners),
  [workflow syntax, paths](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions)
  (the first 100,000 of 235,836 characters were read; the section on `paths` was in that part).
- Docker: [build context](https://docs.docker.com/build/concepts/context/),
  [multi-platform](https://docs.docker.com/build/building/multi-platform/).
- Claude Code: [memory](https://code.claude.com/docs/en/memory),
  [large codebases](https://code.claude.com/docs/en/large-codebases).
- Homelab repos: [onedr0p/home-ops](https://github.com/onedr0p/home-ops),
  [ajgon/home-ops](https://github.com/ajgon/home-ops),
  [khuedoan/homelab](https://github.com/khuedoan/homelab). Tree listings are the GitHub UI's, which
  may be truncated by "View all files". Newest-commit dates from the commits atom feed
  (onedr0p, khuedoan) or commits page (ajgon).
- Secondary, for the kustomize load-restrictor point only: kubernetes-sigs/kustomize issues
  [#766](https://github.com/kubernetes-sigs/kustomize/issues/766) and
  [#4052](https://github.com/kubernetes-sigs/kustomize/issues/4052), and a PR in a third-party repo
  found by web search. Treat as community reports.
