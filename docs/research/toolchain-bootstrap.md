# One command that installs every pinned toolchain

Checked 2026-10-25. Sources are each project's own documentation, source and registry files, read
through the GitHub API as the homelab App and through the fetch tool; release, advisory and commit
data from the GitHub API; the OpenSSF Scorecard API where a project has an entry. Facts marked
"tested" come from commands run in this sandbox today. Facts marked "inference" are mine, not a
source's. Where a page did not say something, the note says "not stated" instead of filling it in.

Question, from the operator: how do polyglot repos give a contributor one command that installs
every toolchain and dependency, pinned, on Linux, macOS, Windows through WSL2 and possibly native
Windows; what is the established pattern; what are its failure modes. Context: solo-operator public
repo, WSL2 Debian 13 workstation, Claude Code in a bubblewrap sandbox without sudo and with a domain
allowlist. Tools needed soon: node, pnpm, python, uv, opentofu, kubectl, kind, flux, helm, and podman
(a privileged system package, [ADR 0018](../adr/0018-dev-runtime-user-and-sandbox-tunnel.md)).

Related notes: [gates-and-repo-tooling.md](gates-and-repo-tooling.md) already uses mise as the
provisioner for hook tools; [monorepo-build-tool.md](monorepo-build-tool.md) found Bazel's own
sandbox cannot start inside the Claude Code sandbox (tested there) and chose go-task as the entry
point. This note answers the layer beneath both: where the binaries come from.

## Short answer

- **The established pattern has four parts, and none of the candidates does all four.** (1) A
  committed file that pins each tool's version (`mise.toml`, `.tool-versions`, `.prototools`,
  `aqua.yaml`, `devbox.json`, `flake.nix`, `.bazelversion`). (2) A lockfile that adds per-platform
  checksums (`mise.lock`, `aqua-checksums.json`, `.protolock`, `flake.lock`, `devbox.lock`,
  `MODULE.bazel.lock`). (3) One idempotent command that reads both and installs into the user's
  home, with no root. (4) A normalised entry script, GitHub's "scripts to rule them all"
  (`script/bootstrap`, `script/setup`), which exists so "contributors only need to know the
  pattern, not a deep knowledge of the application". Application dependencies (`pnpm-lock.yaml`,
  `uv.lock`) stay in their own ecosystem lockfiles; mise's docs say its lockfile "covers tools only".
  Privileged system packages stay outside all of it, as a documented one-time operator step. The
  repo already has that shape: [operator-setup.md](../operator-setup.md) is the system layer.
- **Adoption counts, GitHub code search on 2026-10-25 (order of magnitude only; the API's totals are
  approximate):** `filename:.tool-versions` 33,152 files and `filename:mise.toml` 33,920;
  `filename:flake.lock` 93,184; `filename:devcontainer.json path:.devcontainer` 205,568;
  `filename:devbox.json` 5,120; `filename:.bazelversion` 4,608; `filename:aqua.yaml` 1,388;
  `filename:.prototools` 790. No source states what small polyglot repos choose; this is the only
  measure I found.
- **Verdict: adopt mise, with the aqua backend, a committed `mise.lock`, and a committed `bin/mise`
  launcher.** It is the only candidate that covers all but one of the ten tools from release
  binaries, runs without root, runs on native Windows, has a first-party "install myself" launcher
  generator, and passes the adopt-or-build checklist (Scorecard unverified, which the checklist
  allows). Podman stays a system package. Fall back to plain aqua if mise's advisory cadence or its
  one-dominant-maintainer risk becomes a problem; aqua shares the registry and has an explicit
  committed checksum file, but no runtimes, tasks or launcher.
- **Nix flakes, devbox and devenv fail the licence line (Nix is LGPL-2.1) and, more practically,
  need `/nix` created with root and `cache.nixos.org`.** proto fails the maintainers line and has no
  kind and only individually maintained plugins for kubectl, helm, flux and tofu. asdf fails the
  maintainers line, has no lockfile and no checksum checks in core, and compiles Python (needs
  build packages from apt, which needs sudo). Devcontainers and Bazel pass the checklist but solve a
  different problem: devcontainers need a container runtime on the host, and Bazel means adopting a
  build system.
- **In this sandbox mise does not work out of the box (tested).** `kubectl` and `helm` installed
  because their aqua entries download from `dl.k8s.io` and `get.helm.sh`, which are allowlisted. Every
  tool whose recipe reads GitHub release metadata (pnpm, uv, opentofu, kind, flux2) failed: mise asks
  `mise-versions.jdx.dev` first (not allowlisted), falls back to `api.github.com`, and the anonymous
  limit of 60 requests an hour was already spent (partly by my own earlier unauthenticated calls
  from the same address, so the failure of the fallback is not clean evidence; the denial of
  `mise-versions.jdx.dev` is). `node` needs `nodejs.org` and `python` needs
  `mise-versions.jdx.dev`; neither is allowlisted. One setting fixes the GitHub-hosted tools (tested: `use_versions_host = false`); Node needs one new
  host and Python another owner (see "Verdict").
