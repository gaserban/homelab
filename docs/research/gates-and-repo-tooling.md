# Gates and repo tooling: what replaces hand-written bash

Checked 2026-10-25 against first-party docs and repositories, fetched the same day: the Claude Code
docs (code.claude.com/docs), the docs inside each tool's own repository, the GitHub API (releases,
licences, advisories, commit counts, read with `gh api`), PEP 723, and the OpenSSF Scorecard API.
Where a claim comes from a local experiment in this repo's Bash sandbox, it says so.
[ADR 0014](../adr/0014-agent-harness.md) (hooks enforce) and
[ADR 0017](../adr/0017-downloaded-skills-restored-not-committed.md) frame the question. The
checklist is "Adopt-or-build checklist" in `.claude/skills/hl-engineer/reference.md`.

Question, from the operator, for a solo-operator public homelab repo (WSL2 Debian 13; Claude Code in
a Bash sandbox with a domain allowlist; python3 3.13 present, no uv, no pip, no node, no shellcheck):

- (a) What established tools replace hand-written bash for git hooks and pre-merge gates in a
  polyglot repo?
- (b) What replaces hand-written bash for custom repo automation? Is Python through `uv run` with
  PEP 723 inline metadata the established choice? What are the known failure modes?
- Separately: the repo's Claude Code hooks (7 registrations in `.claude/settings.json`, six scripts
  and one test file, 600 lines in `.claude/hooks/`): what do the docs require, does startup cost
  matter, and which would gain from a rewrite?

## Short answer

- **(a) Adopt prek, with a `.pre-commit-config.yaml`, as the hook runner; make CI run the same
  `prek run --all-files`.** The pre-commit YAML format is the de facto standard for polyglot hooks,
  prek is a single MIT binary that reads it unchanged (so upstream pre-commit stays a fallback), and
  `repo: local` + `language: system` hooks need no downloads. Lefthook is the runner-up and passes
  every checklist line too. Husky + lint-staged is Node-only and fails the checklist. mise tasks and
  just are task runners, not hook managers: they can be the thing a hook calls, not the hook layer.
  A git hook is advisory (`--no-verify` skips it); the pre-merge gate is a CI job that the branch
  ruleset requires. The repo has no workflow yet.
- **(b) Python via uv with PEP 723 is established for scripts that need third-party packages, but it
  is not "the" replacement for bash here, and in this sandbox it is the wrong first step.** PEP 723 is
  Final (2024-01-08) and uv implements it. But uv is not installed, `pypi.org` is not on the
  allowlist (tested: the run retries for 6.8 s and fails), and uv's cache directory is read-only in
  the sandbox (tested). Every task listed in the question (wrapping `gh`, `git`, `podman`, `kubectl`,
  JSON) needs only the standard library. Recommendation: stdlib-only `python3` (3.13 is there) for
  anything past about 100 lines or with real control flow; bash for short glue; PEP 723 and uv the
  day a script needs a package; a Typer package in a uv workspace not yet.
- **Claude Code hooks accept any executable.** Input is JSON on stdin; only exit code 2 blocks; the
  default timeout is 10 minutes. Startup cost is small: measured here, bash+jq 3 ms, `python3`
  15 ms, `uv run --script` 25 ms warm (one cold run 55 ms). Hooks on one event run in parallel, so
  the cost per Bash call is the slowest hook, not the sum. Rewrite candidates, in order of gain:
  `skills-restore.sh`, `issue-template.sh`, then `git-guard.sh`; leave `token-refresh.sh` in bash.
- **The biggest hazard in a rewrite is failing open.** A Python traceback exits 1, which Claude Code
  treats as a non-blocking error: the action goes ahead. Every guard needs a top-level
  `try/except` that exits 2.
- Three places where this repo's sandbox changes the textbook answer (all tested, section
  "Sandbox findings"): default cache directories (`~/.cache/prek`, `~/.cache/uv`) are read-only;
  `python3 -m pip` does not exist, so prek cannot bootstrap uv for Python hooks; PyPI is not
  reachable. Git hooks fired by `git commit` inside the sandbox inherit all three limits. Claude
  Code's own hooks do not: they run outside the sandbox.

## Part (a): hooks and pre-merge gates

### Three layers that are easy to confuse

| Layer | Fires on | Can the agent bypass it? | What this repo has |
| --- | --- | --- | --- |
| Claude Code hook (`.claude/settings.json`) | a tool call or session event | no, the harness runs it | six scripts, enforced (ADR 0014) |
| Git hook (`.git/hooks/*`) | `git commit`, `git push` | yes: `git commit --no-verify`, or no install in a fresh clone | none |
| CI gate (GitHub Actions + ruleset required check) | a pull request | no, once the ruleset requires it | no workflow yet |

A git hook is a convenience for fast feedback. The pre-merge gate has to be CI, because hooks are
not versioned (`.git/hooks` is not tracked) and `--no-verify` skips them. `git-guard.sh` could deny
`--no-verify` for the agent; that is a Claude Code hook, not a replacement for the CI gate.

### The candidates, from their own docs

