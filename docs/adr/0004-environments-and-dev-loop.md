# 0004 Environments: kind dev synced from a local artifact, qa deferred, Talos prod

Date: 2026-10-24

## Context

Dev must be fast to prototype in. Running Talos in containers gives OS parity but no Podman path
and slow iteration. Engine-free dev (render and apply with kubectl) is fast but exercises none of
the ordering, Helm and prune behaviour where GitOps surprises live. Flux can package a folder as an
OCI artifact with one command and sync from it.

## Decision

- dev: a single-node kind cluster on the workstation (WSL2, Debian). Flux runs in it and syncs
  from an artifact pushed to a local registry container. Edit, push the folder, Flux applies in
  seconds; no Git commit needed. Offline rendering (the Flux build command, or flate) is a side
  tool, not the deployment path.
- qa: the same recipe plus the Cloudflare tunnel, up only while testing. Deferred until prod
  exists; its name stays reserved.
- prod: Talos Linux on the mini-PC (Ryzen 7 5700U, 16 GB, 512 GB NVMe), more nodes later.
  Images come from the Talos Image Factory with the extensions Longhorn needs.
- Every image must be multi-architecture (amd64 and arm64), because a Raspberry Pi 4 may join as a
  node later.

## Consequences

- One cluster recipe for all environments; only the source definition differs.
- The pull model holds even in dev.
- The workstation gives WSL 16 to 20 GB of its 32 GB.
