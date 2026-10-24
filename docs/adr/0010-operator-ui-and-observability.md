# 0010 Operator UI: Headlamp with the Flux plugin; observability deferred to VictoriaMetrics

Date: 2026-10-24

## Context

Flux has no built-in UI (ADR 0002). Portainer Community Edition was considered: it is a second hand
on the cluster (its purpose is editing workloads from a UI), it has no OIDC login in the free
edition, and it knows nothing about Flux objects. The design had no observability component at all.

## Decision

- Headlamp (CNCF sandbox) with the Flux plugin, logged in through authentik; Kubernetes RBAC
  decides what the logged-in person may see or do. Read-only by default. metrics-server with it for
  live CPU and memory. The Flux Operator's own web UI is the lighter fallback.
- Observability is a named, deferred feature: VictoriaMetrics single-node as the
  Prometheus-compatible store, feeding Headlamp's charts, Grafana and future dashboard tiles. It
  comes after the base platform.

## Consequences

- The people-facing landing page (Homepage, later in-house) is a separate thing for a separate
  audience; an operator tile there reads the same metrics store.
- kube-prometheus-stack is deliberately not used on this hardware.