| | pre-commit | prek | lefthook | husky (+ lint-staged) | mise tasks | just |
| --- | --- | --- | --- | --- | --- | --- |
| What it is | Python framework; hooks are git repos with a `.pre-commit-hooks.yaml` | Rust reimplementation of pre-commit, one binary | Go git-hooks manager; runs commands you write | Node package that points git at `.husky/` scripts | task runner + tool version manager | command runner |
| Latest release | v4.7.0, 2026-10-13 | v0.5.7, 2026-10-21 | v2.2.2, 2026-10-13 | v9.1.7, 2024-11-18 | v2026.10.19, 2026-10-24 | 1.59.0, 2026-10-15 |
| Installs itself | `pre-commit install` writes `.git/hooks/pre-commit` | `prek install` writes the shim; honours `core.hooksPath` | `lefthook install` writes `.git/hooks/*` calling `lefthook run` | `prepare` script in `package.json` runs `husky` | `mise generate git-pre-commit --write` writes a hook running `mise run pre-commit`, staged files in `$STAGED` | does not; call it from a hook |
| Hook environments | creates one per hook; downloads, installs and runs on first use | same, shared across hooks; managed toolchains for Python, Node, Bun, Deno, Go, Rust, Ruby | none: runs tools already on `PATH` | none: POSIX shell scripts | `[tools]` installs pinned tools (aqua/github backends) | none |
| Downloads from | the hook repo (git clone), then PyPI/npm/Go/Rust per `language`; node/golang/rust toolchains bootstrapped if missing | same, plus uv (PyPI wheel or astral releases) for Python; checksum-verified toolchains, uv download not yet covered | nothing at run time | npm registry at install | GitHub releases etc. per backend; `mise.lock` holds checksums | nothing |
| Speed (first-party) | 1,942 ms, 13 hooks, 960 files, warm | 1,534 ms same test; 80 ms with fast path and priorities (self-reported, M3 Pro, 2026-10-05) | "Fast", no numbers; `parallel: true` | n/a | tasks run `depends` in parallel | n/a |
| CI parity | `pre-commit run --all-files`; pre-commit.ci; `pre-commit/action` is "maintenance-only mode" | `prek run --all-files`; `j178/prek-action` | `lefthook run pre-commit --all-files` | `HUSKY=0` in CI; lint-staged is staged-only | `jdx/mise-action`, `mise run <task>`, `mise install --locked` | `just <recipe>` |
| Config | `.pre-commit-config.yaml` | the same YAML, or native `prek.toml` | `lefthook.yml` (YAML, TOML, JSON) | shell + `package.json` | `mise.toml` | `justfile` |
| Pin | `rev:` tag or SHA; `autoupdate --freeze` | `update --freeze`, `--cooldown-days`; `minimum_prek_version` | `remotes:` with `ref:` | npm lockfile | `mise.lock`; 24 h minimum release age by default | n/a |

Sources: [4], [5], [6], [7], [8], [9], [10]; release data [16].

Notes that change a decision:

- **prek reads the same config as pre-commit**, so adopting prek is not a bet on prek's survival. Its
  compatibility page lists one unimplemented command (`hazmat`) and, in the differences page, one
  behavioural divergence (file-type tagging of `makefile.png`). It adds `repo: builtin` hooks
  implemented in Rust (offline), a workspace mode and `priority` scheduling. Upstream pre-commit does
  not read `prek.toml`; keep the YAML to stay portable. prek is pre-1.0 (0.5.x).
- **pre-commit needs Python >= 3.11** (`python_requires` in its `setup.cfg`). The zipapp
  (`pre-commit-#.#.#.pyz`) runs without pip, which matters on Debian where `python3 -m pip` is absent.
- **lefthook does not manage tools.** It is a scheduler plus file-glob templates (`{staged_files}`,
  `{all_files}`, `--all-files`). That is why it has no download problem and also no ecosystem of
  ready-made hooks. Shared configs come from `remotes:`, pinned by `ref`.
- **husky is a hook installer, not a runner.** Its docs tell you to write POSIX shell in
  `.husky/pre-commit`; lint-staged adds staged-file globbing and stash handling and is Node-only. For a
  repo with no `package.json` it adds a Node toolchain to run shell scripts.
- **mise and just do not replace a hook runner.** mise can generate a hook that runs one task with the
  staged names in `$STAGED`; it passes no other hook arguments for most hooks. just has no git
  integration. Both are good as the *thing a hook calls* so that local and CI run the same command
  (`mise run check` / `just check`). Their strength is task naming; neither filters files or runs
  tools per file type. jdx (the mise author) also ships `hk`, a hook manager (MIT, v2.8.1,
  2026-10-23); not examined further.
- **A `.pre-commit-config.yaml` plus `prek run --all-files` already is the "same command locally and
  in CI".** prek's CI page recommends exactly that because it "checks every tracked file instead of
  depending on a CI job's staging area". Lefthook offers `--all-files` too (docs/usage.md).

### Polyglot coverage: the tools the repo needs

| Tool | Ready-made hook | How it runs | Fit in the sandbox |
| --- | --- | --- | --- |
| shellcheck | `shellcheck-py/shellcheck-py` (MIT, `language: python`, PyPI wheel); `koalaman/shellcheck-precommit` (`language: docker_image`) | wheel from PyPI, or Docker | PyPI blocked, no Docker in the sandbox: use a `system` hook on an installed binary |
| ruff | `astral-sh/ruff-pre-commit` (Apache-2.0, v0.17.2, 2026-10-22, `language: python`) | wheel from PyPI | PyPI blocked (tested) |
| prettier | `pre-commit/mirrors-prettier` is archived (last push 2024-04-11); community `rbubley/mirrors-prettier` (MIT, 7 contributors, pushed 2026-10-11) | `language: node`, npm | npm registry is allowlisted |
| biome | `biomejs/pre-commit` (Apache-2.0, tag v2.6.3 follows biome 2.6.3, pushed 2026-10-25) | `language: node`, npm | npm allowlisted; this is the first-party option |
| tofu fmt / validate | `antonbabenko/pre-commit-terraform` (MIT, v1.109.3, 2026-10-20); OpenTofu via `--hook-config=--tf-path=tofu` or `PCT_TFPATH` | bash scripts; needs the binary, or downloads at `--tool-version` | needs `tofu` installed (release binaries have linux/darwin amd64+arm64) |
| kubeconform | none: the repo has no `.pre-commit-hooks.yaml` | `repo: local`, `language: system` | binary releases for linux/darwin amd64+arm64 (v0.8.0, 2026-06-04); default schemas are fetched from `raw.githubusercontent.com` (allowlisted); CRDs such as Flux's need extra `-schema-location` entries |
| gitleaks | official `gitleaks` (`language: golang`), `gitleaks-docker`, `gitleaks-system` | golang builds from source; system runs the installed binary | `golang` needs the Go toolchain and module proxy (not allowlisted): use `gitleaks-system` |

