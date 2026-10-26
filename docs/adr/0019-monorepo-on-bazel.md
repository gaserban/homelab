# 0019 Monorepo on Bazel; tools from Bazel; languages wired when first used

Date: 2026-10-25

Status: Accepted (2026-10-26). The prototype for #19 (#24) built and tested, inside the Claude
sandbox, a React component (Aspect rules_js and rules_ts with pnpm), a Python module (rules_uv), a Go
and a C++ target and an OpenTofu module (rules_tf format), and ran every tool through `bazel run`;
its 20 checks passed ([monorepo-build-tool.md](../research/monorepo-build-tool.md), "Prototype
results"), and its code is kept under the tag `spike-bazel-polyglot`, never merged. Corrected on
acceptance, from the same results: the reason OpenTofu validate and lint wait (Context, Decision),
and Go waits for an app that uses it (Decision).

## Context

The repo will hold TypeScript and React front ends, Python services and scripts, Go and C++ for
heavy jobs and connectors, and OpenTofu (ADR 0007). Switching build systems after apps exist is the
cost to avoid, and the operator knows Bazel. A task runner over pnpm and uv was the research
default until compiled languages became certain
([monorepo-build-tool.md](../research/monorepo-build-tool.md)). Tested in the Claude sandbox on
2026-10-25 (same note): Bazel 9.3.1 builds Go and C++ with downloaded toolchains and cross-compiles
to arm64. Its `linux-sandbox` cannot start, because the Claude sandbox refuses user namespaces, and
`allowNestedUserNamespaces` would let sandboxed code escape (ADR 0014). Creating a Unix socket is
refused too, and OpenTofu providers and tflint plugins are reached over one. That pass blamed the
socket for rules_tf's `validate` and `lint` failing; the prototype disproved it for both: `validate`
passes on a module with no providers, which starts no plugin, and `lint` fails on rules_tf's own
bundled tflint config ("`module` attribute was removed in v0.54.0"), not on a socket. No
provider-backed command was run.

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
  one `go.mod` with rules_go; C++ through hermetic_cc_toolchain. No Go code and no rules_go until
  an app uses Go (the operator, 2026-10-26). That app's wiring first meets the prototype's go.dev
  finding: rules_go looks up SDK hashes on go.dev, which is not allowlisted, unless `go_sdk` pins
  both Linux hashes in `sdks`, and its `go_sdk.from_file` still probes go.dev on every new server
  under `--lockfile_mode=error` (about 30 s in a fresh clone) until `bazel mod deps
  --lockfile_mode=update` writes the output base's lockfile or the operator allowlists go.dev
  ([monorepo-build-tool.md](../research/monorepo-build-tool.md), "Failures met and fixed").
  aspect_gazelle_prebuilt writes BUILD files for every language it covers, and its check fails on a
  stale one. BUILD files list sources explicitly; no recursive globs (Bazel BUILD style guide).
- OpenTofu stays outside the graph for plan and apply (ADR 0007). rules_tf runs format, validate and
  lint as tests, wired with the first OpenTofu module. Validate and lint are deferred to that
  module, not for lack of sockets: before it there is nothing to check, and, measured on the
  prototype, rules_tf's bundled tflint config fails on tflint 0.65.0, so that module brings a lint
  config of its own. Once validate and lint run provider binaries the branch chooses (and reach
  them over a Unix socket the Claude sandbox refuses), they run in CI on the runner; for Claude's
  commits on the remote-execution worker (#21); for the operator's, in a throwaway dev-runtime
  container. The hook entries land with the first OpenTofu module.
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
  must run before Bazel); Go for standalone binaries, once an app has wired Go
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
- Bash scripts at #19 (Done when 5): every tracked file whose first line is a bash shebang, one row
  each. #19 replaced none. The Claude Code hooks stay bash by the repo-tooling rule above, whatever
  their length; for the rest, "glue" means the rule's bash case (no JSON, no state, about 100 lines).

| File | Verdict | Reason |
| --- | --- | --- |
| `.claude/hooks/branch-cleanup.sh` | kept | Claude Code hook (deletes merged branches at session start); hooks stay bash, under shellcheck and the hook suite |
| `.claude/hooks/flow-review-bound.sh` | kept | Claude Code hook (bounds hl-engineer's plan-review rounds); hooks stay bash, under shellcheck and the hook suite |
| `.claude/hooks/git-guard.sh` | kept | Claude Code hook (the merge guard and the hook-bypass denials); hooks stay bash, under shellcheck and the hook suite |
| `.claude/hooks/issue-template.sh` | kept | Claude Code hook (refuses an issue body without the four headings); hooks stay bash, under shellcheck and the hook suite |
| `.claude/hooks/skills-restore.sh` | kept | Claude Code hook (restores downloaded skills, ADR 0017); hooks stay bash, under shellcheck and the hook suite |
| `.claude/hooks/test.sh` | kept | the hook suite, run by prek's `hook-suite` entry; tests bash hooks by feeding them payloads |
| `.claude/hooks/token-refresh.sh` | kept until #20 | Claude Code hook that mints the App token outside the sandbox; #20 removes it with the App token scripts, for `gh` and a machine account |
| `setup` | kept (new, #25) | glue that must run before Bazel: checks Podman, bubblewrap and the bazelisk pin, then `bazel fetch` |
| `tools/ci-bazel-test` | kept (new, #26) | CI glue around `bazel test //...` that accepts exit 4 only while no test target exists |
| `tools/gh` | kept until #20, named exception | wraps `/usr/bin/gh` with the App token; #20 removes it, for `gh` itself logged in as a machine account |
| `tools/gh-app-token` | kept until #20, named exception | mints and caches the App installation token (openssl, curl); #20 removes it |
| `tools/git-credential-homelab-app` | kept until #20, named exception | git credential helper serving the App token; #20 removes it, for `gh auth setup-git` |
| `tools/hl-runtime` | kept | glue at the 100-line mark: ssh, socat and podman wiring to the rootless Podman API (ADR 0018), no JSON; its kind, kubectl, flux and helm are already tool runs from the multitool lock (#25) |
| `tools/setup-dev-runtime.sh` | kept, named exception | the operator's once-per-workstation root wizard, mostly the `wizard` skill's generated library; its kind, kubectl and flux installs stay as an amd64-only fallback (#25, `docs/operator-setup.md`) |

- Prototypes and spikes keep scratch under `$TMPDIR/hl-proto/<name>/` and end with a cleanup check
  (#22).
