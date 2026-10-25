# Build or task orchestrator for a polyglot monorepo

Checked 2026-10-25. Sources are upstream docs read from the projects' own repositories (through the
GitHub API as the homelab App), release and advisory metadata from the GitHub API, the npm registry,
and the OpenSSF Scorecard API. Two facts about this sandbox come from commands run in it today and
are marked "tested". Anything marked "inference" is mine, not a source's.

Question, from the operator: what build or task orchestrator do small teams run for a polyglot
monorepo with Node (pnpm workspaces), Python (uv workspaces) and OpenTofu, with more languages
later; what is the established pattern; what are its failure modes. Context: solo-operator public
repo, Flux GitOps, kind dev on WSL2 Debian 13, Talos prod. [ADR 0007](../adr/0007-external-resources-and-interfaces.md)
fixes OpenTofu (run by the operator from the workstation, state in HCP Terraform). Today the repo
holds only the Claude harness, docs and bash tools in `tools/`.

## Short answer

- **No source measures what small teams run, so "established pattern" is partly my reading.** What
  the sources do show is three tiers. (1) Native workspace tools only: `pnpm -r`, `uv`, `tofu`, with
  a task runner on top. (2) A graph-and-cache layer: Turborepo, Nx, moon, and now mise's workspace
  graph. (3) A hermetic build system: Bazel or Pants. moon's own docs place itself "between Bazel
  (high complexity, full structure), and make/just/etc scripts (low complexity, no structure)".
- **Verdict: adopt go-task as the one entry point, build nothing, adopt no graph tool yet.** It is
  the only candidate that passes all six checklist lines. The "no build graph" baseline costs one
  YAML file and keeps `pnpm-lock.yaml` and `uv.lock` as the only lockfiles.
- **Bazel is the wrong default for this repo today** and fails the checklist on its OpenTofu leg
  (`rules_tf`: one maintainer, last release 2025-07-09). The sharper reasons are practical: Bazel's
  own sandbox cannot start inside the Claude Code sandbox (tested), `rules_python` cannot read
  `uv.lock`, and OpenTofu plan and apply are not hermetic actions anyway.
- **The graph tools are all weakest exactly where this repo is.** Each has a gap on one of
  uv, pnpm or OpenTofu: Pants (no `uv.lock`, JS beta, Terraform alpha), Nx (Python is a community
  plugin with one maintainer), Turborepo (uv support experimental since 2026-09-18), moon (Python and
  uv toolchains are `unstable_`, one maintainer), mise (graph is new, caches experimental, one
  maintainer, repeated trust-model advisories).
- **Revisit when a trigger fires** (section "Verdict"). Bazel becomes right under the conditions
  listed at the end.

## Bazel in the Claude sandbox, tested (second pass, 2026-10-25)

Run by the conductor after the operator said Go and C++ are certain, which meets this note's first
condition for Bazel. A scratch workspace, Bazel 9.3.1 through bazelisk v1.30.0:

- **Starts and builds.** `linux-sandbox` is not registered (no user namespaces), and Bazel falls back
  on its own to `processwrapper-sandbox`. That still runs each action in a symlink tree of only its
  declared inputs, so undeclared inputs fail. It does not isolate the network or the rest of the
  filesystem; hermeticity then rests on hermetic toolchains, not on the sandbox.
- **Output root.** `~/.cache/bazel` is read-only; `--output_user_root` on a gitignored folder in the
  repo works. `$TMPDIR` is a 9.8 GB tmpfs and ran out of space extracting LLVM, so it is not an option.
- **Server per command.** Each Bash call gets its own process namespace, so the Bazel server dies
  between calls. A cold start cost 1.3 s; the on-disk action cache survives (a later build was all
  cache hits).
- **Go and C++ with no host compiler.** The host has no gcc and no libc headers. rules_go 0.59.0
  fetched its SDK and modules; it needs a C toolchain even with `pure`. `toolchains_llvm` 1.12.0
  downloaded LLVM 19.1.7 but compiled against host libc headers (`features.h` not found), so it needs
  a sysroot. `hermetic_cc_toolchain` 4.3.0 (Zig, ships libc) worked once
  `HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX` pointed at a writable folder (`--repo_env` and
  `--action_env`): `go_test` passed, `go_binary` and a C++ `cc_binary` ran, and
  `--platforms=@zig_sdk//platform:linux_arm64` produced an aarch64 ELF (e_machine `0xB7`).
