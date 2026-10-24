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
