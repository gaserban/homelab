# 0018 Dev runtime: rootless Podman under its own user, reached from the sandbox through SSH

Date: 2026-10-25

## Context

ADR 0005's rung 1 worked rootful, but rootful Podman needs `sudo`, which Claude cannot run, so the
operator would have had to run every container command. The operator wants Claude to drive the dev
runtime itself, without weakening the sandbox's file protections (ADR 0014).

What the sandbox allows, verified on this workstation:

- On Linux it cannot allow one Unix socket path, only all of them (`allowAllUnixSockets`), which
  would also open the systemd user bus and WSL's Windows interop socket: a full escape.
- It has its own network namespace; the host's loopback is reachable only through its HTTP or
  SOCKS proxy, as an allowed `IP:port`.
- Both proxies drop a connection once the client half-closes it. `podman exec -i` signals the end
  of stdin that way, so `kind create cluster` fails at "Installing CNI" through them.
- `excludedCommands: ["podman"]` never took effect: an entry without a wildcard matches only the
  bare command. Excluding `podman *`, `kind *`, `kubectl *` or `flux *` would not help either: an
  unsandboxed client can upload any file the operator can read (`podman cp`, a build context,
  `kubectl create secret --from-file`).

## Decision

- Containers run under `homelab-runtime`, a system user with no login shell and its own subordinate
  IDs, as rootless Podman. Its home is private and the operator's home is mode 700, so its
  containers cannot read the operator's files. All cgroup controllers are delegated to user
  sessions; its Podman API is a user service with `Delegate=yes` and `k8s-file` logs, serving
  `127.0.0.1:8888`. `tools/setup-dev-runtime.sh` is the operator's one-time, privileged setup.
- Claude's clients (`podman`, `kind`, `kubectl`, `flux`) stay sandboxed. `tools/hl-runtime` runs
  them with their ports (8888 Podman API, 6443 kind API server, 5000 registry) forwarded through
  one SSH connection to `hl-tunnel`: an `sshd` container the runtime user runs on the host network,
  bound to `127.0.0.1:5001`, accepting one key and forwarding only to those three ports. SSH carries
  end-of-input in-band, so the proxy never sees a half-close. If the tunnel is down,
  `hl-runtime` rebuilds and restarts it over a plain bridge to the API.
- The sandbox allowlist gains `127.0.0.1:8888` (the bootstrap bridge) and `127.0.0.1:5001` (the
  tunnel); `excludedCommands` is removed. Keys live in `.state/`, which is gitignored.
- This supersedes ADR 0014's sentence "Only the container runtime is excluded from the sandbox; the
  dev cluster API is bound to the WSL interface address so cluster tools stay sandboxed."

## Consequences

- Claude creates and deletes the cluster, runs the registry, pushes artifacts and uses kubectl
  without the operator. The operator runs the setup wizard once per workstation.
- Anything on the workstation that can open `127.0.0.1:8888` drives the runtime user's containers.
  Containers reach the internet directly, outside the sandbox's domain allowlist, so a container
  Claude starts is an unfiltered network path. Neither path reaches the operator's files or root.
- `127.0.0.1:6443` stays in the allowlist from the first setup but is no longer used; drop it at
  the next settings change.
- The tunnel's host key is baked into a local image; wiping `.state/` makes `hl-runtime` rebuild
  the image with new keys on its next run.