Sources: hook manifests read from each repository's `.pre-commit-hooks.yaml`; releases [16].

Reading the table: **the tools that are single binaries (shellcheck, tofu, kubeconform, gitleaks) are
best run as `language: system` hooks**, with the binary provisioned separately (mise with a lockfile,
the CI image, or the operator's package manager). Remote hooks only add value for ruff and
biome/prettier, where the hook repo pins the tool version for you. The shared
`pre-commit-hooks` (YAML check, trailing whitespace, large files, private keys) are what prek
reimplements as offline `repo: builtin` hooks.

This repo's own push protection and a pre-tool hook already cover secrets (CLAUDE.md); gitleaks
would be a second layer, not the first.

### Sandbox findings (tested 2026-10-25, prek 0.5.7, uv 0.13.5, lefthook 2.2.2)

The sandbox allows writes only to the working directory and `$TMPDIR`, and network to the allowlist.
Binaries came from GitHub releases (allowlisted) and passed their published checksum where one
exists.

| Test | Result |
| --- | --- |
| `prek run` with default cache | `failed to create directory /home/gaserban/.cache/prek: Read-only file system`. `PREK_HOME=$TMPDIR/...` fixes it |
| `prek install`, then `git commit` | writes `.git/hooks/pre-commit`; the shim hardcodes prek's absolute path and falls back to `PATH` |
| `prek run`, one `language: system` hook | passes, about 10 ms per run |
| `prek run` with `ruff-pre-commit`, no uv on `PATH` | prek tries `python3 -m pip install uv==0.13.4`: `No module named pip`; also denied: `releases.astral.sh`, `pypi.org` |
| same, with uv on `PATH` | fails fetching `https://pypi.org/simple/ruff/` (denied) |
| `lefthook install`, `git commit`, `run pre-commit --all-files` | works with no cache directory and no network; about 15 ms per run |
| `gh attestation verify` on the prek tarball | `no valid Sigstore verifiers could be initialized` (TUF fetch blocked); verify outside the sandbox |
| `uv run --script` with no dependencies and default cache | `Failed to initialize cache at /home/gaserban/.cache/uv`, exit code 2; `UV_CACHE_DIR` fixes it |
| `uv run --script` with a PyPI dependency | retries for 6.8 s, then fails on `pypi.org` (denied) |
| `prek run --hook-stage pre-push --from-ref A --to-ref B`, a `language: system` hook echoing the refs (#19) | the hook sees `PRE_COMMIT_FROM_REF=A` and `PRE_COMMIT_TO_REF=B`; without the flags both are unset, so `${PRE_COMMIT_FROM_REF:?}` fails closed |
| `types: [shell]` over an executable `#!/bin/bash` file, an executable `#!/usr/bin/env bash` file, a non-executable `#!/bin/bash` file, `plain.sh` (#19) | tagged: both executables (by shebang) and `plain.sh` (by extension); not tagged: the non-executable file with no extension. Every bash script tracked at #19 is executable or ends `.sh` |
| `prek run` with `.pre-commit-config.yaml` unstaged (#19) | refuses: "Configuration file ... is not staged"; `--all-files` does not check it |
| an `entry:` holding `: ` unquoted (#19) | YAML error "mapping values are not allowed"; quote the whole entry |
| gitleaks 8.30.1 `git` over a commit holding an AWS key, the key's fingerprint in the working tree's `.gitleaksignore` (#19) | exit 0 (silenced) with or without `-i <empty dir>`: gitleaks always reads `<source>/.gitleaksignore`; exit 1 once that file is removed |
| gitleaks 8.30.1, the source's `.gitleaks.toml` allowlisting the key's path (#19) | exit 0 (silenced) by default; exit 1 with `-c <file holding [extend] useDefault = true>`: `-c` replaces the source's config |
| gitleaks 8.30.1 `git --log-opts=A..B` over a merge commit whose conflict resolution adds an AWS key (#19) | exit 0 (missed: `git log -p` shows no merge diff); exit 1 with `--log-opts="--diff-merges=first-parent A..B"` |
| gitleaks 8.30.1 over a commit adding a key in `lock` and `.gitattributes` holding `lock -diff` (#19) | exit 0 from that checkout (missed: the file diffs as binary); exit 1 when the same range is scanned from `git worktree add --detach <dir> <base>`, which applies the base's attributes, ignore file and config |

Consequence: a git hook that runs inside the agent's sandbox can use only local tools plus whatever
the allowlist reaches. Either keep gates to `system` and `builtin` hooks (and npm-based ones), or add
`pypi.org` and `files.pythonhosted.org` to the allowlist (ADR 0014: "one line per tool"), or run the
gate in CI and the operator's shell only. Set `PREK_HOME` to a writable path in the hook's
environment.

### Known failure modes (git-hook managers)

- **Hooks are not in a fresh clone.** `pre-commit install`, `prek install`, `lefthook install` must run
  per clone (husky does it through `npm install`). A SessionStart hook can run the install; that is a
  cheap fix, and `prek install` honours `core.hooksPath`.
- **Bypass.** `git commit --no-verify`, and `SKIP=<id>` for pre-commit/prek (a documented feature).
- **Mutable pins.** A git tag can be moved; prek's security guide says a full SHA is the strongest pin
  and offers `prek update --freeze`; pre-commit has `autoupdate --freeze`. Branch names are not pins.
- **A hook config is executable code from the repo.** prek's security guide: installing the shim
  "authorizes the selected hooks, their installation steps, and their dependencies to execute with the
  current user's permissions". Review config changes in pull requests.
- **Per-hook environment setup.** The first run after a clone or a version bump downloads and builds
  environments: seconds to minutes, off the speed numbers (the prek benchmark excludes installation
  and network time). `language: golang` and `language: rust` hooks build from source.
- **Cache directory.** `~/.cache/pre-commit`, `~/.cache/prek`: not writable in this sandbox (tested).
  prek's CI guide warns that cache correctness depends on prek version, platform, config and hook
  revisions.
- **Partial staging.** Hooks that reformat can stage changes the author did not intend; lint-staged
  stashes unstaged changes for partially staged files by default; lefthook has `stage_fixed`.
- **Husky and GUIs.** Git GUIs do not load the shell setup that provides Node, so `command not found`;
  husky's fix is `~/.config/husky/init.sh`.
- **Maintainer concentration.** pre-commit (asottile 73 of the last 12 months' commits, next human 2),
  husky (typicode, 6 commits, docs only), lint-staged (iiroj 261, next 3).
- **`pre-commit/action` is in maintenance-only mode** (its README); the replacement for GitHub Actions
  is `j178/prek-action` (MIT, pushed 2026-10-21) or a plain `run` step.

### Adopt-or-build scores for (a)

"Maintainers" rule used here, since the checklist leaves "active" open: at least two non-bot authors
with 10 or more commits to the default branch in the last 12 months (commit counts from the GitHub
API, 2025-10-25 to 2026-10-25). Security: "none" means the repository lists no published GitHub
security advisory; Scorecard is cited where the API had one, else unverified.

| Tool | Maintained | Licence | Security | Maintainers | Images (release binaries) | Pinning | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pre-commit | pass, 2026-10-13 | MIT, pass | no advisory; Scorecard 4.5 (2026-10-19: Code-Review 0, Signed-Releases 0, Pinned-Dependencies 0) | fail: asottile 73, next 2 | pass: pure Python (PyPI, `.pyz` zipapp), no binary | pass: `rev` SHA, `--freeze` | fail on one line: single maintainer; the format outlives that |
| prek | pass, 2026-10-21 | MIT, pass | no advisory; artifacts carry GitHub attestations; Scorecard not available (404): unverified | pass: j178 825, shaanmajid 42 (dominant owner, lopsided) | pass: darwin and linux, aarch64 and x86_64 (gnu and musl) | pass: version-pinned installer URL, SHA hook pins, `--freeze`; toolchain downloads checksum-verified except uv | **adopt** (pre-1.0) |
| lefthook | pass, 2026-10-13 | MIT, pass | no advisory; Scorecard 5.3 (Code-Review 4, Branch-Protection 0, Signed-Releases 0) | pass: mrexox 123, scop 27 | pass: Linux x86_64 and arm64, macOS x86_64 and arm64 | pass: exact version; `remotes` `ref` | **runner-up** |
| husky | weak: last release 2024-11-18, only docs commits since; Scorecard Maintained 0 | MIT, pass | no advisory; Scorecard 4.7 | fail: typicode only | n/a (npm JS) | pass via lockfile | **fail**: Node-only and unmaintained in practice |
| lint-staged | pass, v17.6.0, 2026-09-26 | MIT, pass | no advisory; unverified | fail: iiroj 261, next 3 | n/a (npm JS) | pass via lockfile | not needed without husky; fail on maintainers |
| mise (tasks, tools) | pass, 2026-10-24 | MIT, pass | six high/medium advisories 2026-08 to 2026-10, all patched at or before 2026.10.0, latest is 2026.10.19; Scorecard unavailable: unverified | pass: jdx, risu729, others | pass: linux x64/arm64 (glibc and musl), macOS x64/arm64 | pass: `mise.lock`, `install --locked` | usable as the tool provisioner; not a hook layer |
| just | pass, 2026-10-15 | CC0-1.0 (public-domain dedication: not on the checklist's list, treat as permissive and say so) | no advisory; Scorecard 4.2 | fail: casey 473, next 7 | pass: linux musl x86_64/aarch64, macOS both | n/a: pins no tools | not a gate layer |

Tools the gates call, scored only on the lines that can decide an adoption:

| Tool | Maintained | Licence | Maintainers | Images |
| --- | --- | --- | --- | --- |
| ruff | 0.17.2, 2026-10-22 | MIT | Astral team | linux/darwin amd64+arm64: pass |
| biome | 2.6.3, 2026-10-24 | Apache-2.0 | many | pass |
| OpenTofu | v1.13.2, 2026-10-21; advisories all patched (latest high fixed in 1.12.3) | MPL-2.0 | many | pass |
| gitleaks | v8.30.1, 2026-03-21; commits to 2026-10-23 | MIT | fail by the rule: bryanbeverly 14, zricethezav 8 | pass: linux x64/arm64, darwin x64/arm64 |
| kubeconform | v0.8.0, 2026-06-04 | Apache-2.0 | fail: yannh 5 commits in 12 months | pass: linux and darwin, amd64 and arm64 |
| shellcheck | v0.11.0, 2025-08-04 (14 months, commits to 2026-10-19: pass) | **GPL-3.0**: fails the line mechanically; it is run, not linked, but this is the operator's call | pass: koalaman 60, e-kwsm 26 | pass: linux/darwin aarch64 and x86_64 |

None of these has an equivalent that passes every line, so the kubeconform, gitleaks and shellcheck
results are "adopt, with the flagged line accepted by the operator", not "build". Nobody builds a
schema validator or a secret scanner for a homelab.

### Verdict (a)

**Adopt prek**, configured through a `.pre-commit-config.yaml`:

1. Local hooks: `repo: local`, `language: system` for shellcheck, tofu, kubeconform, gitleaks, each
   calling a binary the operator or CI provisions. Add `repo: builtin` hooks for whitespace, YAML and
   private-key checks. No downloads, so they run inside the agent's sandbox.
2. Remote hooks (ruff, biome) only after `pypi.org` and `files.pythonhosted.org` are allowlisted, or
   run those two in CI only.
3. CI runs `prek run --all-files` through `j178/prek-action` (pinned by SHA, as prek's own CI guide
   shows), and the ruleset requires that check. That job is the gate; the local hook is feedback.
4. A SessionStart step installs the shim; set `PREK_HOME` to a writable path.

Runner-up: **lefthook**, if the operator prefers a 2.x tool with no environment manager at all. It
cannot consume pre-commit hooks, so the ruff/biome step becomes a hand-written `run:` line.
Reject: husky + lint-staged (Node-only, one maintainer, no release in 23 months). Not a hook layer:
mise and just; decide separately whether mise's `mise.lock` is the way to provision the system
binaries. This note does not find it necessary: it has had six advisories in two months, and a CI
image or plain release downloads pinned by hash do the same job.

## Part (b): repo automation scripts

### What the question reduces to

Typical script here: call `gh`/`git`/`podman`/`kubectl`, parse JSON, call the GitHub API, branch on
results, and be testable. Existing examples: `tools/setup-dev-runtime.sh` (402 lines),
`tools/hl-runtime` (90), `branch-cleanup.sh` (69, with associative arrays and `git worktree
--porcelain` parsing), `skills-restore.sh` (109, with an awk emulation of ICU collation).

### Comparison

| | bash | Python, stdlib only | Python, `uv run --script` + PEP 723 | Typer/Click package in a uv workspace | Go | TypeScript (Node, Bun, Deno) |
| --- | --- | --- | --- | --- | --- | --- |
| Calling `gh`/`git`/`podman`/`kubectl` | native | `subprocess.run([...], check=True)`, no quoting hazards | same | same | `os/exec` | `child_process` / `Bun.$` / `Deno.Command` |
| JSON | needs jq (or `gh --jq`) | `json` | `json` | `json` | `encoding/json` | native |
| GitHub API | `gh api` | `gh api` via subprocess, or `urllib` | `gh api`, or `httpx` | same | `go-gh` or `net/http` | `fetch` |
| Tests | hand-rolled (`test.sh`: 67 cases through jq-built payloads); bats exists, not in the repo | `unittest`, table-driven | `unittest`; pytest is a dependency | pytest, Typer's runner | `go test`, built in | `node --test`, `bun test`, `deno test` |
| Startup (measured, warm) | 3 ms | 15 ms | 25 ms (one cold run 55 ms) | project sync check each `uv run`, not measured | compiled binary: ms; `go run` compiles | Bun 5.2 ms vs Node 25.1 ms on `hello.js` (Bun docs, Linux) |
| Dependency pinning | none, whatever is on `PATH` | none needed | `uv lock --script` writes `<script>.lock`; `[tool.uv] exclude-newer` bounds the resolver by date; otherwise floating | `uv.lock`, one lock per workspace | `go.mod` + `go.sum` checksums | `deno.lock` / `bun.lock` / `package-lock.json` |
| Needs on the box | bash, jq | python3 (here: 3.13.5) | uv, network or a warm cache, PyPI | uv, PyPI, `[project.scripts]` | Go toolchain | a runtime not installed here |
| Readable by an agent | weakest past ~100 lines: quoting, `set -u` traps, arrays as maps | strong: types, structured errors, one obvious way | same as stdlib | strongest for many subcommands, heaviest to set up | strong, verbose | strong; `node` strips types only (no checking) |

Sources: [11], [12], [13], [14], [15]; measurements under "Startup".

### Is Python through uv the established choice over bash?

Evidence for "established, in the right place":

- PEP 723 is Final (created 2023-08-04, resolved 2024-01-08) and now lives in the PyPA spec; Pantsbuild,
  Pex, Hatch, Mypy and Ruff were listed as supporters when it was written; uv implements it,
  including `uv add --script`, `uv lock --script`, a `#!/usr/bin/env -S uv run --script` shebang and
  automatic Python download.
- uv is a maintained Apache-2.0 tool (v0.13.5, 2026-10-22; many active maintainers; release binaries for
  linux/darwin amd64+arm64).
- Google's shell style guide, a primary statement of the other side: shell "should only be used for
  small utilities or simple wrapper scripts"; past 100 lines or "non-straightforward control flow",
  rewrite early in a more structured language.

Evidence against "the replacement here":

- The PEP's own limits: no hash pinning is specified, reproducibility is up to the runner, an
  untrusted script can pull a malicious dependency, and `requires-python` is only "should error".
  uv's `dependencies` key "must be provided even if empty".
- uv adds a dependency on a tool that is not installed, and in this sandbox on PyPI (tested).
- PEP 723 is only needed for third-party packages. The scripts listed above need none; stdlib Python
  gets structured JSON, subprocess without quoting, `shlex`, `argparse` subcommands and `unittest`
  with the Python already installed. uv would add a download, a cache directory and a lock file
  to solve a problem the scripts do not have.
- PEP 723 gives a self-describing single file, not a tested package: the "testability" gain comes
  from Python, not from PEP 723.

So: **Python is the established step up from bash; uv + PEP 723 is the established way to give a
Python script dependencies; neither is a reason to rewrite working short bash.** The two earn their
place at different thresholds.

### Failure modes (Python through uv, PEP 723)

1. **Floating dependencies.** No lock by default; `uv lock --script` is an explicit step and the
   lockfile sits next to the script. Without it, a script that worked last month resolves differently.
   `exclude-newer` is the cheap bound.
2. **Network at first run.** A cold cache needs the index; here, PyPI is blocked and the failure costs
   about 7 s of retries before the error.
3. **Cache location.** `~/.cache/uv` is read-only in the sandbox: `uv` exits 2. Set `UV_CACHE_DIR`.
   Note that exit code 2 is also Claude Code's "block" code (see below).
4. **Python download.** If no matching interpreter exists, `uv run` downloads one (uv docs);
   `UV_PYTHON_DOWNLOADS=never` makes it fail instead. Here the system 3.13 satisfies `>=3.12`.
5. **Project vs script.** `uv run <file>` inside a project syncs the project environment first (uv
   docs: "ensure that the project environment is up-to-date before running"); scripts carrying inline
   metadata are isolated from the project. A script without a metadata block is not.
6. **The tool is itself a supply-chain input.** uv has six published advisories, the newest high
   severity published 2026-10-20 and patched in 0.13.4. Pin the uv version in whatever installs it.
7. **Shebang portability.** `env -S` is needed for `uv run --script` in a shebang; fine on Debian 13,
   not on every system.
8. **Fail-open on exceptions in hooks** (below).
9. **A Typer/Click package** adds a build backend, an entry point, and a lock to keep fresh. Typer is
   MIT (0.27.3, 2026-10-06; tiangolo 98, svlandeg 37, YuriiMotov 22 commits in 12 months) and, since
   0.26.0, bundles Click's source rather than depending on it; Rich is a required dependency;
   `typer-slim` is now a synonym. A uv workspace shares one lockfile and one `requires-python` across
   members (uv docs) and is meant for "multiple interconnected packages", which this repo does not
   have.

### Go and TypeScript, briefly

- **Go** gives a static binary, `go test` and checksum-verified modules (`go.sum`), and `os/exec` is
  fine for `gh`/`kubectl`. Costs: a toolchain this box lacks, `proxy.golang.org` not on the allowlist,
  and a compile step in an agent loop. A fit if a script becomes a long-lived tool; not for glue.
  (Go release binaries and maintainers were not re-checked here.)
- **TypeScript.** Node strips types and runs `.ts` files (stable since v25.2.0 and v24.12.0; erasable
  syntax only, no type checking, `tsconfig.json` ignored). Deno is secure by default with scoped
  `--allow-*` flags (but `--allow-run`, which shelling out to `gh` needs, "should be treated as equivalent to
  `--allow-all`"). Bun auto-installs missing packages when there is no `node_modules`. Deno
  (v2.9.8, MIT) and Bun (v1.4.4, licence `NOASSERTION` in the API, MIT with bundled third-party code)
  both ship linux/darwin x64+arm64 binaries and are active. None is installed here, and npm is the only
  registry already allowlisted. The gain over Python is nil for this repo's work.

### Startup measurements (local, 2026-10-25, WSL2, 12 cores, Python 3.13.5, uv 0.13.5)

A hook-shaped script: read a PreToolUse JSON from stdin, exit 2 if the command contains a string.
Average of 30 runs after one warmup; `bash -c true` is the floor.

| Variant | Average |
| --- | --- |
| `bash -c true` | 1 ms |
| bash + `jq` | 3 ms |
| `python3 h.py` (stdlib) | 15 ms |
| `python3 -I -S h.py` | 13 ms |
| `uv run --script` (PEP 723 block, empty dependency list, warm cache) | 25 ms |
| the same with `--offline --no-config` | 24 ms |
| `uv run --script`, one run on an empty cache | 55 ms |
| `prek run`, one local system hook | about 10 ms |
| `lefthook run pre-commit --all-files`, two jobs | about 15 ms |

A script with a real dependency was not timed: the index is unreachable from the sandbox. A
project-mode `uv run` (with the sync check) was not timed.

## Claude Code hooks

### What the docs require

From [1], [2], [3], all fetched 2026-10-25:

- **Any executable works.** In shell form, `command` is a shell string (`sh -c` on Linux and macOS, or
  `shell: "bash"`). In exec form (`args` set), `command` is "resolved as an executable on `PATH`" and
  spawned with no shell, so `"command": "uv", "args": ["run", "--script", ".claude/hooks/x.py"]` is
  legal. The guide says: "If you see 'jq: command not found', install `jq` or use Python/Node.js for
  JSON parsing". Scripts must be executable (`chmod +x`) when invoked by path.
- **Input is JSON on stdin**, with common fields (`session_id`, `transcript_path`, `cwd`,
  `permission_mode`, `hook_event_name`) plus event fields; PreToolUse adds `tool_name`, `tool_input`,
  `tool_use_id`.
- **Exit codes.** 0: proceed; stdout is parsed as JSON if it starts with `{`, and SessionStart stdout is
  added as context. 2: block (PreToolUse: stderr is the denial reason shown to Claude; SessionStart:
  stderr to the user only, nothing blocked). Any other code: non-blocking error, the action goes ahead.
  JSON on stdout with `permissionDecision` (`allow`, `deny`, `ask`, `defer`) and `updatedInput` is the
  richer interface; precedence `deny > defer > ask > allow`.
- **Timeouts.** `timeout` in seconds per hook; default 600 for `command`, `http`, `mcp_tool` (30 s for
  UserPromptSubmit and two model-switch events, 10 s for MessageDisplay, 1.5 s shared for SessionEnd).
  What a timed-out PreToolUse command hook does was not found in the pages read.
- **Parallel.** "When an event fires, its matching hooks run in parallel." So the latency a Bash call
  pays is the slowest matching hook.
- **SessionStart "runs on every session, so keep these hooks fast."** It accepts only `command` and
  `mcp_tool` hooks.
- **`if`** (permission-rule syntax such as `Bash(gh issue *)`) is evaluated only on tool events, so
  `issue-template.sh` runs only for `gh issue` commands.
- **Hooks run outside the sandbox with full access** [3]; git hooks started by a Bash command do not.
- **Shell profile output** ahead of the JSON (an `echo` in `.bashrc` reached through `BASH_ENV`) makes
  Claude Code ignore the JSON silently, with exit 0 (the guide's debugging section). Exec form avoids
  the shell.
- **Not covered by the docs:** a documented startup budget for tool-call hooks. The only stated limits
  are the timeouts above.

### Does `uv run` startup matter at every tool call?

No, by measurement, with three conditions:

1. The cost is 10 to 22 ms over bash per process, and hooks on one event run in parallel, so a Bash
   call pays the slowest hook, not the sum. Model latency per tool call is orders of magnitude larger.
2. Keep dependencies empty. A warm cache is 25 ms; an empty cache with no dependencies measured 55 ms;
   a dependency that needs the index would add the network to a path that runs on every Bash call.
   If a hook needs a package, vendor it or use the stdlib.
3. A hook that cannot start must not become a silent hole. Exit codes decide: uv's own errors exited
   2 in the cache test, which makes a broken uv install block every Bash call loudly (fail closed,
   noisy). A Python traceback exits 1, which lets the call through (fail open). Wrap `main()` so any
   exception exits 2 for guards and exits 1 plus a message for the SessionStart hooks that must never
   block.

For hot-path hooks plain `python3` (no uv) is the cheaper choice (15 ms vs 25 ms, no cache, no
network, nothing to install). uv earns its place only for a script with dependencies.

### The six scripts, and which would gain from a rewrite

Registrations: SessionStart runs `token-refresh.sh`, `skills-restore.sh`, `branch-cleanup.sh`;
PreToolUse (Bash) runs `git-guard.sh`, `token-refresh.sh`, and `issue-template.sh` when the command
matches `Bash(gh issue *)`; PreToolUse (Agent) runs `flow-review-bound.sh`. `test.sh` (260 lines,
67 cases) exercises all of them.

| Script | Lines | When it runs | What is hard in bash today | Gain from Python |
| --- | --- | --- | --- | --- |
| `skills-restore.sh` | 109 | SessionStart, cache-first | an awk emulation of ICU collation (`icu_sort`), a hand-built hash over paths and contents in two variants, `\x1f`-separated fields to survive `read`, sparse blobless clones | **High.** `hashlib`, `pathlib`, `json`, `subprocess`, `tempfile`. One catch: Python's stdlib has no ICU collation; the hash must equal the Node skills CLI's, whose sort is `localeCompare`, so an exact port needs the same ordering (a Python port would keep the table-driven emulation, but readable and unit-testable). Runs once per session; startup is irrelevant |
| `issue-template.sh` | 63 | only on `gh issue ...` | parses a shell command line with sed, awk (heredoc stripping) and regexes; extracts `--body-file` with a 3-way sed; segment-splitting on `;&|(` | **High.** `shlex` plus a small heredoc scanner is shorter and testable; runs rarely, so startup is irrelevant. The existing 22 cases in `test.sh` port directly |
| `git-guard.sh` | 33 | every Bash call | a regex deny-list over the raw command string (the hook's own comment records one earlier false positive from sed over the JSON) | **Medium.** Tokenising with `shlex` removes the `[^;&|]*` regex tricks and the false-positive class, and the case table becomes data. Hot path: +12 ms and the fail-open rule above. Regex deny-lists stay bypassable in either language (`bash -c`, aliases); the CI gate and the ruleset are the real guard |
| `flow-review-bound.sh` | 42 | only Agent launches; exits early unless the payload mentions `hl-plan-reviewer` | `jq` read-modify-write on a state file under `flock` | **Low to medium.** `json` and `fcntl.flock` are cleaner and drop the jq dependency; low frequency |
| `branch-cleanup.sh` | 69 | SessionStart | associative arrays, `git worktree list --porcelain` parsing, `gh --jq` string pipes | **Medium.** It is git plumbing where bash is natural; Python would make the merged-branch decision a testable function. Do not rewrite for its own sake |
| `token-refresh.sh` | 24 | SessionStart and every Bash PreToolUse | nothing: a stat, a grep, a call to the helper | **None.** Hot path, shortest, clear; a rewrite adds 12 to 22 ms per Bash call and risks fail-open |
| `test.sh` | 260 | by hand | jq-built payloads; a mini harness (`t`, `r`, `a`) | follows the hooks: if two or three hooks move, table-driven `unittest` replaces the harness; the rest keep it |

Independent of language: **none of this bash is linted.** No shellcheck is installed and there is no CI
(`test.sh` is the only check). Adding shellcheck as a gate (part a) is cheaper than any rewrite, and
the repo's bash line count (about 1,100 across `.claude/hooks` and `tools`) stays modest.

Dependencies that drop with a Python rewrite: `jq` (docs/operator-setup.md section 3 requires it, and
three hooks fail closed without it) and the `sha256sum`/`awk`/`sed` quirks.

## Verdicts

### (a) Gates

**Adopt prek** with a `.pre-commit-config.yaml`; `system` hooks for the single-binary tools; CI runs
`prek run --all-files` as the required check. Details and the sandbox constraints are under "Verdict
(a)". Lefthook is the acceptable alternative; husky + lint-staged is rejected; mise and just are
task runners, optional.

### (b) Automation

1. **Do not adopt uv + PEP 723 as the default replacement for bash now.** Set the rule at the
   threshold instead: bash for glue up to roughly 30 lines (`token-refresh.sh`, `tools/gh`,
   `git-credential-homelab-app`); stdlib-only `python3` for anything with parsing, JSON, state or
   more than about 100 lines (Google's threshold); `unittest` for tests.
2. **Add uv and PEP 723 when the first script needs a package**, and then: pin uv by version and
   hash from its GitHub release, set `UV_CACHE_DIR`, allowlist `pypi.org` and
   `files.pythonhosted.org`, `uv lock --script` and `exclude-newer`.
3. **Typer/Click in a uv workspace: not yet.** Revisit when the repo has one CLI with several
   subcommands that share code; `argparse` subparsers cover it until then.
4. **Go and TypeScript: no.** Nothing in this repo's automation needs them.
5. **Claude Code hooks:** rewrite `skills-restore.sh` and `issue-template.sh` in stdlib Python first
   (largest gain, off the hot path), then consider `git-guard.sh`; keep `token-refresh.sh`,
   `branch-cleanup.sh` and `flow-review-bound.sh` in bash unless they grow. Every Python guard needs
   a top-level handler that exits 2. These are candidate follow-up issues, not decisions: ADR 0014
   fixes hooks as the enforcement mechanism, not the language.

## Not verified

- prek's, uv's and mise's OpenSSF Scorecard (API returned 404): security lines are "no published
  advisory", not an audit. No published advisory means the repository's advisory list was empty;
  repositories can omit advisories.
- Maintainer counts are commits to the default branch by login over 12 months, bots excluded; they say
  nothing about who holds merge rights. prek's `shaanmajid` (42) and lefthook's `scop` (27) are counted
  as second maintainers by that rule.
- prek's and lefthook's published numbers and the benchmark are the vendors' own; the prek benchmark
  ran on macOS with 960 files. No pre-commit run was made here.
- Whether a PreToolUse command hook that times out blocks or lets the call through: not stated in
  the parts of the hooks reference read (about 200 of 282 thousand characters); the guide says a
  Windows hook that failed to start "blocked the tool call".
- Go and Node release binaries and maintainers; Go's module proxy status under the sandbox allowlist
  (inferred from the allowlist text, not run).
- A pip-free `pre-commit` run with the `.pyz` zipapp; `shellcheck`, `tofu`, `kubeconform`, `gitleaks`
  and `mise` were not installed or run here. kubeconform with Flux CRDs needs schema locations this
  note did not look up.
- The prek attestation could not be verified inside the sandbox (Sigstore trust root fetch blocked);
  the uv tarball matched its published SHA-256.
- Scorecard Maintained for husky is 0 on the 2026-10-19 report; the husky commit count is from the API.

## Sources

Fetched 2026-10-25 unless noted.

1. Claude Code hooks reference: https://code.claude.com/docs/en/hooks (first 200,000 of 282,268 characters)
2. Claude Code hooks guide: https://code.claude.com/docs/en/hooks-guide
3. Claude Code sandboxing: https://code.claude.com/docs/en/sandboxing
4. pre-commit: https://pre-commit.com/ (v4.7.0 shown); source pages in https://github.com/pre-commit/pre-commit.com (`sections/cli.md`, `sections/advanced.md`); `setup.cfg` in https://github.com/pre-commit/pre-commit; https://github.com/pre-commit/action (README)
5. prek: https://github.com/j178/prek and https://prek.j178.dev/ (installation, benchmark dated 2026-10-05, differences); `docs/ci.md`, `docs/security.md`, `docs/compatibility.md`, `docs/reference/language-support.md` read from the repository
6. lefthook: https://lefthook.dev/ ; `docs/index.md`, `docs/usage.md`, `docs/configuration/remotes.md`, `docs/installation/node.md` in https://github.com/evilmartians/lefthook
7. husky: https://typicode.github.io/husky/get-started.html and `/how-to.html`
8. lint-staged: https://github.com/lint-staged/lint-staged
9. mise: https://mise.jdx.dev/tasks/ ; `docs/continuous-integration.md`, `docs/security.md`, `docs/dev-tools/mise-lock.md`, `docs/cli/generate/git-pre-commit.md` in https://github.com/jdx/mise
10. just: https://just.systems/man/en/
11. uv scripts, workspaces, projects run: https://docs.astral.sh/uv/guides/scripts/ , https://docs.astral.sh/uv/concepts/projects/workspaces/ , https://docs.astral.sh/uv/concepts/projects/run/
12. PEP 723: https://peps.python.org/pep-0723/ (Final; resolved 2024-01-08)
13. Google Shell Style Guide: https://google.github.io/styleguide/shellguide.html
14. Typer: https://typer.tiangolo.com/
15. Deno security: https://docs.deno.com/runtime/fundamentals/security/ ; Node type stripping: https://nodejs.org/api/typescript.html ; Bun: https://bun.com/docs/runtime ; Go modules: https://go.dev/doc/modules/managing-dependencies ; gh formatting: https://cli.github.com/manual/gh_help_formatting
16. GitHub API (`gh api repos/<owner>/<repo>`, `/releases/latest`, `/commits?since=2025-10-25`, `/contributors`, `/security-advisories`) for pre-commit, prek, lefthook, husky, lint-staged, mise, just, hk, uv, Typer, Click, shellcheck, ruff, biome, OpenTofu, kubeconform, gitleaks, Deno, Bun and the hook repositories named above; hook manifests from each `.pre-commit-hooks.yaml`
17. OpenSSF Scorecard API: https://api.securityscorecards.dev/projects/github.com/<owner>/<repo> (pre-commit, lefthook, husky, just returned; prek, uv, mise returned 404)
18. Local experiments in the sandbox, 2026-10-25: prek 0.5.7 (musl), uv 0.13.5, lefthook 2.2.2, from GitHub releases into the session scratchpad; this repo's `.claude/settings.json`, `.claude/hooks/*`, `tools/*`
