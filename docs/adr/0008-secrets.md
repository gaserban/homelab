# 0008 Secrets: OpenBao in-cluster; root secrets from the vault via a bootstrap adapter

Date: 2026-10-24

## Context

Everything that must exist before OpenBao does (OpenBao recovery material, the B2 and Cloudflare
credentials, the Git read key) needs a home outside the cluster. The operator's password manager
is Proton Pass on the Family plan, which includes the pass-cli tool. External Secrets Operator has
no Proton Pass provider and Proton documents no REST API, so nothing in the cluster can sync from it
continuously.

## Decision

- OpenBao is the in-cluster store; External Secrets Operator moves secrets from it to workloads. A
  ClusterSecretStore name is the only thing an app's template references.
- The few root secrets live in Proton Pass. The bootstrap step runs the vault adapter (pass-cli
  today) on the workstation, fetches them once, and creates them in the cluster. This is the one
  sanctioned push into a cluster.
- A secret rotated in the vault reaches the cluster when the seed step is rerun. Accepted, because
  root secrets rotate rarely.

## Consequences

- The adapter boundary (ADR 0007) lets the root secrets move to an ESO-supported manager later
  without touching anything else.
- OpenBao's data is inside the backups, so a rebuild restores every non-root secret from backup.
- A single long-lived credential that can read every environment's secrets must not exist: one
  vault entry set per environment.
