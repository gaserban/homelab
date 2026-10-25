# 0019 Monorepo on Bazel; tools from Bazel; languages wired when first used

Date: 2026-10-25

Status: Proposed. Accepted when the prototype for #19 builds and tests, inside the Claude sandbox, a
React component (Aspect rules_js and rules_ts with pnpm), a Python module (rules_uv), a Go and a C++
target, an OpenTofu module (rules_tf format), and runs every tool through `bazel run`.

## Context

The repo will hold TypeScript and React front ends, Python services and scripts, Go and C++ for
heavy jobs and connectors, and OpenTofu (ADR 0007). Switching build systems after apps exist is the
cost to avoid, and the operator knows Bazel. A task runner over pnpm and uv was the research
default until compiled languages became certain
([monorepo-build-tool.md](../research/monorepo-build-tool.md)). Tested in the Claude sandbox on
2026-10-25 (same note): Bazel 9.3.1 builds Go and C++ with downloaded toolchains and cross-compiles
to arm64. Its `linux-sandbox` cannot start, because the Claude sandbox refuses user namespaces, and
`allowNestedUserNamespaces` would let sandboxed code escape (ADR 0014). Unix sockets are refused too,
so provider-backed `tofu` commands cannot run there.

## Decision

- Bazel, pinned through `.bazelversion` and started by bazelisk, is the single build and test graph
  for every language. No Bazel, setup, hook-configuration or CI file names a home-directory (per-user) path. Tracked settings are the
  project's (`.bazelrc`, `.bazelversion`, `MODULE.bazel`, a project `.bazeliskrc` if one is ever
  needed) and are reviewed like code. Per-user settings live in files each user keeps untracked: a
  gitignored `user.bazelrc`, which `.bazelrc` imports last with `try-import %workspace%/user.bazelrc`
  (output root, disk cache, the Zig cache prefix, and `run --run_env=` for the caches of tools run
  through Bazel, such as prek's `PREK_HOME`), and, because bazelisk runs before any rc file is read,
  the user's environment for `BAZELISK_HOME`
  ([monorepo-build-tool.md](../research/monorepo-build-tool.md), "Per-user configuration without
  repo paths"). The operator's clone uses Bazel's defaults; CI adds only a disk cache. In the Claude sandbox `$HOME` is
  read-only, so Claude's checkout carries its own `user.bazelrc` pointing at the sandbox write path
  the operator grants in their Claude settings (a new directory outside the repository and outside
  `~/.cache`), which also set Claude's `BAZELISK_HOME`; that keeps
  Claude's output root apart from the operator's. Nothing Bazel writes lands in the worktree, apart
  from its gitignored `bazel-*` convenience symlinks, or near `.state/` (ADR 0018). The lockfile is
  checked everywhere (`common --lockfile_mode=error`); `bazel mod deps --lockfile_mode=update`
  refreshes it. Directories Bazel must not see are listed in `REPO.bazel` `ignore_directories`.
- No guard compares paths. The boundary is that the operator does not commit, push, or run Bazel,
  `./setup`, hl-runtime or the wizard, with a working directory inside Claude's checkout, and code reaches the operator's clone only through a reviewed merge; separate output
  roots keep a Claude-writable binary out of the operator's builds. bazelisk verifies an official
  Bazel release's detached signature against its embedded key (`httputil.go`), not a download from
  a mirror, a fork or a commit; a tracked `.bazeliskrc`, `tools/bazel` or `.bazelversion` that points
  elsewhere is a reviewed change like any other.
- Nothing Claude can change without review runs outside the sandbox, with three named exceptions:
  the App token helpers that a hook and the operator's PATH run from the worktree (#20 removes
  them); the root wizard, which the operator ran from the worktree (#19 moves it); and CI, which
  runs a pull request's code on ephemeral GitHub runners with a read-only token, no secrets and no
  persisted credentials. Claude's checkout is Claude's alone (the previous bullet lists what the operator does not do
  there). The operator works in their own clone from GitHub, outside
  every sandbox write path.
- Git hooks guard every commit and push: the operator writes two small shims into the `.git/hooks`
  of Claude's checkout and of their own clone. They run prek through `bazel run` with that
  checkout's configuration; the pre-push shim loops over every pushed ref. In Claude's checkout they
  run inside Claude's sandbox, which denies Claude writes to `.git/hooks` and `.git/config`. git-guard
  denies the direct bypasses (`--no-verify`, `SKIP`/`PREK_SKIP`, `core.hooksPath` overrides). The hooks catch
  Claude's mistakes, not a Claude that edits the configuration or reaches git indirectly, nor a
  push from a clone without hooks or a write through the GitHub API: before publication GitHub
  push protection is the only gate, and after it the required CI check and the operator's review.
- GitHub Actions workflows run outside any sandbox, so Claude's push credential never holds the
  Workflows permission: the operator adds workflow changes under their own account (GitHub's web
  editor on the PR branch), which extends ADR 0013's "only to approve and merge" to workflow
  commits; the default workflow token is read-only, and Actions may not create or approve pull
  requests.
- Bazel provides the tools, and every tool runs through `bazel run`, as Bazel intends: language
  toolchains through their rule sets, single-binary CLIs (kubectl, kind, flux, helm, prek,
  shellcheck, gitleaks, buildifier) through rules_multitool, run as
  `bazel run --config=tool @multitool//tools/<tool>:cwd --`
  so they work in the caller's directory. bazel_env is not used: it puts launcher scripts on PATH
  that rebuild themselves and break when copied. Each user installs bazelisk as `bazel` on their own
  PATH, since it must exist before Bazel. No mise. System packages (Podman, bubblewrap) stay an
  operator step. `./setup` checks them and that `bazel` is a bazelisk release whose SHA-256 it pins,
  prints how to install what is missing, and runs `bazel fetch //... @multitool//tools/...`, since
  `//...` alone fetches no tool; it installs nothing, writes no tracked file and never runs sudo. Measured in the sandbox: the first `bazel run` of a shell call takes about 3 s
  (the server dies with each call there), later ones in the same call well under a second;
  concurrent calls queue on the output-base lock only for the build step
  ([monorepo-build-tool.md](../research/monorepo-build-tool.md), "Tools through `bazel run`").
- Supported: Linux on amd64 and arm64, WSL2 included (the workstation). macOS and native Windows are
  unsupported, so tool locks carry Linux platforms only.
- Layout: `apps/` (deployables), `packages/` (shared libraries), `kubernetes/` (all Flux YAML, the
  only folder Flux packages), `opentofu/`, `tools/`, `docs/`, `.claude/`. A folder exists once
  something lives in it.
- Each language is wired when its first package lands, never ahead of it. One lockfile per language
  at the root: `pnpm-lock.yaml` read by Aspect's rules_js and rules_ts (`hoist: false`); Python from
  a root `pyproject.toml` compiled by rules_uv into a hashed `requirements.txt` for rules_python;
  one `go.mod` with rules_go; C++ through hermetic_cc_toolchain. aspect_gazelle_prebuilt writes
  BUILD files for every language it covers, and its check fails on a stale one. BUILD files list
  sources explicitly; no recursive globs (Bazel BUILD style guide).
- OpenTofu stays outside the graph for plan and apply (ADR 0007). rules_tf runs format, validate and
  lint as tests. Validate and tflint need Unix sockets, which the Claude sandbox refuses, and they
  run provider binaries the branch chooses: in CI they run on the runner; for Claude's commits on
  the remote-execution worker (#21); for the operator's, in a throwaway dev-runtime container. The
  hook entries land with the first OpenTofu module.
- Checks split by question. Questions about the repository as git sees it (secrets, shell lint by
  file type, Bazel file format, the hook suite) run in prek from `.pre-commit-config.yaml`, at
  commit and push through the hooks above and in CI over git's tracked files; gitleaks scans the
  commits being pushed, or in CI the pull request's commits with a gitleaks binary the workflow
  itself pins, always given the base branch's configuration (or the default rules) and ignore file,
  and inline allow markers ignored. The other CI hooks
  run the pull request's own configuration and tools, so the operator's review is their gate. A
  Bazel test sees the disk, not git, and replays cached results, so it cannot answer them. Questions about build targets run as `bazel test //...`, from the first
  package on. A GitHub Actions workflow runs both on `ubuntu-24.04` (amd64) and `ubuntu-24.04-arm`
  (arm64), pinned because `-latest` moves, and is a required check. shellcheck (GPL-3.0; run, never
  linked) and gitleaks (one dominant maintainer; nothing equivalent passes) are accepted exceptions
  to the adopt-or-build checklist.
- The Claude sandbox stays as ADR 0014 and ADR 0018 set it. Full isolation of build actions comes
  from remote execution on a worker under `homelab-runtime`, reached through `hl-tunnel`, decided
  and built in #21; its port will extend the three ports ADR 0018 lets the tunnel forward.
- Repo tooling: bash for glue (running and wiring other programs); Python once a script parses
  JSON, keeps state or passes about 100 lines (a Bazel `py_binary`, or stdlib `python3` where it
  must run before Bazel); Go for standalone binaries
  ([gates-and-repo-tooling.md](../research/gates-and-repo-tooling.md), part b). The Claude Code hooks stay
  bash and get shellcheck.

## Consequences

- Locally in the Claude sandbox Bazel uses `processwrapper-sandbox`: undeclared inputs fail, but
  network and filesystem are not isolated, so reproducibility rests on the downloaded toolchains
  until the remote-execution worker exists, and any action or repository rule can read what the
  sandbox can, `.state/` included.
- The Bazel server dies between Claude's shell calls; the first Bazel command of each call pays
  about 3 s. In the operator's shell and CI the server persists (three hours idle by default).
- Every download host goes on the sandbox allowlist, one commented line per tool, set by the operator.
- rules_tf and rules_uv each have one main maintainer; both are thin, and forking is the exit.
- Revisit Python when Aspect's rules_py reads `uv.lock` without an `unstable` extension.
- A Claude branch rebased over a commit that changed `.github/workflows/` may be refused on push,
  because its credential has no Workflows permission (unverified); branch from `origin/main` afresh.
- Container images (rules_oci) are a separate decision.
- Bash scripts at #19 (Done when 5):

| Script | Verdict | Reason |
| --- | --- | --- |
| `.claude/hooks/branch-cleanup.sh`, `.claude/hooks/flow-review-bound.sh`, `.claude/hooks/git-guard.sh`, `.claude/hooks/issue-template.sh`, `.claude/hooks/skills-restore.sh`, `.claude/hooks/test.sh` | kept | ADR 0019: Claude Code hooks stay bash, under shellcheck; operator-owned |
| `.claude/hooks/token-refresh.sh`, `tools/gh`, `tools/gh-app-token`, `tools/git-credential-homelab-app` | kept, named exception until #20 | #20 replaces them with `gh` and a machine account |
| `tools/setup-dev-runtime.sh` | kept, named exception | the operator's once-per-workstation root wizard (`wizard` skill form) |
| `tools/hl-runtime` | kept, named exception | keeps SSH keys but is ssh and podman wiring with no JSON |
| new `setup`, `tools/ci-bazel-test` | new | glue that parses no JSON; `setup` checks what must exist before Bazel's tools |

- Prototypes and spikes keep scratch under `$TMPDIR/hl-proto/<name>/` and end with a cleanup check
  (#22).
