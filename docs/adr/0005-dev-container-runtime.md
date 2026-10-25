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

Rung 1 won; rungs 2 and 3 were not tried.

- Host: Debian 13 in WSL2, kernel 6.6.114.1-microsoft-standard-WSL2, `cgroup_no_v1=all` on the
  kernel command line, so `/sys/fs/cgroup` is cgroup v2 only.
- Runtime: Debian's `podman` 5.4.2, rootful, crun, systemd cgroup manager.
- Cluster: kind v0.33.0, node image `kindest/node:v1.37.0`.
  `sudo env KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --wait 3m` reached Ready after
  15 seconds; the cgroup failure from the 2025 issue did not appear.
- Registry: `docker.io/library/registry:3` as `kind-registry` on the `kind` network, published on
  `127.0.0.1:5001`. `flux push artifact oci://localhost:5001/...` (flux v2.9.6,
  `--insecure-registry`) succeeded and the tag was listed by the registry.

What the result changes in the consequences above:

- Every `podman` and `kind` command runs through `sudo`, and kind writes its kubeconfig to root's
  home; a user kubeconfig comes from `sudo kind get kubeconfig`. The `podman` entry in the sandbox's
  `excludedCommands` does not let Claude drive the runtime, because Claude cannot `sudo`. Container
  operations stay with the operator until a ticket decides how Claude reaches the root socket.
- The sandbox has its own network namespace, so the host's `127.0.0.1:5001` is not its loopback.
  Claude reaches the registry only through the sandbox proxy, with `127.0.0.1:5001` allowed. Go
  never proxies loopback addresses, so `flux push` from the sandbox needs a local forwarder through
  the proxy (the test used `socat`). The dev loop (ADR 0004) has to settle this before Claude
  pushes artifacts routinely.