- **Native Windows is the weak leg for this repo, not for mise.** Every CLI in the list ships a
  Windows binary except `kind` for Windows on ARM, and mise runs natively there. But the repo's
  hooks are bash, Claude Code's `CLAUDE_ENV_FILE` is not given to PowerShell hooks, and the dev loop
  needs a Linux container runtime that native Windows reaches only through a VM. Treat WSL2 as the
  supported Windows path and native Windows as installs-the-CLIs-only unless the operator decides
  otherwise (an ADR question, not a research one).

## What was tested in this sandbox

Method: mise v2026.10.19 (`linux-x64`, SHA-256 checked against the release's `SHASUMS256.txt`)
unpacked into the session scratchpad; `HOME` and the XDG directories pointed at the scratchpad so
nothing touched the operator's home; a scratch `mise.toml` pinning node 24.11.0, pnpm 10.20.0,
python 3.13.5, uv 0.9.5, opentofu 1.10.6, kubectl 1.34.1, kind 0.30.0, flux2 2.7.0 and helm 3.19.0;
`mise install` under the repo's real allowlist. No allowlist entry was added and no token was
given to mise on the first run.

| Observation | Evidence |
| --- | --- |
| Even `mise --version` calls `mise.jdx.dev/releases.tsv` | three retries, then a sandbox denial for `mise.jdx.dev:443` |
| kubectl and helm installed | their aqua recipes are `type: http` on `dl.k8s.io` and `get.helm.sh`, both allowlisted |
| pnpm, uv, opentofu, kind, flux2 failed after about 50 s each (the whole run took 142 s) | "failed to read GitHub release ... from mise-versions.jdx.dev ... and from api.github.com after it"; the API answered 403 with "API rate limit exceeded" (60 per hour, unauthenticated, shared by the egress address; I had spent part of it before the run) |
| node failed | `mise-versions.jdx.dev/data/node.toml`, then `nodejs.org/dist/index.json`, both denied |
| python failed | its build list comes from `mise-versions.jdx.dev` (the python page says the install needs it) |
| The error names its own fix | "set use_versions_host = false to ask api.github.com directly" |

### Second run, after the anonymous GitHub budget reset

Same scratch project minus node and python (the two that need hosts that stay blocked), with
`MISE_USE_VERSIONS_HOST=0` and `MISE_CHECK_UPDATE=0`, no token, same allowlist:

| Step | Result |
| --- | --- |
| `mise install` | kind, uv, opentofu, flux2 and pnpm downloaded from `github.com` and installed in 5.5 s after "fetching from api.github.com"; kubectl and helm were already installed; 7 of 7 in 18 s |
| Versions | kubectl v1.34.1, helm v3.19.0, kind 0.30.0, flux 2.7.0, OpenTofu v1.10.6, uv 0.9.5, pnpm 10.20.0, all as pinned |
| Idempotent rerun | "installed 0 tools, 7 already installed in 3ms" |
| `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64,windows-x64` | 35 targets checked; `mise.lock` (format `lockfile_version = 3`) holds a `sha256:` checksum and a URL for all 35; no `provenance` entries were recorded for these tools |
| Non-interactive shell, `env -i` with only the shims directory on PATH | `kubectl` resolved to the shim and ran (offline mode, already installed) |

So the metadata host is the only blocker for the GitHub-hosted tools, and turning it off fixes it
without adding a host or a token, as long as the 60-per-hour anonymous budget lasts (this run used
well under it). The budget is per egress address, so a shared network or a repeated first install
can exhaust it, which is the case for the optional no-scope token. Node and Python were not retested. Whether
mise still contacts `mise.jdx.dev` with `MISE_CHECK_UPDATE=0` was not separated out.

## The pattern in practice, and where it breaks

Ordered by how much damage each did in the sources.

1. **Prompt-hook activation does not reach an agent's shell.** `mise activate` "adds a hook that
   updates tools and environment variables on each prompt and directory change", so a shell that
   never shows a prompt never fires it. mise says scripts and CI "don't need it and should use `mise
   exec` and `mise run`", and offers shims for "programs that never start an activated shell". Claude
   Code's own page says each Bash command is "a separate process", that environment variables do not
   persist, and that at session start it sources `~/.bashrc` or `~/.profile` and captures "aliases,
   functions, and shell options" (it does not say PATH). Two documented ways to get tools onto the
   agent's PATH: a SessionStart hook that appends `export PATH=...` lines to `$CLAUDE_ENV_FILE`
   (Claude Code runs the file before every Bash command; SessionStart, Setup, CwdChanged and
   FileChanged hooks may write it), or shims on PATH before `claude` starts. This repo already runs
   SessionStart hooks (`token-refresh.sh`, `skills-restore.sh`), so a third one is in keeping with
   [ADR 0017](../adr/0017-downloaded-skills-restored-not-committed.md). I did not test either route
   end to end.
2. **Metadata hosts and rate limits, not the binary hosts, are what break in a filtered network.**
   Tested above. mise's `use_versions_host` default sends version lists, GitHub release data and
   attestation answers through `mise-versions.jdx.dev`, and "anything the host answers is trusted,
   including a `404`". That is a third party, run by the mise author, inside the trust path; it also
   receives opt-in download statistics (`GET https://mise-versions.jdx.dev/t`). Turning it off sends
   everything to `api.github.com`, which needs a token to avoid the anonymous limit. mise's token
   order is `MISE_GITHUB_TOKEN`, `GITHUB_API_TOKEN`, `GITHUB_TOKEN`, a credential command, `gh`'s
   `hosts.yml`, then `git credential fill`; it does not run `gh auth token` unless a
   `credential_command` says so. Do not hand mise the App token (Contents write): two 2026
   advisories (GHSA-333c-h2jr-xv83, GHSA-wcqh-j26q-g44x) were `GITHUB_TOKEN` leaks to
   project-controlled hosts. Public releases need a token with no scopes, only to lift the rate limit.
3. **The project config is code, and trust has had holes.** mise's trust page: only `[tools]` with
   plain versions and simple `[tasks]` load without trust; `[env]`, `[hooks]`, `[settings]`,
   `include` and tool option tables need `mise trust`; "in CI, every config is treated as trusted".
   The getting-started page says running `mise install`, `mise exec` or `mise run` in a project
   marks it trusted. In a repo that takes pull requests, a changed `mise.toml` therefore runs on the
   next contributor's machine. The advisory list shows the boundary has been breached repeatedly
   (next section). Mitigation: keep `mise.toml` to `[tools]` and `[tasks]`, and review any change to
   it as executable.
4. **A lockfile is per platform, and strict mode fails where an entry is missing.** `mise install
   --locked` "fails when a tool has no matching lockfile entry, including a missing URL for the
   current platform". So the file must be generated for every platform contributors use
   (`mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64,windows-x64`) and regenerated
   on every bump. Other documented limits: tools only, not application dependencies; a locked
   install "is not offline"; `.tool-versions` entries are not locked; a `provenance` field "does not
   prove mise verified the bytes"; locked versions install even when newer than
   `minimum_release_age`; the lockfile is itself a trust input "so review changes to it".
5. **Two managers for one tool.** mise's python page: "uv may download its own Python. Set
   `UV_PYTHON` to `{{ tools.python.path }}` to make uv use mise's interpreter". With uv and mise
   both able to supply Python and uv by default downloading when needed (`python-downloads` is
   `automatic`), a repo needs one owner for the interpreter. Inference: simplest is uv owns Python
   (`.python-version`, `uv python install`) and mise owns everything else.
6. **Source builds sneak in.** mise and asdf both fall back to compiling Python or Node where no
   prebuilt exists (mise on Alpine and NixOS by default, "deprecated" and due to switch in 2027.8.0).
   asdf-python always builds through pyenv's `python-build` and tells the user to install "the
   required system dependencies" first, which on Debian is `sudo apt install`.
7. **Deprecation churn in the manager.** mise's own pages announce removals: the `ubi` backend (gone
   in 2027.1.0), `uv_venv_auto = true` (2027.7.0), `aqua.registry_url` (2027.12.0), `generate
   bootstrap` as an alias (2027.9.0). Pin the mise version in the launcher and read the changelog on
   each bump.
