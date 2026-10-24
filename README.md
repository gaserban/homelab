# homelab

A self-hosted Kubernetes homelab run by one person, declared entirely in Git and applied by one
engine. This repository holds the platform, the applications, the outside resources as code, and
the setup for the AI agent (Claude Code) that does most of the building.

## Goals

- **Everything in the cluster is declared in Git and applied by one engine.** One place to see
  what runs and why; nothing changed by hand.
- **Least privilege by default.** No application, and no deployment step, can reach more than
  what it is for. Strong rights exist in as few places as possible.
- **Applications request, the platform provides.** An app says what it needs; it never creates
  its own access, accounts, secrets stores or certificates.
- **Rebuildable from nothing.** Any environment can be destroyed and recreated; data comes back
  from backups.
- **Runs on modest hardware.** One mini-PC for production today, a few later; shared services
  where a per-app copy would cost too much.

## Environments

| | Where | Purpose |
| --- | --- | --- |
| dev | kind cluster on the workstation (WSL2) | day-to-day work; disposable; Flux syncs from a locally pushed artifact, no Git push needed |
| qa | same recipe as dev, plus the Cloudflare tunnel; up only while testing | internet-facing rehearsal; deferred until prod exists |
| prod | Talos Linux on a mini-PC (Ryzen 7 5700U, 16 GB) | always on; more nodes later |

Clusters pull their configuration from a source; nothing outside pushes into a cluster. The one
sanctioned exception is the bootstrap step that seeds the few root secrets.

## Components

**Platform (fixed choices, in-cluster)**

- **Flux via the Flux Operator**: the only thing that applies objects to a cluster. Reads Git (or
  a local OCI artifact in dev), applies in dependency order, keeps the cluster matching the source.
- **KRO**: turns an app's small request into the full set of objects behind it, from templates the
  platform owns. Behind a prototype gate; Kustomize components are the fallback.
- **OpenBao + External Secrets Operator**: the in-cluster secret store and the mover of secrets
  between it, the outside store and workloads.
- **cert-manager**: certificates from the homelab's own CA, kept in OpenBao.
- **Traefik**: ingress for every site, using its native resources.
- **authentik**: identity: people, groups, each app's login and rights, sign-in in front of sites
  that have none.
- **CloudNativePG**: one shared Postgres; each app gets its own role and database.
- **Longhorn**: storage; one replica today, more as nodes arrive.
- **Headlamp + Flux plugin + metrics-server**: the operator's window into the cluster, behind
  authentik.

**Outside the cluster (interfaced, swappable)**

- **Cloudflare**: tunnel, access fence and zone, managed by OpenTofu; per-app DNS records by
  external-dns in-cluster.
- **Backblaze B2**: one locked bucket per environment for backups.
- **HCP Terraform**: OpenTofu state.
- **Proton Pass** (via `pass-cli`): the human vault holding the few root secrets, read once at
  bootstrap through a swappable adapter.
- **GitHub**: the repository; clusters read it with a read-only key.

**Deferred features** (named now, built after the base platform): backups with VolSync,
observability with VictoriaMetrics, per-app resource quotas.

## How it fits together

```
Git (or local OCI in dev) ──► Flux ──► platform: secrets, certificates, ingress, templates, Postgres, identity
                                  └─► apps: each in its own namespace, created from its requests
OpenTofu (workstation) ──► Cloudflare tunnel, fence, zone · B2 bucket ──► outputs into the vault ──► ESO ──► cluster

a person ──► Cloudflare access fence ──► tunnel ──► Traefik ──► authentik sign-in ──► app
app ──► its own secrets (OpenBao) · its own database (shared Postgres) · its own hostnames (external-dns)
```

## Where to read next

- `docs/adr/`: every decision, with its reasons and the alternatives rejected.
- `docs/agents/harness.md`: how the AI agent is set up and how its flows compose.
- `docs/operator-setup.md`: the steps only the operator can do.
- GitHub Issues: the backlog. The wayfinder map issue indexes the open decisions.
