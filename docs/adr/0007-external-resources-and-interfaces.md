# 0007 External resources: OpenTofu, HCP Terraform, external-dns; one interface per external purpose

Date: 2026-10-24

## Context

Cloudflare (tunnel, access fence, zone), Backblaze B2 (buckets) and the Git host sit outside the
cluster. Rights that can change them must never live in a cluster. The operator knows Terraform
and Pulumi, and wants the outside tools swappable while the in-cluster components stay fixed
(ADR 0003).

## Decision

- OpenTofu, run by the operator from the workstation at the end of each rollout, manages the
  things that exist once per environment: the tunnel, the access fence, zone settings, the scoped
  DNS token, the B2 bucket with object lock. State lives in HCP Terraform's free tier. Outputs are
  written to the vault, and External Secrets delivers them into the cluster.
- external-dns runs in-cluster with a Cloudflare token limited to editing records in one zone, and
  creates the per-app records from the routes the platform templates emit. Apps never touch
  Cloudflare.
- One interface per external purpose, each with one implementation folder chosen by a single
  variable:

| Purpose | Interface | First implementation |
| --- | --- | --- |
| Human vault, root secrets | bootstrap adapter (`get <name>`), one script per manager | pass-cli (Proton Pass) |
| Object storage | S3-compatible endpoint plus a delivered credential | Backblaze B2 |
| IaC state | OpenTofu backend block | HCP Terraform |
| Edge: DNS, tunnel, fence | OpenTofu module `edge`; external-dns provider as one Helm value | Cloudflare |
| Git host | sync source URL plus read-only key | GitHub |

## Consequences

- The domain (gaserban.work), the tunnel and HCP Terraform are first needed when the first
  internet-facing environment is built; dev uses local hostnames and the homelab CA.
- Pulumi remains possible; the shape is identical. OpenTofu was chosen for fit with the installed
  skill and the one inspiration repository that does this well.
- The worst a compromised cluster can do with the DNS token is repoint the homelab's own records.