8. **Shims on Windows copy, and drift.** Shims there are copies of `mise-shim.exe`; if an update
   replaces `mise.exe` but leaves an older shim, `mise doctor` reports it and `mise reshim --force` is
   needed. GUI editors ignore `$PROFILE`.
9. **`curl | sh` as the bootstrap.** Every candidate's documented first command is a piped
   installer. aqua's own page calls the one-liner risky because the installer "may be tampered" and
   recommends downloading it and checking its SHA-256 first. mise's answer, `mise generate
   install-script`, commits the installer into the repo (see mise below).

## Candidate by candidate

All dates are 2026 unless stated. "Windows" means native Windows, separately from WSL2, which every
candidate treats as Linux.

### mise (formerly rtx)

- **Release and licence.** v2026.10.19 published 2026-10-24; MIT.
- **OS.** Linux (x64, arm64, armv7, glibc and musl), macOS (x64, arm64). WSL2 is Linux. Windows:
  native, x64 and arm64 `.exe`, install by `winget install jdx.mise`, `irm https://mise.run/powershell
  | iex` (no admin rights; checks the zip against `SHASUMS256.txt`), Scoop, Chocolatey, or the zip.
  The aqua backend "works on Windows"; the asdf backend never runs there; core Python is
  precompiled only on Windows.
- **Idempotent.** `mise install` installs what is missing. `mise bootstrap`, the newer machine-setup
  command, states "parts that already match the config are left alone, but hooks and the `bootstrap`
  task run every time". Tested rerun: see "Second run".
- **Root.** No for the binary and tools (`~/.local/bin/mise`, data under `~/.local/share/mise`). The
  apt and dnf routes use sudo. `mise bootstrap packages` can run `apt-get` and "uses sudo when mise
  is not running as root", so it could install podman; it is young (the changelog shows heavy
  churn in the last two weeks), so I would not depend on it.
- **Activation.** PATH hook (`mise activate`), shims, or neither (`mise exec -- cmd`, `mise run`).
  Shims run the version the current directory selects, load `[env]`, and auto-install a missing tool
  unless `not_found_auto_install` is off. The shims page says it "doesn't address AI agents
  specifically, but the same approach applies to any non-shell caller".
- **Pinning.** Exact versions in `mise.toml` (prefixes like `"24"` are also allowed, so write exact
  ones). `mise.lock` records versions, URLs, per-platform checksums and provenance; `--locked` or
  `MISE_LOCKED=1` enforces; for npm and PyPI tools, format v2 adds a digest of the dependency graph.
  Default `minimum_release_age` 24 hours. The settings file does not label `lockfile` experimental.
- **Supply chain.** Checks run inside mise (no `gpg`, `cosign` or `gh` needed). By backend: `aqua:`
  checksums, Cosign, Minisign, SLSA and GitHub artifact attestations "as the aqua registry declares
  them"; `github:` attestations when published; Node.js `SHASUMS256.txt` plus its OpenPGP signature
  (a missing signature fails the install); precompiled Python attestations. The aqua registry is
  baked into each mise release, so no runtime fetch of recipes. Advisories: see below.
- **Hosts.** Install script: `mise.run` then `mise.jdx.dev`, falling back to GitHub Releases
  (`MISE_INSTALL_FROM_GITHUB` forces GitHub only). Runtime: `mise-versions.jdx.dev` (default),
  `mise.jdx.dev/releases.tsv` (tested; purpose not stated), `api.github.com`, `github.com` and the release asset hosts,
  `nodejs.org` for Node, `dl.k8s.io` and `get.helm.sh` through aqua.
- **Self-bootstrap.** `curl -fsSL https://mise.run | sh`; checksums for the script's own release are
  embedded, other versions are checked against `SHASUMS256.txt` on GitHub, and the script stops on a
  mismatch. Better for a repo: `mise generate install-script --write ./bin/mise --windows`
  (the older name was `generate bootstrap`). It fetches `https://mise.jdx.dev/v<version>/install.sh`
  and its minisign signature, verifies the signature against a key compiled into mise, and embeds
  the installer in the committed script with the version pinned. Contributors then run
  `./bin/mise install` ( `bin/mise.cmd` on Windows) without installing mise first. `--localize`
  keeps data in the project. Defaults to the newest release at least 24 hours old.