- **Hosts used:** bcr.bazel.build, releases.bazel.build, mirror.bazel.build, github.com and its
  release-asset hosts, dl.google.com, proxy.golang.org, ziglang.org. Each went through
  `allowed_domains`; a permanent setup puts them on the sandbox allowlist (operator's settings).
- **Not tested:** rules_js with pnpm, rules_py or rules_python with uv, rules_oci images, a remote
  cache, and the size of the output root over time (12 GB after this test, LLVM included).

- **Why `linux-sandbox` cannot start, and the one switch.** Inside the sandbox `max_user_namespaces`
  is 0 and a seccomp filter refuses `unshare`/`clone` with the user- or mount-namespace flag (EPERM),
  per the [sandbox-runtime README](https://github.com/anthropic-experimental/sandbox-runtime).
  Claude Code has `sandbox.allowNestedUserNamespaces` (user or managed settings only, v2.1.305+). Its
  [sandboxing page](https://code.claude.com/docs/en/sandboxing) warns that with it on, "code from a
  sandboxed command can end up running outside the sandbox" and protected paths do not hold. Read
  through a summarizing fetch, 2026-10-25; check the exact wording before quoting it in an ADR.
  `excludedCommands: ["bazel *"]` runs Bazel with no filesystem or network limits at all. The
  remaining route keeps the client sandboxed and runs actions on a remote-execution worker under the
  runtime user (ADR 0018's pattern); not tested.

- **rules_tf 0.0.10 on Bazel 9.3.1 (its own CI pins Bazel 7.0.0).** Module resolution, analysis and
  the `tofu` 1.10.6 toolchain download worked; the toolchain fetches the official OpenTofu GitHub
  release for any `version` and checks it against that release's `SHA256SUMS` (read in
  `tf/toolchains/tofu/toolchain.bzl`), so a new OpenTofu release needs no new rules_tf. The checksum
  comes from the same release as the binary, not from a hash pinned in this repo. `//tfmod:format`
  passed; `validate` and `lint` failed with go-plugin handshake errors. The cause is the Claude
  sandbox, not rules_tf: plain `tofu validate` fails the same way, and creating any `AF_UNIX` socket
  returns EPERM there. Providers and tflint plugins talk to their host over a Unix socket, so
  provider-backed `tofu` commands cannot run inside the Claude sandbox at all; they run in CI, on the
  operator's shell, or on a remote-execution worker.

- **BUILD generation: `aspect_gazelle_prebuilt` 0.0.28** ([aspect-build/aspect-gazelle](https://github.com/aspect-build/aspect-gazelle),
  Apache-2.0, release 2026-10-22, in the BCR; prebuilt binaries for linux and darwin on amd64 and
  arm64 with in-toto provenance; 12-month commits: jbedard 393, gregmagolan 17, alexeagle 6, others
  under 7). One prebuilt binary carries the go, cc (EngFlow gazelle_cc), js, python, proto and
  starlark languages, so neither Gazelle nor its plugins are compiled locally. Tested here with
  `languages = ["go", "cc"]` and `repo_config = None` (it refuses go without a repo config, by
  design): it generated a correct `go_library`/`go_test` and a `cc_library`, the generated Go test
  passed, and `gazelle.check` (from `with_check = True`) exited 0 when clean and 1 with a diff after a
  new `.cc` file. Upstream `bazel-gazelle` has no JS or C++ language; those come from Aspect and
  EngFlow anyway. js and python languages not tested.

- **Tools through `bazel run` (2026-10-25, Bazel 9.3.1, rules_multitool 1.11.1, shellcheck 0.11.0,
  gitleaks 8.30.1).** `bazel run @multitool//tools/<tool>:cwd -- <args>` runs in the caller's
  directory (the README's workaround for bazelbuild/bazel#3325; without `:cwd` the tool starts in
  the runfiles tree), passes exit codes through (shellcheck 1 on SC2164, 0 on a clean file) and
  forwards stdin (gitleaks `stdin` found `aws-access-token`). Timing in the Claude sandbox: 3.1 s
  for the first `bazel run` of a Bash call, 0.16 to 0.45 s for later ones in the same call, against
  ~0 s for the bare binary. The server is a long-lived process by design ("will stop after a period
  of inactivity (3 hours, by default ... `--max_idle_secs`)", docs/run/client-server.mdx), but in the
  sandbox it dies with each Bash call (new pid every call), because each call runs in its own
  process namespace; in the operator's shell and CI it persists. Concurrency: "Each server can
  handle at most one invocation at a time; further concurrent invocations will either block or
  fail-fast (see `--block_for_lock`)"; tested, the second of two parallel runs printed "Another
  command holds the output base lock ... Waiting" and both finished in 0.87 s, because `bazel run`
  builds on the server and then has the client `exec()` the binary (docs/contribute/codebase.mdx),
  so the lock covers only the build step. A `bazel run` binary that itself calls `bazel run` (prek
  calling its hooks) works: inner calls got the lock and their real exit codes. Not measured: the
  analysis-cache discard Bazel does when flags differ between commands, so tool runs should share
  the flags of normal builds.

- **An empty graph and fetching tools (2026-10-25).** With only `tools/BUILD.bazel`
  (`exports_files` of the lock), `bazel test //...` exits 4 ("No test targets were found, yet
  testing was requested") and `bazel fetch //...` exits 0 but downloads no multitool tool, since no
  `//...` target depends on them; `bazel fetch @multitool//tools/...` downloads them, after which
  `bazel run --nofetch @multitool//tools/<tool>:cwd` runs offline. Linked worktrees: the sandboxing
  docs say writes to the main repository's shared `.git` are allowed from a linked worktree, but
  "Writes to `hooks/` and `config` inside that directory remain denied".

- **Per-user configuration without repo paths (2026-10-26, Bazel 9.3.1, bazelisk 1.30.0, #19).** A
  workspace whose `.bazelrc` ends `try-import %workspace%/user.bazelrc`, with a gitignored
  `user.bazelrc` holding `startup --output_user_root=<dir>` (and `common --disk_cache=<dir>`): `bazel
  info output_base` lands under `<dir>`; with `user.bazelrc` absent, Bazel falls back to
  `~/.cache/bazel` (in the sandbox: `FATAL: mkdir ... Read-only file system`). bazelisk reads
  `BAZELISK_HOME` from a `.bazeliskrc` in the workspace (its `downloads/` appeared there with no
  environment variable set); without one it fails on `~/.cache/bazelisk` (read-only). So each user
  points the caches where they like from untracked files, and the repo names no path outside itself.
  `bazel run` takes the target's environment from `--run_env=NAME=value` (Bazel 9.3.1 `bazel help
  run`), which works from `user.bazelrc` (`run --run_env=PREK_HOME=<dir>`): a run target printing
  `PREK_HOME` showed the rc's value, and the rc's value won over the same variable in the shell.
  bazelisk runs before any rc file is read, so `BAZELISK_HOME` alone comes from the environment or a
  `.bazeliskrc`; bazelisk takes the environment over the workspace's `.bazeliskrc` over `~/.bazeliskrc`.
  `output_user_root` is not a `bazel info` key (`ERROR: unknown key(s)`, exit 2); `bazel info
  output_base` lands under it. An rc file does not expand environment variables: `common
  --disk_cache=$TMPDIR/...` in `user.bazelrc` made a directory literally named `$TMPDIR` in the
  workspace, so whoever writes `user.bazelrc` writes absolute paths (a shell expands them first).
  `bazel cquery` takes one query expression: `cquery //:a //:b` fails (`unexpected token '//:b'
  after query expression '//:a'`, exit 2), `cquery "set(//:a //:b)"` lists both outputs.

This removes the claim in the short answer that the sandbox "removes the reason to pay for Bazel":
the reason moves from the sandbox to the toolchains, and those work here.

## Findings per candidate

### Bazel (rules_js, rules_python or rules_py, rules_tf)

- **Language coverage.** Node through `aspect_rules_js` (v3.5.2, 2026-10-22). Python through
  `rules_python` 2.4.5 (2026-10-23) or Aspect's `rules_py` (v2.0.0-alpha.10, 2026-10-22; v1.13.0
  stable, 2026-10-21). OpenTofu through `rules_tf` v0.0.10 (2025-07-09; in the Bazel Central Registry
  with one listed maintainer, last commit 2025-12-15). Its README says the rules "are useful to
  validate, lint and format terraform code". Nothing there runs plan or apply.
- **pnpm lockfile: respected.** rules_js reads `pnpm-lock.yaml` directly
  ([docs/pnpm.md](https://github.com/aspect-build/rules_js/blob/main/docs/pnpm.md)): "The pnpm
  lockfile format includes all the information needed to define `npm_import` rules ... so that Bazel
  can guarantee supply-chain security". The price: pnpm hoisting must be off ("`rules_js` does not
  and will not support pnpm 'phantom' hoisting"; the docs recommend `hoist: false`), every package
  with npm deps needs `npm_link_all_packages()` in its BUILD file, plugin-style tools (eslint,
  prettier) need `public_hoist_packages`, and missing transitive deps need `pnpm.packageExtensions`.
  Changing `package.json` does nothing for Bazel until the lockfile is regenerated. README known
  issue: "ESM imports escape the runfiles tree and the sandbox" (#362).
- **uv lockfile: not respected by the main Python rules.** `rules_python`'s
  [lock docs](https://github.com/bazel-contrib/rules_python/blob/main/docs/pypi/lock.md): "Currently
  `rules_python` only supports `requirements.txt` format" (`pylock.toml` is tracked in #2787). Its
  experimental `uv` `lock` rule runs `uv pip compile` to produce `requirements_lock.txt`, so the repo
  would carry `uv.lock` for uv and a derived second lockfile for Bazel. The docs warn that the
  workspace heuristic "may incorrectly assume the upper-most workspace `pyproject.toml` is the
  correct one". Aspect's `rules_py` can read `uv.lock` directly
  ([docs](https://aspect.build/docs/bazel/python/uv.md)), but through
  `@aspect_rules_py//uv/unstable:extension.bzl` ("the extension API may change between" releases).
  That page does not document uv workspaces, and notes that entrypoints are not auto-detected and
  sdist builds may need annotations.
  [`bazel-contrib/rules_uv`](https://github.com/bazel-contrib/rules_uv) (checked 2026-10-25,
  added after the first draft at the operator's prompt) does not change this. Its README offers two
  rules: `pip_compile`, which runs `uv pip compile` on `requirements.in` or `pyproject.toml` to write
  a hashed `requirements.txt` plus a diff test, and `create_venv`; it needs `rules_python` for the
  toolchain and feeds `rules_python`'s `pip.parse`. No rule reads `uv.lock` or uv workspaces, so it
  is the same derived-second-lockfile shape, with uv as a faster resolver. Multi-platform means one
  `requirements_<os>.txt` per platform.
- **Affected-only and caching.** Both are core and the strongest of any candidate: a content-addressed
  action cache, remote cache and remote execution, `bazel query` for the graph.
- **Upkeep for a solo maintainer** (the sources give no hour counts; this is what the docs make
  recurring):
  - A BUILD file per Bazel package, plus `MODULE.bazel` and `MODULE.bazel.lock` to review.
  - A major Bazel release about every 12 months; Bazel 7 ends support in Dec 2026, Bazel 9 is
    Active until Dec 2028 ([release policy](https://bazel.build/release)).
  - `rules_python` is "a community maintained project run by volunteers" and "only the latest
    version is supported" ([support policy](https://github.com/bazel-contrib/rules_python/blob/main/docs/support.md)).
    Its high advisory GHSA-f8vq-jw3w-q789 (2026-10-23, fixed in 2.4.5) is about the rules bundling an
    old `uv`, `pip` and `twine` with a distrusted CA root: the fix reached you only by upgrading the
    rules, not by upgrading uv.
  - Every linked lockfile is a second place for drift (pnpm hoist setting, requirements_lock.txt).
- **OpenTofu.** `tofu plan` and `apply` need network, provider downloads and HCP Terraform state, so
  they cannot be hermetic Bazel actions; they would be tagged to escape the sandbox. ADR 0007 has the
  operator run them from the workstation anyway.
- **WSL and macOS.**
  - WSL2: Bazel is a Linux build there. I found no Bazel-specific WSL guidance. The general advice
    (Microsoft, via the Ladybird and SerenityOS notes) is to keep the repo on the ext4 side; this repo
    is at `/home/gaserban/src/homelab` and `/mnt` is denied to the sandbox anyway.
  - macOS: needs the Xcode command line tools ([install page](https://bazel.build/install/os-x)).
    The Bazel Linux and macOS sandboxes "do not work in a 'nested' scenario", and on macOS "you cannot
    run `sandbox-exec` inside a process that's already being sandboxed"
    ([sandboxing](https://bazel.build/docs/sandboxing)).
- **From the Claude Code Bash sandbox (all three points tested or read from `.claude/settings.json`
  on 2026-10-25).**
  - `unshare --user --map-root-user --mount --pid --fork true` fails with "Operation not permitted"
    here. Bazel's `linux-sandbox` needs user namespaces, so Bazel would fall back to
    `processwrapper-sandbox` or `local` (documented fallback), which drops the hermeticity that is the
    reason to pay for Bazel.
  - The default output base is under `~/.cache`, outside the sandbox's write allowlist (only `.` and
    `$TMPDIR`). It needs `--output_user_root` inside the repo or `$TMPDIR` (inference from the
    configured allowlist).
  - The network allowlist has `github.com` and `registry.npmjs.org` but not `bcr.bazel.build`
    (tested: denied), the Bazel release server, `pypi.org`, `files.pythonhosted.org` or
    `registry.opentofu.org`. Bazel would add four to six allowlist lines and keep adding them as rules
    pull tools.

### Pants

- **Coverage.** Ships with Python, Go, Java, Scala, Kotlin, Shell and Docker
  ([welcome](https://www.pantsbuild.org/stable/docs/introduction/welcome-to-pants)). JavaScript: "Javascript
  support is beta stage"; it wraps `npm`, `pnpm` and `yarn` with a caching layer, with pnpm workspaces
  supported. Terraform: "Terraform support is in alpha stage"
  ([docs](https://github.com/pantsbuild/pants/blob/main/docs/docs/terraform/index.mdx)); the backend
  downloads HashiCorp's `terraform` (default URL `releases.hashicorp.com/terraform`) and I found no
  OpenTofu mention in the docs or issues.
- **Lockfiles.** pnpm: yes, Pants models the package manager's lockfile as a resolve. Python: no
  `uv.lock`. Pants delegates to Pex and its docs say lockfiles "are generated by Pex"; manual
  lockfiles must be Pex JSON or `requirements.txt` style. A `uv` resolver option exists for
  generating them, with open and closed issues in 2026 (#23476 open, #23407 open, remote-cache bugs
  #23344 and #23438 closed).
- **Affected and cache.** Yes (`--changed-since`-style goals, local and remote cache, remote
  execution). Hermetic sandboxing without namespaces, so it would run inside the Claude sandbox
  (inference; not tested).
- **Upkeep.** BUILD files generated by `pants tailor`; `pants.toml`; one lockfile per resolve.
- **Checklist notes.** No macOS x86_64 binary: `scie-pants` v0.13.2 ships only linux-aarch64,
  linux-x86_64 and macos-aarch64, and the Pants 2.33.1 wheels and PEXes list darwin_arm64 and linux
  only. Fine for Apple Silicon, fails the line as written.

### moon (moonrepo)

- **Coverage.** Toolchains for Go, Node, Bun, Deno, npm, pnpm, yarn, TypeScript, Rust, Ruby and
  Python, but Python, pip, poetry and uv are named `unstable_python`, `unstable_pip`,
  `unstable_poetry` and `unstable_uv`
  ([toolchain config](https://github.com/moonrepo/moon/blob/master/website/docs/config/toolchain.mdx)).
  OpenTofu is Tier 0: run it with `toolchain: system` and install it yourself, or use a
  third-party proto plugin (`appthrust/proto-toml-plugins`, listed in proto's registry).
- **Lockfiles: respected.** moon parses manifests and lockfiles (Tier 2 "Ecosystem platformization");
  its v1.32 notes say Python "relies on `pyproject.toml` and `uv.lock` instead of `requirements.txt`".
  It drives the native package manager rather than replacing it.
- **Affected and cache.** `moon run --affected` (git-based plus graph relations); local cache; remote
  cache through any Bazel Remote Execution v2 compatible service such as `bazel-remote` (self-hosted,
  since v1.30).
- **Upkeep.** Projects must be declared in `.moon/workspace.*`; task inheritance reduces repetition;
  moon downloads its own tools through proto into `~/.proto` unless `MOON_TOOLCHAIN_FORCE_GLOBALS`.
  Its FAQ lists what system-toolchain languages lose: automatic install, consistent versions,
  automatic dependency installs on lockfile change.
- **Agent fit.** Single Rust binary from GitHub releases (hosts already allowlisted); tool
  downloads would add hosts. `~/.proto` is outside the sandbox write allowlist (inference).
- **Risk.** About 95% of recent commits are one author (385 commits by `milesj` in the last 12
  months against at most 6 by anyone else).

### Nx with a Python plugin

- **Coverage.** Nx's own `packages/` directory has no Python or Terraform package (it has
  dotnet, gradle, maven, docker and the JS stack). Python comes from `@nxlv/python`, a community
  plugin (v23.3.1, 2026-10-21, MIT, peer `@nx/devkit >=22`) whose README states "Nx ... doesn't have
  built-in support for Python projects, this plugin aims to fill this gap" and supports uv or Poetry.
  One author wrote 52 of about 60 human commits in the last 12 months.
- **Lockfiles.** Nx hashes against the lockfile; by default "a change to your package manager's lock
  file affects every task", narrowed with `projectsAffectedByDependencyUpdates: "auto"`.
- **Affected and cache.** `nx affected` (git base and head, task inputs and graph); local cache;
  Nx Cloud, or a free self-hosted S3, GCS or Azure cache plugin with an optional activation step
  (Nx's own pages; one older Powerpack page still calls it paid, so check at adoption).
- **Risk.** 2025-08-27 critical advisory GHSA-cxm3-wv7p-598c: malicious Nx and plugin versions were
  published to npm (since deleted). Five high advisories in 2026 (command injection, daemon sockets
  open to other local users, zip-slip in the self-hosted cache), all fixed in 22.7.x. Scorecard 7.9.
- **Upkeep.** `nx.json`, per-project `project.json` or inferred targets, an npm-installed daemon and
  Node as the host runtime for a Python and OpenTofu repo.

### Turborepo

- **Coverage.** JavaScript and TypeScript natively. Turborepo 2.11 (post dated 2026-09-18) "can now
  discover packages and dependency relationships from Cargo, uv, and `go.work` workspaces", behind
  `futureFlags.experimentalPythonWorkspaces`; the uv page says "uv support is experimental and can
  change at any time". The RFC (opened 2026-07-31) reports a cache-hash bug: the hash included the
  kernel version, hurting portability across CI runners, VMs and WSL; a fix was linked.
- **Lockfiles.** pnpm: yes, lockfile feeds the global and per-package hash. uv: root `uv.lock`
  required; "Turborepo never creates or updates `uv.lock`"; caching includes "the resolved external
  dependency closure from `uv.lock`, scoped to each member".
- **OpenTofu.** Not a supported toolchain. The multi-language guide says other toolchains run through
  `package.json` scripts, so each tofu root would need a shim `package.json` (inference from that
  guide; I found no OpenTofu example). Package names must be unique across the whole graph.
- **Affected and cache.** `--filter`, `--affected`, local `.turbo/cache`; remote cache defaults to
  Vercel's, replaceable through the Remote Caching API.
- **Agent fit.** Release tarballs for linux and darwin on x64 and arm64 on GitHub (allowlisted) and
  npm optional packages. README tagline: "Turborepo is the build system for coding agents" (vendor
  claim, not tested).
- **Risk.** About 95% of commits in the last six months are one author, inside a Vercel-owned
  project; the one high advisory is for the VS Code extension.

### Plain task runner delegating to native tools

This is the baseline. The native tools already cover most of what a graph tool would add:

- pnpm: `pnpm --filter "...[origin/main]" run build` runs only changed packages and their dependents
  ([pnpm filtering](https://pnpm.io/filtering); needs Git 2.24 or newer; merge-base comparison since
  v12.7.0).
- uv: one `uv.lock` for the whole workspace, `uv run --package <member>`; the docs mention no
  changed-only mode. Workspaces force one shared `requires-python` and are "not suited for cases in
  which members have conflicting requirements".
- OpenTofu: no workspace-level graph; `tofu -chdir=<root>`. Changed-only has to be a path check on
  `git diff --name-only` (script you write).

Runners compared:

| Runner | Skip unchanged work | Notes |
| --- | --- | --- |
| go-task v3.54.0 (2026-10-01) | `sources`/`generates` with `checksum` (default), `timestamp` or `none`; fingerprints in `.task/` (local) | `task --list --json`, `--dry`, `--summary`, `--watch`; `includes` for per-directory Taskfiles; install by release binary or script that "verifies its checksum" |
| just 1.59.0 (2026-10-15) | none | "a command runner, not a build system"; CC0-1.0 licence |
| mise v2026.10.19 (2026-10-24) | `sources`/`outputs` freshness; artifact and remote cache are `experimental = true` | Now has a monorepo mode and a workspace graph (below) |

**mise deserves its own note because it has stopped being only a runner.** Its docs describe a
`//path:task` monorepo mode and a graph inferred from Cargo, uv, Go, Gradle and Node (pnpm) manifests,
with `mise run --affected <task>` (also `--affected-explain`, `--affected-json`). For a changed
`pnpm-lock.yaml` only Node projects whose lockfile entries changed are selected; "other lockfiles
count as ordinary files", so a changed `uv.lock` selects projects by file ownership, not by resolved
closure (my reading). The changelog puts workspace graph and affected in 2026.8.0 and 2026.8.1
(2026-08-01 and 2026-08-03) and drops the experimental gate on `--affected` working-tree support in
2026.10.6 (2026-10-09). The artifact cache and remote cache are still experimental. `mise.lock`
records tool versions with checksums and covers tools only, not `uv.lock` or `pnpm-lock.yaml`. It has
`opentofu`, `pnpm`, `uv` and `node` in its registry (the `node` core plugin downloads from
nodejs.org, not allowlisted). It has had seven high or critical advisories in 2026, mostly its trust
model for repository config and signature verification (for example GHSA-fjj5-v948-whjj, critical,
arbitrary code execution through templates in `.tool-versions`; GHSA-6986-cq7v-7cj9 implicit project
trust), all fixed by 2026.10.0. For a repo where an agent edits config files, that class of bug
matters. The docs say "Jeff Dickey created mise and maintains it".

## Adopt-or-build checklist

Source: `.claude/skills/hl-engineer/reference.md`. Dates are the latest release (R) and the checked
commit window (12 months back from 2026-10-25). "Maintainers" counts distinct human committers with
material activity in the last 12 months, plus what the docs say. "Open critical" means an
unpatched critical advisory on the project's GitHub advisory list.

| Candidate | Maintained | Licence | Security | Maintainers | Images (linux and darwin, amd64 and arm64) | Pinning |
| --- | --- | --- | --- | --- | --- | --- |
| Bazel 9.3.1 | Pass (R 2026-10-21) | Pass, Apache-2.0 | Pass; no high or critical advisory; Scorecard 5.5 (2026-10-24) | Pass (many; top three each 190+ commits) | Pass (bazel 9.3.1: darwin arm64 and x86_64, linux arm64 and x86_64; bazelisk v1.30.0 same) | Pass (`.bazelversion`, `MODULE.bazel.lock` integrity hashes) |
| rules_js v3.5.2 | Pass (R 2026-10-22) | Pass, Apache-2.0 | Unverified (no Scorecard; no advisories) | Pass (Aspect: jbedard 309, plus others) | n/a, Starlark | Pass |
| rules_python 2.4.5 | Pass (R 2026-10-23) | Pass, Apache-2.0 | Pass with note: high GHSA-f8vq-jw3w-q789 published 2026-10-23, fixed in 2.4.5 (current); no Scorecard | Pass but volunteers: rickeylev 363, aignas 85 | n/a, Starlark | Pass |
| rules_uv v0.89.2 | Pass (R 2025-12-01; last commit 2026-10-14) | Pass, Apache-2.0 | Unverified (no Scorecard data; 0 repository advisories, 2026-10-25) | **Fail** (12 months: markelliot 10 commits, next human 2) | n/a, Starlark | Pass |
| rules_tf v0.0.10 | Marginal (R 2025-07-09, older than 12 months; last commit 2025-12-15) | Pass, Apache-2.0 | Unverified | **Fail** (one maintainer, 26 stars) | n/a, Starlark | Pass |
| Pants 2.33.1 | Pass (R 2026-08-27) | Pass, Apache-2.0 | Pass; no advisories; Scorecard 5.3 (Security-Policy 0, Signed-Releases 0) | Pass (cburroughs, benjyw, tobni, sureshjoshi, tdyas) | **Fail** (no macOS x86_64; Apple Silicon only) | Pass (`pants_version`) |
| moon v2.6.4 | Pass (R 2026-10-23) | Pass, MIT | Unverified (no Scorecard; no advisories) | **Fail** (385 commits vs at most 6) | Pass (gnu and musl on x64 and arm64, macOS x64 and arm64) | Pass (proto pins tool versions; moon version set in config) |
| Nx 24.0.1 | Pass (R 2026-10-23) | Pass, MIT | Pass with note: critical GHSA-cxm3-wv7p-598c (2025-08-27, malicious publish, versions deleted) and five 2026 highs, none open; Scorecard 7.9 | Pass for core (FrozenPandaz 630, leosvelperez 422, jaysoo 394) | Pass via npm optional packages (linux x64 and arm64 gnu or musl, darwin x64 and arm64) | Pass |
| @nxlv/python 23.3.1 | Pass (R 2026-10-21) | Pass, MIT | Unverified (no Scorecard; no advisories) | **Fail** (one maintainer) | n/a, npm JS | Pass |
| Turborepo v2.11.10 | Pass (R 2026-10-20) | Pass, MIT | Unverified (no Scorecard); one high advisory, VS Code extension, patched | Unclear: one author is about 95% of commits, but Vercel-owned | Pass (GitHub tarballs for all four, plus npm) | Pass |
| mise v2026.10.19 | Pass (R 2026-10-24) | Pass, MIT | Pass with note: seven high or critical advisories in 2026, none open; no Scorecard | Unclear, lean fail: docs name one maintainer; three accounts have 200+ commits | Pass (linux and macos, x64 and arm64) | Pass (`mise.lock` with checksums, `install --locked`) |
| just 1.59.0 | Pass (R 2026-10-15) | CC0-1.0 is not on the list; public domain, so no stricter than permissive (operator's call) | Pass; no advisories; Scorecard 4.2 (Pinned-Dependencies 0, Signed-Releases 0) | **Fail** (casey 473, others at most 7) | Pass (aarch64 and x86_64, linux musl and apple-darwin) | Pass |
| go-task v3.54.0 | Pass (R 2026-10-01) | Pass, MIT | Pass; no advisories; Scorecard 6.1 (Signed-Releases 0) | Pass (vmaerten 160, andreynering 90, pd93 26) | Pass (linux and darwin, amd64 and arm64) | Pass (release tag pin in install script; `task_checksums.txt`) |
| uv 0.13.5 (not a candidate) | Pass | Pass, Apache-2.0 | High GHSA-hq85-5cpj-mr62 (2026-10-20), fixed in 0.13.4 | n/a | n/a | Pass (workspace `uv.lock`) |

Reading the table under the rule "a candidate that fails any line gets build or find another":

- Only go-task passes every line.
- Bazel passes for its core and the pnpm leg. Its OpenTofu leg fails (rules_tf), so that leg is
  "build" (a plain wrapper action) or skip it. Its uv leg is either a derived lockfile
  (rules_python) or an alpha rule set.
- Pants fails Images and is missing `uv.lock`; Nx's Python leg fails Maintainers; moon fails
  Maintainers; mise and Turborepo are unclear on Maintainers; just fails Maintainers.
- Scorecard data exists only for Bazel, Pants, Nx, just and Task. The rest are "unverified" per the
  checklist's wording, not "failed".

## How an agent operates each one from the Bash sandbox

| Candidate | What the Claude Code sandbox changes |
| --- | --- |
| Bazel | Nested sandbox fails (tested); output base outside the write allowlist; four to six new allowlist hosts; JVM server and a large cache under `$TMPDIR` |
| Pants | Single launcher from GitHub; downloads Python and tools on first run; no namespace sandbox; no macOS Intel |
| moon | Single binary from GitHub (allowlisted); `~/.proto` outside the write allowlist; tool downloads add hosts |
| Nx | `npm`/`pnpm install` only (npm registry allowlisted); the Nx daemon and Node host process; Python plugin needs `uv` on PATH |
| Turborepo | `pnpm add -D turbo` or GitHub tarball (both allowlisted); `uv` must be on PATH for Python |
| mise | Binary from GitHub; tool downloads use `github.com` (allowlisted) but `node` core uses nodejs.org (not); trust prompts need `mise trust` in a non-interactive run |
| go-task | One static binary from `github.com/go-task/task/releases` (allowlisted); `taskfile.dev/install.sh` is not allowlisted, so download the release asset; `.task/` lives in the repo (writable); `task --list --json` gives a machine-readable command list |

## Failure modes of the established pattern

- **Task runner only:** it grows into an ad hoc build system; cross-language dependencies (a Python
  service generating a client for a Node app) are invisible; no shared cache (`.task/` fingerprints
  are local); changed-only for uv and OpenTofu is a script you own; CI and local drift if the Taskfile
  is not what CI calls.
- **Graph-and-cache tools:** they sit on top of native tools, so the native tool's gaps remain (uv
  workspaces force one `requires-python`); they are youngest on Python and OpenTofu; most of their
  Python support is experimental, `unstable_` or community-run today; the "affected" decision depends
  on how each treats `uv.lock` (Nx: every task by default; Turborepo and moon: per-member closure or
  file ownership; mise: file ownership).
- **Hermetic build systems:** lockfile duplication (`uv.lock` and `requirements_lock.txt`), upkeep of
  BUILD files and rule versions, a yearly major upgrade, a second set of dependency-security
  advisories (rules bundling old tools), loss of hermeticity when the sandbox cannot nest, and
  IaC steps that cannot be hermetic.

## Verdict: adopt go-task, build nothing now

- **Adopt go-task** as the single entry point (`task lint`, `task test`, `task plan:<root>`), one
  root `Taskfile.yml` with `includes` per language directory. It delegates to `pnpm -r` and
  `pnpm --filter "...[origin/main]"`, to `uv run --package` and `uv sync`, and to `tofu -chdir`.
  It adds no lockfile, runs in the Claude sandbox from an allowlisted host, and passes all six
  checklist lines. Pin its version in the install step and check `task_checksums.txt`.
- **Build nothing else.** The "affected" script for uv and OpenTofu is a ten-line `git diff
  --name-only` check; write it when there is a second package, not before. Tool versions can use each
  ecosystem's native pin (`packageManager` for pnpm, uv's `required-version`, `required_version` in
  the tofu config) instead of adding mise (which fails or is unclear on Maintainers).
- **Not decided here:** this note does not create an ADR. A decision to pick the runner belongs in
  `docs/adr/`, drafted by the operator's flow.
- **Revisit triggers.** Any one of: (1) a second JS or Python package makes `pnpm --filter` and
  `uv --package` insufficient (a shared package or generated client crosses languages);
  (2) CI exceeds a threshold the operator names and caching would cut it; (3) a compiled language
  (Go, Rust) joins and needs its own build graph; (4) a second maintainer joins. At that point
  re-score Turborepo (if the uv flag graduates from experimental), mise's graph (if its caches leave
  `experimental`) and Bazel.

## When Bazel would be the right call

All of these should hold, or the first two plus the sandbox condition:

1. **A compiled or multi-target language joins** (Go, Rust, C++, container images through `rules_oci`),
   where Bazel's native rules are strongest and the others are weakest, and the repo needs one
   dependency graph across languages with correct invalidation.
2. **Build time or CI cost is the problem**, so remote caching and execution pay for themselves, and
   artifacts must be reproducible (for example signed images built from a pinned toolchain).
3. **The agent can run Bazel's sandbox**: unprivileged user namespaces available to it (a dev
   container or VM where `unshare --user` works, or Claude Code run outside bwrap), the allowlist
   gains `bcr.bazel.build`, the release server and PyPI, and the output base sits in a writable
   path. Otherwise Bazel runs unsandboxed and loses its main benefit.
4. **Someone owns it.** The operator has Bazel experience, which cuts the learning cost, not the
   upkeep: a second maintainer or a budget for yearly major upgrades and rule bumps.
5. **The Python story is settled**: either the team accepts `requirements_lock.txt` generated from
   `uv.lock`, or Aspect's `rules_py` uv extension leaves `unstable` and documents uv workspaces.
6. **OpenTofu stays outside the graph** (validate and lint only, or a thin wrapper), since plan and
   apply are not hermetic and `rules_tf` is a single-maintainer, 0.0.x rule set.

## Not verified

- No primary source measures what small teams adopt; the "established pattern" paragraph is my
  synthesis of vendor positioning and the tools' own roadmaps.
- No hour or cost figures for Bazel upkeep exist in the sources; the upkeep list is what the docs
  make recurring.
- Pants, moon, Nx, Turborepo and mise were not run in this sandbox. Only the Bazel namespace failure
  and the `bcr.bazel.build` denial were tested.
- OpenSSF Scorecard had no data for rules_js, rules_python, rules_py, rules_tf, moon, `@nxlv/python`,
  Turborepo and mise; those Security lines are "unverified".
- Whether mise's other high-volume committers hold merge rights is not stated in its docs.
- Pants OpenTofu support: not found in docs or issues; it may exist in an option I did not read.
