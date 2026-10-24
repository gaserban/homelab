# 0006 Storage: Longhorn, one replica until more nodes

Date: 2026-10-24

## Context

Prod starts on one node and will grow. A local-path provisioner binds volumes to one disk and
forces a migration when node two arrives. Rook-Ceph expects three nodes and much more memory.
OpenEBS's replicated engine wants dedicated cores. miroir has one maintainer.

## Decision

Longhorn from day one with replica count one, raised as nodes arrive. Talos images include the two
extensions Longhorn needs. Durability comes from backups (ADR 0011); replication later buys
availability, not safety.

## Consequences

- Usable space is raw space divided by replica count once replication is on.
- Replication traffic wants gigabit at least; the mini-PC's second LAN port can be dedicated to it.
- The 512 GB disk is the tighter resource; a second disk or the future NAS relieves it.