- **Advisories (GitHub API, 2026-10-25).** 13 published in 2026, all with a patched version; none
  without. One critical (GHSA-fjj5-v948-whjj, `.tool-versions` Tera templates bypass trust, patched
  2026.3.10). Six high, including the two newest: GHSA-r9rm-ppfv-c993 (unanchored substring match in
  the attestations signer check) and GHSA-fh4m-2w73-96r9 (keyless cosign verification accepted
  bundles signed by any Fulcio identity, aqua and vfox), both patched in 2026.10.0. Reading: the
  verification code that this note leans on was itself unsound until 2026.10.0, so pin
  `>= 2026.10.0`.
- **Coverage of the ten tools** (recipes read from `registry/*.toml` in jdx/mise and
  `pkgs/**/registry.yaml` in aquaproj/aqua-registry): node `core:node`; python `core:python`; pnpm,
  uv, opentofu, kind, flux2 `aqua` with GitHub release assets (kind and uv checksum assets, flux and
  opentofu cosign, pnpm and uv GitHub attestations); kubectl `aqua` `http` from `dl.k8s.io` with
  SHA-256 and a cosign certificate; helm `aqua` `http` from `get.helm.sh` with a `.sha256sum`;
  podman only as `github:podman-container-tools/podman` renamed `podman-remote`, the client, not the
  engine, so podman stays a system package.

### asdf

