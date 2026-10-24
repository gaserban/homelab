# 0002 GitOps engine: Flux via the Flux Operator

Date: 2026-10-24

## Context

One engine applies everything. Candidates: Argo CD and Flux. Scored against the goals: one tree of
everything an app caused, deployment steps that cannot over-reach, dependency ordering, deletion
safety for stateful components, a read-only Git credential, a fast dev loop that may skip the
engine, Helm handling for operator charts, modest hardware, dependency updates, backing.

Findings (October 2026): Argo CD 3.5 and Flux 2.9 with Flux Operator 0.61, both CNCF graduated.
Argo wins on the built-in UI, safer deletion defaults and breadth of maintainers. Flux wins on the
admin fence (each Kustomization runs as a Kubernetes service account, so Kubernetes RBAC enforces
the limit rather than the engine), on cross-object ordering (`dependsOn` with health gates), on
real Helm releases (hooks, CRD upgrade policy, rollback, remediation, which the cert-manager and
CloudNativePG charts need), on memory (four controllers at 64 MiB requested each versus five to
seven pods), on an offline renderer for the dev loop, and on a built-in Renovate manager. The Flux
Operator route keeps the Git credential read-only; the classic bootstrap command needs write
access and is not used.

## Decision

Flux, installed and managed by the Flux Operator, with a FluxInstance whose source is GitHub
(read-only key) in prod and a local OCI artifact in dev. Argo CD was a defensible choice; the UI
gap is the accepted cost, mitigated by ADR 0010.

## Consequences

- The Flux Operator is one company's AGPL project (ControlPlane), not a CNCF one. Accepted.
- Deletion safety must be configured; see ADR 0012.
- Multi-tenancy uses per-Kustomization service accounts and the no-cross-namespace-refs setting.
