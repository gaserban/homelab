# 0009 Database: one CloudNativePG cluster, a Database and a DatabaseRole per app

Date: 2026-10-24

## Context

A per-app Postgres, which the inspiration repositories run, costs memory on a 16 GB box.
CloudNativePG 1.25 added a standalone Database object and 1.30 (June 2026) added a standalone
DatabaseRole object, so an app's template can create both without editing the shared Cluster.

## Decision

One shared CloudNativePG cluster per environment. The platform template creates a DatabaseRole and
a Database owned by it for each app that requests one. pgAdmin reads every database through an
explicit platform grant.

## Consequences

- A managed.roles entry on the Cluster wins over a DatabaseRole of the same name; the platform
  keeps managed.roles empty except for its own accounts.
- A DatabaseRole is reconciled only when its spec or password Secret changes; manual drift is not
  reverted. Documented, not fought.
- Reclaim policy is retain for both objects, so removing an app keeps its data until a person
  deletes it.