- **Release and licence.** v0.20.2 published 2026-09-22 (a Go binary since 0.16); MIT.
- **OS.** Linux and macOS (release assets darwin and linux, amd64 and arm64). Windows: none. The
  getting-started page does not mention it, the issues "Windows support? Docs & tests for WSL2" (#450)
  and "Define & Document supported Shells & OSs" (#1436) have been open since 2019 and 2023, and mise
  says the asdf backend "is not available on Windows".
- **Idempotent.** Yes in practice (`asdf install` skips installed versions); not stated on the page I
  read.
- **Root.** Core no ("sudo may be required depending on your system configuration"). Plugins have
  their own needs: the Node.js plugin wants `curl`, `gawk`, `gpg`; asdf-python wants build
  dependencies from the system.
- **Activation.** Shims only: `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` on PATH. That works in a
  non-interactive shell if the profile puts it there. No hook model.
- **Pinning.** `.tool-versions` with exact versions or `ref:`/`path:`; no lockfile.
- **Supply chain.** None in core that the pages describe. The plugin page makes "no security claims",
  and plugins are arbitrary shell code from git URLs, synced from `asdf-vm/asdf-plugins`. Plugins
  for this tool list come from different individuals (kubectl from asdf-community, kind from
  johnlayton, flux2 from tablexi, helm from Antiarchitect, opentofu from virtualroot, pnpm from
  jonathanmorley).
- **Hosts.** GitHub for the binary and plugins; each plugin chooses the rest.
- **Self-bootstrap.** Homebrew, Zypper, AUR, or download the binary from GitHub releases and put it
  on PATH; no committed launcher; also needs `git`.
- **Scorecard (2026-10-19).** 4.6: Code-Review 2, Signed-Releases 0 ("unsigned and lack
  provenance"), Branch-Protection 0.

### Nix flakes, devbox and devenv

- **Release and licence.** Nix 2.35.4 (tag; the repo publishes no GitHub releases), LGPL-2.1, which
  is not on the checklist's permissive list. devbox 0.18.4 (2026-09-25) and nightly edge tags to
  2026-10-22, Apache-2.0. devenv v2.4.0 (2026-09-24), Apache-2.0.
- **OS.** Nix: Linux, macOS 14 or newer, and "Windows through WSL2"; the page does not mention
  native Windows. devbox: the same, "Windows via WSL2", native Windows "not covered". devenv:
  Windows only through WSL2 with the single-user installer.
- **Idempotent.** Yes by design (store paths); not tested.
- **Root.** The multi-user install "runs a daemon that requires root" and, on WSL2, needs systemd
  enabled (WSL 0.67.6 or newer). Single-user installs run as the user but "the script uses `sudo` to
  create `/nix` if it doesn't exist"; without sudo "you must create `/nix` as root and change its
  owner". That is the blocker for a sandbox with no sudo. devbox on Linux and WSL2 installs Nix in
  single-user mode; on macOS, multi-user. devbox's page does not say whether sudo is needed.
- **Activation.** Environments entered with `nix develop`, `devbox shell` or `devenv shell`;
  `devbox run <script>` runs a script in the environment non-interactively; direnv hooks the prompt
  (the direnv page lists no Windows support). A non-interactive agent shell has to call
  `devbox run` or `nix develop -c`; nothing is on PATH otherwise.
- **Pinning.** Flakes: `flake.lock` pins inputs to commits. devbox: `name@version` in `devbox.json`
  plus `devbox.lock`, resolved through a search service (`https://www.nixsearch.com` in the source,
  overridable). devenv: `devenv.lock`; Node and pnpm are "whatever nixpkgs provides", the page names
  no versions. The Nix manual still lists `flakes` and `nix-command` as experimental, with no
  stabilisation statement.
- **Supply chain.** `require-sigs` defaults to true, `trusted-public-keys` to the
  `cache.nixos.org-1` key; the build sandbox is on by default on Linux. `trusted-users` is "essentially
  equivalent to giving that user root access".
- **Hosts.** `nixos.org` (installer), `releases.nixos.org` (binary tarballs; the page does not say
  whether the installer checks the published SHA-256), `cache.nixos.org` (substituter), `github.com`
  for flake inputs. None of these is allowlisted.
- **Self-bootstrap.** `curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s --
  --daemon` (or `--no-daemon`); devbox `curl -fsSL https://get.jetify.com/devbox | bash` installs Nix
  too if it is missing.
- **Advisories.** Nix: 16 published, 2 critical, all patched. devbox and devenv: none listed.
  Scorecard: Nix 6.5 (2026-10-19; Code-Review 10, Branch-Protection 4); devbox and devenv no entry.

### proto (moonrepo)

- **Release and licence.** v0.63.2, 2026-10-22; MIT.
- **OS.** Linux and macOS (assets: aarch64 and x86_64 apple-darwin, gnu and musl linux). Windows:
  native, `irm https://moonrepo.dev/install/proto.ps1 | iex` in an administrator PowerShell (x86_64
  only in the assets; the page says shims may need execution policy `RemoteSigned`).
- **Idempotent.** Not stated on the pages read.
- **Root.** Linux and macOS: none stated, but it needs Git, tar, unzip, gz and xz from the system.
  Windows: the installer wants an administrator terminal.
- **Activation.** Shims in `~/.proto/shims` (wrappers around `proto run`, version detected on every
  call) and `~/.proto/bin` symlinks, or `proto activate <shell>` (a prompt hook). Shims suit a
  non-interactive shell; `~/.proto/bin` must always be on PATH.
- **Pinning.** `.prototools` (TOML). Lockfile `.protolock` exists since v0.51.0 but is behind
  `unstable-lockfile = true` and the docs say "Lockfiles are currently unstable". `proto install
  --immutable-lockfile` since v0.61.0; per-libc records since v0.63.0.
- **Supply chain.** Plugin code supports GPG detached signatures and minisign checks (source:
  `crates/core/src/checksum/{gpg,minisign,sha}.rs`; the docs pages I read describe none of it).
  Third-party plugins are loaded only from trusted configs.
- **Hosts.** `moonrepo.dev` (installer), GitHub releases, `raw.githubusercontent.com` for plugin
  manifests, and each tool's own host (`nodejs.org` for Node).
- **Coverage.** Built in: node, pnpm, python, uv. Unofficial third-party TOML plugins by individuals,
  fetched from raw GitHub URLs: kubectl (Trillion Labs), helm (stk0vrfl0w), flux (b4nst), tofu
  (appthrust). `kind`: none in the registry (only `k3d`). Podman: none.
- **Advisories and Scorecard.** None listed; no Scorecard entry (404): unverified.

### aqua

- **Release and licence.** v2.65.2, 2026-10-22; MIT (the `LICENSE` file; the API reports no SPDX
  id).
- **OS.** Linux and macOS (assets amd64 and arm64); native Windows (assets, a Windows support page:
  works with Developer Mode off and without Administrator; hard links; MinTTY caveats in Git Bash).
- **Idempotent.** `aqua i` installs what `aqua.yaml` lists; reruns are no-ops in practice, not
  stated.
- **Root.** Not stated; installs under `$AQUA_ROOT_DIR` (default
  `${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua`).
- **Activation.** A proxy directory `$AQUA_ROOT_DIR/bin` on PATH; invoking a tool runs `aqua exec`
  through `aqua-proxy`, which installs on first use ("lazy install"). Works from a non-interactive
  shell once PATH is set; the first call needs the network.
- **Pinning.** `aqua.yaml` with `name@version`; registries pinned by ref;
  `aqua-checksums.json` committed, keyed per OS and architecture, filled by `aqua update-checksum`.
  Checksum verification "is disabled by default"; turn it on with `checksum: enabled: true` and
  enforce with `AQUA_ENFORCE_CHECKSUM` and `AQUA_ENFORCE_REQUIRE_CHECKSUM`.
- **Supply chain.** Checksums, Cosign, Minisign, SLSA provenance and GitHub artifact attestations as
  each recipe declares; a policy file ("only the standard registry is allowed by default"); aqua
  "doesn't execute external commands except for `go install` and `go build`".
- **Hosts.** `github.com` for the binary and for the registry and recipes, plus each recipe's own
  host (`dl.k8s.io`, `get.helm.sh`, `nodejs.org`).
- **Self-bootstrap.** A shell one-liner from `aquaproj/aqua-installer` pinned by tag, or the GitHub
  Action pinned to a commit; the page recommends downloading the script and checking its SHA-256.
- **Advisories and Scorecard.** GHSA-286g-rf2x-cv99 (high, 2026-09-15): a GNU sparse tar member makes
  aqua re-extract through the host `tar`, escaping the install directory on hosts whose `tar` follows
  symlinks. Range `>= 2.61.0, <= 2.62.3`; the advisory lists no patched version, and the latest
  release is 2.65.2, outside the range. Inference: fixed in practice, not confirmed by the advisory.
  Scorecard 6.5 (2026-08-31): Signed-Releases 10, Code-Review 2, Branch-Protection 3, SAST 0,
  Security-Policy 0.
- **Coverage.** pnpm, uv, opentofu, kubectl, kind, flux, helm, node (`nodejs.org`, http recipe).
  Python: none (use uv). Podman: none.

### Devcontainers

- **Release and licence.** `devcontainers/cli` v0.89.0 (tag; no GitHub releases), MIT; repo pushed
  2026-10-22.
- **OS.** The host needs a container engine. Windows: Docker Desktop with the WSL 2 back-end, "Docker
  Toolbox and Windows container images are not supported"; macOS: Docker Desktop; Linux: Docker
  CE/EE. Podman: set `dev.containers.dockerPath` to `podman`; "mostly compatible", other CLIs "not
  officially supported". The CLI's install script runs on Linux and macOS, x64 and arm64.
- **Idempotent.** `devcontainer up` reuses a container; lifecycle commands (`onCreateCommand`,
  `postCreateCommand`) run on first creation.
- **Root.** Needs a container engine (a daemon with root, or rootless Podman set up as in ADR 0018).
- **Activation.** Not a shell activation model: tools live inside the container; `devcontainer exec`
  runs a command there. A bubblewrap sandbox has no engine socket (ADR 0018 spent a whole ADR on
  that), and kind inside a devcontainer is container-in-container (inference: needs privileged mode).
- **Pinning.** Image by tag or digest; `.devcontainer-lock.json` pins Feature versions, generated by
  default on `build` and `up`, enforced by `--frozen-lockfile`.
- **Supply chain.** The CLI's install script downloads Node.js from `nodejs.org` with no checksum or
  signature step I could find (the script's only "verify" lines check that files exist).
- **Hosts.** `raw.githubusercontent.com`, `registry.npmjs.org`, `nodejs.org`, an image registry
  (default for `mise generate devcontainer` is `mcr.microsoft.com/devcontainers/base:ubuntu`).
- **Self-bootstrap.** `curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh |
  sh`, or `npm install -g @devcontainers/cli` (needs Python and a C/C++ toolchain); in VS Code the
  extension.
- **Advisories and Scorecard.** None listed; no Scorecard entry: unverified.

### Bazel: bazelisk and hermetic toolchains

- **Release and licence.** bazelisk v1.30.0, 2026-10-20, Apache-2.0; Bazel 9.3.1, 2026-10-21.
- **OS.** bazelisk assets for linux, darwin and windows, amd64 and arm64
  (`winget install Bazel.Bazelisk`). Native Windows: supported; Bazel's install page wants MSYS2 for
  Bash targets, Visual C++ and the Visual Studio build tools for C++.
- **Idempotent.** Yes; it caches the selected Bazel under its home.
- **Root.** No for bazelisk. Bazel's own sandbox cannot start inside the Claude Code sandbox (tested
  in [monorepo-build-tool.md](monorepo-build-tool.md)).
- **Activation.** None: `bazel` on PATH is bazelisk, which reads `.bazelversion` (or
  `USE_BAZEL_VERSION`, `.bazeliskrc`). Works in any shell.
- **Pinning.** `.bazelversion`; `BAZELISK_VERIFY_SHA256` checks the downloaded Bazel. Toolchains:
  `MODULE.bazel.lock` "stores the result of module resolution and extension evaluation" and hashes of
  registry files; the page does not say it covers toolchain archives. `rules_python` registers a
  python-build-standalone archive with an explicit `sha256`. `rules_multitool` (Apache-2.0, v1.11.1,
  2025-12-01) is a JSON lockfile of per-OS, per-CPU URLs with `sha256` for plain binaries; its last
  release leaves the 12-month window on 2026-12-01.
- **Supply chain.** SHA-256 per download. bazelisk releases are unsigned (Scorecard Signed-Releases 0).
- **Hosts.** Google Cloud Storage for Bazel itself (README), the Bazel Central Registry, GitHub for
  python-build-standalone, `nodejs.org` for Node; none of these hosts beyond GitHub is allowlisted.
- **Self-bootstrap.** Download the bazelisk binary, or winget, Homebrew, npm.
- **Fit.** Not an installer: it provisions the Bazel build, and the other tools only if the repo
  adopts Bazel rules for each. Podman, kind, flux and helm have no first-party rule in anything I read.
- **Advisories and Scorecard.** bazelisk: none listed; Scorecard 5.5 (2026-10-19; Code-Review 10,
  Maintained 5). Bazel: one advisory, patched.

## Operating properties at a glance

| | mise | asdf | Nix / devbox / devenv | proto | aqua | Devcontainers | Bazelisk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Linux, macOS | yes | yes | yes | yes | yes | needs engine | yes |
| WSL2 | yes | yes | yes (multi-user needs systemd) | yes | yes | Docker Desktop back-end | yes |
| Native Windows | yes | no | no (WSL2 only) | yes (admin shell) | yes | Docker Desktop, Linux containers | yes (MSYS2, MSVC) |
| Root or sudo | no | no (plugins may) | yes, for `/nix` | no (Windows: admin) | not stated | engine | no |
| Activation | hook, shims or `exec` | shims | enter a shell, `run` | shims or hook | PATH proxy, lazy install | inside container | wrapper on PATH |
| Lockfile with checksums | `mise.lock` | none | `flake.lock`, `devbox.lock`, `devenv.lock` | `.protolock` (unstable) | `aqua-checksums.json` | features only | `MODULE.bazel.lock`, `BAZELISK_VERIFY_SHA256` |
| Checks done by the tool | checksum, cosign, minisign, SLSA, attestations, GPG (Node) | none described | signed binary cache | checksum, GPG, minisign in plugins | checksum, cosign, minisign, SLSA, attestations | none for its own installer | SHA-256 |
| Tool covers the ten | 9 of 10 (not the podman engine) | 9 of 10 (Python by compiling; podman none) | not verified | 4 built in, 4 individuals' plugins, no kind, no podman | 8 of 10 (no Python, no podman) | not checked | no |

## Adopt-or-build checklist

Rule for "Maintainers": GitHub does not show who can merge to a public repo, so the proxy is
non-bot commit authorship from 2025-10-25 to 2026-10-25 (GitHub API). Pass means at least two
humans each wrote 5% or more. It does not measure bus factor, so the dominant share is shown.
"Images" means release binaries for linux and darwin, amd64 and arm64.

| Candidate | Maintained | Licence | Security | Maintainers | Images | Pinning | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mise | pass, v2026.10.19 2026-10-24 | MIT, pass | no open critical; 13 advisories in 2026, one critical patched 2026.3.10, newest highs patched 2026.10.0; no Scorecard (404): unverified | pass: jdx 62%, risu729 10%, JamBalaya56562 6% of 4,556 commits | pass: linux and macOS x64 and arm64, plus Windows | pass: exact versions and `mise.lock` | **adopt** |
| aqua | pass, v2.65.2 2026-10-22 | MIT, pass | one high advisory, range ends before the latest release; Scorecard 6.5 | marginal pass: suzuki-shunsuke 81%, scop 8% of 135; effectively one person | pass | pass: `aqua.yaml` plus checksums file | **adopt as fallback** |
| asdf | pass, v0.20.2 2026-09-22 | MIT, pass | no advisories; Scorecard 4.6, releases unsigned | **fail**: Stratus3D 60%, next 4% of 45 commits | pass | exact versions, no lockfile or digest | **find another** |
| proto | pass, v0.63.2 2026-10-22 | MIT, pass | no advisories; no Scorecard: unverified | **fail**: milesj 79%, next 2% of 234 | pass: darwin and linux, both architectures | `.protolock` unstable | **find another** |
| Nix flakes | pass, 2.35.4 | **fail**: LGPL-2.1 | 16 advisories, 2 critical, all patched; Scorecard 6.5 | pass: xokdvium 32%, Ericson2314 25%, edolstra 11% of 2,965 | pass (stated, not read from the release listing) | pass: `flake.lock`; flakes still experimental | **find another** |
| devbox | pass, 0.18.4 2026-09-25 | Apache-2.0, pass | no advisories; no Scorecard: unverified; needs Nix | marginal pass: mikeland73 75%, Lagoja 7% of 150 | pass | pass: `devbox.lock` | **find another** (needs Nix) |
| devenv | pass, v2.4.0 2026-09-24 | Apache-2.0, pass | no advisories; no Scorecard: unverified; needs Nix | pass: domenkozar 48%, sandydoo 39% of 2,594 | via Nix | pass: `devenv.lock` | **find another** (needs Nix) |
| Devcontainers CLI | pass, v0.89.0, pushed 2026-10-22 | MIT, pass | no advisories; no Scorecard: unverified | pass: chrmarti 48%, v-Mathiyarasy 17% of 134 | pass: install script linux and macOS, both | pass: image digest, feature lockfile | passes; **wrong problem** |
| bazelisk | pass, v1.30.0 2026-10-20 | Apache-2.0, pass | no advisories; Scorecard 5.5, releases unsigned | pass: valco1994 19%, fweikert 15% of 27 | pass: linux, darwin, windows | pass: `.bazelversion` and SHA-256 | passes; **wrong problem** |

"Find another" follows the checklist's rule: any failing line means build or find another. Nix's
licence failure is a policy call, not a technical one: the repo would only run Nix, not
redistribute it, and [agentic-software-factory-implementation.md](agentic-software-factory-implementation.md)
already frames a licence miss on software that is only deployed as an ADR call. I did not
recommend it because the no-sudo `/nix` blocker and the unlisted hosts are independent of the
licence.

## Verdict

**Adopt mise** for the user-space toolchain, as follows. The design choices are the ones the sources
force; the operator decides the rest.

1. **Pin.** `mise.toml` with `[tools]` and `[tasks]` only (no `[env]`, `[hooks]` or `[settings]` in
   the committed file, so it loads without trust). Exact versions for kubectl, kind, flux2, helm,
   opentofu, pnpm, uv, node. Set `minimum_release_age` in the global config, not the repo file.
2. **Lock.** Commit `mise.lock` generated for `linux-x64,linux-arm64,macos-arm64,macos-x64,windows-x64`;
   contributors and the agent run `mise install --locked`. The platform list omits `windows-arm64`
   because kind ships no such asset.
3. **Launcher.** `mise generate install-script --write ./bin/mise --windows`, committed, with
   mise pinned to `>= 2026.10.0` (the verification fixes). The one command is `./bin/mise install
   --locked`; wrap it in `mise run bootstrap` or the go-task entry point the other note chose.
4. **Python.** Let uv own it (`.python-version`, `uv python install`; uv takes it from
   `python-build-standalone` on GitHub). Reason: mise's own Python needs `mise-versions.jdx.dev`.
   Untested here.
5. **Agent PATH.** A SessionStart hook that appends the mise install directory (or the shims
   directory) to `$CLAUDE_ENV_FILE`, so the sandboxed Bash sees the tools without a prompt hook.
6. **Allowlist.** To make the tested failure go away: `use_versions_host = false` in the global
   config (tested: that alone installed kind, uv, opentofu, flux2 and pnpm), optionally a no-scope
   read-only token as `MISE_GITHUB_TOKEN` to avoid the 60-per-hour anonymous limit (not the App token,
   see point 2 of the failure list), and `nodejs.org` added for Node (the single new host; untested
   because the host is blocked). The alternative is to
   allow `mise-versions.jdx.dev` and `mise.jdx.dev`, which puts a third party in the metadata path
   (point 2 above); I would not.
7. **Podman and bubblewrap stay system packages**, as in `docs/operator-setup.md`. Do not rely on
   `mise bootstrap packages` yet.
8. **Windows.** WSL2 supported. Native Windows: the launcher's `.cmd` and the CLIs work, the bash
   hooks and the dev loop do not; call it unsupported until an ADR says otherwise.

What would change the verdict: a new critical advisory in mise's verification path; the operator
wanting contributors on native Windows with the full dev loop (then a devcontainer or a Windows
VM story is the question, not a toolchain manager); or the repo adopting Bazel for builds (then
bazelisk and rules_multitool become the natural pin).

## Not verified

- Whether the Claude Code Bash tool sees `~/.local/bin` or shims added in `~/.profile` (the docs say
  rc files are sourced and aliases, functions and options captured, not PATH). Not tested.
- Nix, devbox and devenv were not installed (no sudo). Their package coverage of the ten tools and
  the Nix release platform listing (`releases.nixos.org` is not allowlisted) were not read.
- Scorecard entries do not exist (404) for mise, proto, devbox, devenv and devcontainers/cli;
  "unverified" above means no independent audit or scorecard was found. No third-party audit of any
  candidate turned up.
- The "Maintainers" proxy counts commit authors, not merge rights.
- Windows behaviour is from documentation only; nothing was run on Windows or macOS.
- The `mise bootstrap` machine-setup command is new in this release series; its stability was not
  assessed beyond its changelog churn.
