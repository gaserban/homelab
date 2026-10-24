# Operator setup

The steps only the operator can do, in order. After these, Claude works in the repository from a
Claude Desktop WSL session. Decisions behind each step: ADR 0001, 0005, 0013, 0014.

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
3. Put the App key at `~/.config/homelab/app.pem`, `chmod 600`. In `~/.local/bin`, add a git
   credential helper and a `gh` wrapper that mint one-hour App installation tokens from the key
   (a small script using openssl and curl). Set the App's bot name and email with
   `git config --global`, and set the helper. `~/.local/bin` must be on `PATH` before the helper
   scripts work: Debian's `~/.profile` adds it only when the directory already exists at login, so
   create the directory, log in again, and check that `command -v gh` resolves to the wrapper and
   not to `/usr/bin/gh`.
4. Install the container runtime per ADR 0005, rung by rung, until kind creates a cluster. Record
   the winning rung in the Podman prototype ticket.
5. `git clone https://github.com/gaserban/homelab ~/src/homelab`.
6. Open a Claude Desktop WSL session in `~/src/homelab`. The first session's task is the harness
   skeleton ticket.

## 4. Verify

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

- Claude can read the App key, because the credential helper runs inside the sandbox. With it,
  Claude can push branches and open PRs on this repository. It cannot merge (ruleset). Rotate the
  key on suspicion.
- WebFetch runs outside the sandbox; permission prompts decide which sites it reaches.
- Excluding the container runtime from the sandbox gives that one command host access.
