# Operator setup

The steps only the operator can do, in order. After these, Claude works in the repository from a
Claude Desktop WSL session. Decisions behind each step: ADR 0001, 0005, 0013, 0014, 0019.

## 1. GitHub, in the browser

1. Create the public repository `gaserban/homelab` with a README.
2. Settings, Code security: turn on secret scanning and push protection.
3. Settings, Rules, Rulesets: a ruleset on `main` with
   - require a pull request before merging, one approval, dismiss stale approvals on new commits;
   - block force pushes; block deletion;
   - restrict updates;
   - bypass list: repository admin, mode "for pull requests only".
4. Settings, Developer settings, GitHub Apps: create an App with Contents read and write, Pull
   requests read and write, Issues read and write, Metadata read. Install it on `homelab` only.
   Download its private key. Add Workflows read and write only when the repo gets its first
   workflow.
5. Create a read-only deploy key for the cluster later (the Flux source); not needed until prod.

## 2. Windows

1. WSL is installed. Install Debian: `wsl --install -d Debian`. Set the memory cap in
   `%UserProfile%\.wslconfig`: `memory=20GB`, and `kernelCommandLine=cgroup_no_v1=all` so cgroup
   v2 is in force for the container runtime.
2. Open Claude Desktop, choose the WSL session type pointing at the Debian distro.

## 3. In the Debian distro

1. `sudo apt install git bubblewrap socat curl jq` (bubblewrap and socat are the sandbox's
   requirements; the hooks parse their input with jq and refuse to run without it). Debian does
   not restrict unprivileged user namespaces by default; if the sandbox still fails to start,
   follow the sandboxing docs' AppArmor note.
2. Install the Proton Pass CLI (`pass-cli`) and log in once. Create the vault entries the bootstrap
   adapter will read; names are listed in `docs/adr/0008-secrets.md` once the first environment
   exists.
3. Put the App key at `~/.config/homelab/app.pem`, `chmod 600`, and the App's IDs in
   `~/.config/homelab/env` (`HOMELAB_APP_ID=...`, `HOMELAB_APP_INSTALLATION_ID=...`). The helper
   scripts live in the repository's `tools/` (step 5 clones it); symlink them into `~/.local/bin`:
   `ln -s ~/src/homelab/tools/{gh-app-token,gh,git-credential-homelab-app} ~/.local/bin/`.
   `gh-app-token` serves a cached one-hour App installation token from
   `$XDG_RUNTIME_DIR/homelab-app-token` and mints a new one from the key only when the cache is
   older than 50 minutes; the sandbox cannot read the key, so the `token-refresh.sh` hook (which
   runs outside it) keeps the cache fresh. Set the App's bot name and email with
   `git config --global`, and set the helper:
   `git config --global credential.https://github.com.helper '!git-credential-homelab-app'`.
   `~/.local/bin` must be on `PATH` before the helper scripts work: Debian's `~/.profile` adds it
   only when the directory already exists at login, so create the directory, log in again, and
   check that `command -v gh` resolves to the wrapper and not to `/usr/bin/gh`.
4. `sudo apt install podman`, then run `tools/setup-dev-runtime.sh` (ADR 0005): rootless Podman
   under the `homelab-runtime` user with its API on `127.0.0.1:8888`, kind, kubectl and flux, and
   the sandbox settings that let Claude reach them. Claude then creates the cluster and the registry
   (`127.0.0.1:5000`) itself through `tools/hl-runtime`, which tunnels over SSH (ADR 0018).
5. `git clone https://github.com/gaserban/homelab ~/src/homelab`.
6. Open a Claude Desktop WSL session in `~/src/homelab`. The first session's task is the harness
   skeleton ticket.

## 4. Bazel, your clone and Claude's settings

Bazel builds and runs every tool (ADR 0019). Claude's checkout (`~/src/homelab` and its worktrees)
is Claude's alone: you never commit, push, or run Bazel, `./setup`, `tools/hl-runtime` or the wizard
with a working directory inside it. You work in your own clone.

1. Install bazelisk v1.30.0 as `bazel` on your PATH, checking the SHA-256 GitHub lists for the
   asset. `setup` pins the same digests and refuses any other `bazel`:
   - `bazelisk-linux-amd64`: `a248ae2b2b62b5baebb748f6fba7203bff1a27e5d01b55399a8406744cb539e8`
   - `bazelisk-linux-arm64`: `b2bcc040c213b44586b121bda6d983c35df121b917c3a7a66fb16f2fa0df1a4f`

   ```bash
   arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
   tmp=$(mktemp)
   curl -fsSLo "$tmp" "https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-linux-$arch"
   sha256sum "$tmp"   # must equal the digest above for your arch
   install -m 755 "$tmp" ~/.local/bin/bazel && rm "$tmp"
   ```

   A bazelisk bump changes `setup` and `.github/workflows/checks.yml` in one PR; each user then
   reinstalls.
