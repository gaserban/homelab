# 0003 Apps request, platform provides: KRO behind a prototype gate

Date: 2026-10-24

## Context

An app should declare what it needs (namespace, hostnames, a place for secrets, a login, a
database, later backups and quotas) and never create the real objects itself. KRO (Kubernetes
Resource Orchestrator, a Kubernetes SIG Cloud Provider subproject, v0.9.4 stable in September
2026) turns a small request into the full set of objects from a platform-owned template. Its API is
still v1alpha1 and the maintainers warn of breaking changes. The two active inspiration
repositories achieve a weaker version of the same pattern with Kustomize components plus
substitution variables.

## Decision

KRO is the intended mechanism, behind a gate: one real app goes through one KRO template in dev,
including the least-privilege fence (the deploying identity may create only KRO instances in its
namespace), before anything else is built on KRO. If it disappoints, Kustomize components are the
fallback and the request schema is kept the same.

## Consequences

- The request schema is the product. It reserves fields for deferred features (backup, quotas)
  from the start so apps declare them before anything acts on them.
- KRO sets no owner references by default; health of instances is expressed with a CEL readiness
  expression in Flux.
- In-cluster components behind the templates (Traefik, authentik, CloudNativePG, Longhorn,
  OpenBao) are fixed choices; the templates hide them from apps, so no further interface is built.
