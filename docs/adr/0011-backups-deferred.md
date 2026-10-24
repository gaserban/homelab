# 0011 Backups: VolSync, deferred until the base platform works

Date: 2026-10-24

## Context

The first draft ran restic through Argo Workflows. The two maintained restic-based operators are
VolSync (Red Hat, released 2026-10-21) and K8up (VSHN, released 2026-10-22). The inspiration
repositories moved to a one-maintainer tool, which is not copied.

## Decision

VolSync is the intended implementation: each app's request declares what it owns, the template
emits the backup objects, and restore-on-create refills a volume from its last backup. Target: the
B2 bucket (ADR 0007), with the NAS as a second local target when it exists. Argo Workflows leaves
the design. Backups are built after the base platform, but the request schema reserves the backup
field now.

## Consequences

- Until built, "rebuildable from nothing" holds for configuration but not for data.
- CloudNativePG uses its own backup path to the same bucket.