2. Make your clone, outside every path Claude's settings let it write (this workstation uses
   `~/programming`): `git clone https://github.com/gaserban/homelab ~/programming`. Keep it on `main`
   or your own branches, never a Claude branch; your changes go to your own PRs from `main`. Run
   `./setup` there (it checks Podman, bubblewrap and bazelisk, then fetches every locked tool; it
   installs nothing), and from now on run the wizard, Bazel and `tools/hl-runtime` there too. Your
   clone needs no `user.bazelrc`: Bazel's defaults apply.
3. Give Claude its own Bazel directory `<C>`: a new, empty directory outside the repository and
   outside `~/.cache`, written as an absolute path because `env` values are not expanded. In
   Claude's checkout, `.claude/settings.local.json` gets:

   ```json
   {
     "env": { "BAZELISK_HOME": "/home/<you>/claude-bazel/bazelisk" },
     "sandbox": { "filesystem": { "allowWrite": ["/home/<you>/claude-bazel"] } }
   }
   ```

   Start a new Claude session so `BAZELISK_HOME` is set. Claude writes its own untracked
   `user.bazelrc` (output root and tool caches under `<C>`) in its checkout and copies it into each
   worktree. When `<C>` runs short of space or you ask, and only after you confirm no other Claude
   session is open, Claude wipes the children of `<C>`, never `<C>` itself. If `<C>/prek/patches`
   holds a file (an interrupted commit's stash), it stops and reports it instead. Otherwise, in one
   call, then `./setup`:

   ```bash
   cd "$(dirname "${BAZELISK_HOME:?}")" || exit 1
   chmod -R u+w bazel bazelisk prek xdg-cache xdg-data go zig pnpm-store pnpm-store-operation-locks-1000 2>/dev/null
   rm -rf bazel bazelisk prek xdg-cache xdg-data go zig pnpm-store pnpm-store-operation-locks-1000
   ```

4. Once `.pre-commit-config.yaml` is on `main`, write the two hook shims, mode 755, into
   `.git/hooks` of Claude's checkout and of your clone (the sandbox denies Claude writes there).
   Each runs prek through Bazel with that checkout's configuration.

   `.git/hooks/pre-commit`:

   ```bash
   #!/bin/bash
   # prek's pre-commit hooks, run through Bazel with this checkout's configuration.
   exec bazel run --config=tool @multitool//tools/prek:cwd -- run --config .pre-commit-config.yaml --hook-stage pre-commit
   ```

   `.git/hooks/pre-push`:

   ```bash
   #!/bin/bash
   # prek's pre-push hooks, run through Bazel once per pushed ref. A deletion is skipped; a new ref, or
   # one whose remote commit is not here, is checked from origin/main.
   rc=0
   while read -r _ local_sha _ remote_sha; do
     case "$local_sha" in *[!0]*) ;; *) continue ;; esac
     base=$remote_sha
     case "$remote_sha" in *[!0]*) git cat-file -e "$remote_sha^{commit}" 2>/dev/null || base=origin/main ;; *) base=origin/main ;; esac
     bazel run --config=tool @multitool//tools/prek:cwd -- run --config .pre-commit-config.yaml \
       --hook-stage pre-push --from-ref "$base" --to-ref "$local_sha" </dev/null || rc=1
   done
   exit "$rc"
   ```

   If a broken hook blocks every commit or push, remove both shims from that checkout
   (`rm .git/hooks/pre-commit .git/hooks/pre-push`), merge the fix, then write them back.
5. The wizard still installs kind, kubectl and flux into `/usr/local/bin`, for amd64 only, as a
   fallback. Claude, `tools/hl-runtime` and CI use the locked versions in
   `tools/multitool.lock.json`, through Bazel.

## 5. Verify

- `/status` shows the project settings loaded; `/context` lists CLAUDE.md.
- In the sandbox: reading `~/.ssh`, `~/.config/homelab` or `/mnt/g` fails; the Read tool is
  refused on `/mnt/**`; writing outside the repo fails; an unlisted host prompts; a branch push
  works.
- As the App: a push to `main` is refused; a PR cannot merge without the operator's approval; a push
  after approval dismisses it; after approval, a merge attempt by the App is refused; the operator
  can merge.
- The hooks: `gh pr merge` is blocked with a message; an issue without the four headings is blocked.
- Proof: one small issue goes from branch to a merged PR.

## Known risks

- Claude cannot read the App key: the sandbox and the Read tool are denied `~/.config/homelab`, and
  the key is read only by the `token-refresh.sh` hook, outside the sandbox. Claude can read the
  cached one-hour App token, and with it push branches and open PRs on this repository until it
  expires. It cannot merge (ruleset). Rotate the key on suspicion.
- WebFetch runs outside the sandbox; permission prompts decide which sites it reaches.
- Excluding the container runtime from the sandbox gives that one command host access.
