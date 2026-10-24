# 0012 Deletion safety under Flux

Date: 2026-10-24

## Context

Flux garbage-collects a Kustomization's objects when the Kustomization is deleted, unless told
otherwise, and prunes objects that leave the source. With one engine owning Postgres, OpenBao's
storage and the certificates, a mistaken deletion would cascade.

## Decision

From day one:

- every Kustomization that owns stateful objects sets deletionPolicy to Orphan;
- every stateful object (Postgres clusters, volumes and claims, OpenBao, the CA secret) carries the
  Flux prune-disabled annotation;
- the platform templates emit both, so apps cannot forget them;
- suspend is the sanctioned way to pause reconciliation during a risky change.

## Consequences

- Removing an app from Git stops managing its data; a person deletes the data afterwards.
- These settings are part of the KRO prototype acceptance (ADR 0003).
