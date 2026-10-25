# 0005 Dev container runtime: Podman first, with a tested fallback ladder

Date: 2026-10-24

## Context

The operator prefers Podman and has removed Docker. kind supports Podman, but its maintainer calls
the provider brittle and the project does not support WSL; Podman's own docs require rootful
Podman for kind on Windows, and an open 2025 issue shows a cgroup failure on rootful Podman in
WSL2. Talos is no longer in dev (ADR 0004), so only kind, the registry container and the Flux push
need the runtime, all plain container operations.

## Decision

A prototype ticket decides. Rung 1: kind on rootful Podman inside the Debian distro, cgroup v2
forced through the WSL config. Rung 2: k3d on Podman. Rung 3: Docker Engine inside the distro (the
daemon only, not Docker Desktop). Each rung is a short test; the ticket records which rung won and
this ADR is updated.

## Consequences

- If Podman only works rootful, its daemon-free and rootless benefits are mostly gone and the
  reason for choosing it is licensing. That is acceptable as long as it is the stated reason.
- The runtime's socket is excluded from the Claude Code sandbox either way (ADR 0014).

## Result

Date: 2026-10-25. Issue #4.

Rung 1 won, first rootful and then rootless; rungs 2 and 3 were not tried.

- Host: Debian 13 in WSL2, kernel 6.6.114.1-microsoft-standard-WSL2, `cgroup_no_v1=all` on the
  kernel command line, so `/sys/fs/cgroup` is cgroup v2 only.
- Rootful: Debian's `podman` 5.4.2 (crun, systemd cgroup manager) and kind v0.33.0 with node image
  `kindest/node:v1.37.0`. `sudo env KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster` reached
  Ready after 15 seconds; the cgroup failure from the 2025 issue did not appear. A `registry:3`
  container took a `flux push artifact` (flux v2.9.6). Rejected as the standing setup because every
  command needs `sudo`, so Claude could not drive it.
- Rootless, the standing setup (ADR 0018): the same Podman under the `homelab-runtime` user, driven
  by Claude from the sandbox through `tools/hl-runtime`. `kind create cluster --config
  tools/kind-dev.yaml` reached Ready after 14 seconds; kubectl from the sandbox lists the node Ready
  and every system pod Running; `kind-registry` on `127.0.0.1:5000` took a `flux push artifact` and
  listed the tag. Three failures on the way, each fixed in `tools/setup-dev-runtime.sh`:
  - kind refused to start ("requires setting systemd property Delegate=yes"): the Podman API
    service's own cgroup had only `memory pids`. Fixed with cgroup delegation to user sessions and
    `Delegate=yes` on the service.
  - kind timed out at "Preparing nodes": the node booted, but with the journald log driver a system
    user's `podman logs` is empty, so kind never saw the boot line. Fixed with `k8s-file` logs.
  - kind failed at "Installing CNI": the sandbox proxy drops a connection on client half-close,
    which `podman exec -i` relies on. Fixed by the SSH tunnel in ADR 0018.

The last consequence above no longer holds: no runtime command is excluded from the sandbox (ADR 0018).
