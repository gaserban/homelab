# Architecture decision records

One file per decision. Status is Accepted unless stated. Dates are when the decision was made.
Supersede by adding a new ADR and marking the old one Superseded; never edit a decision in place.

| ADR | Decision |
| --- | --- |
| [0001](0001-public-repo-and-ruleset.md) | The repo is public because the branch ruleset needs it |
| [0002](0002-gitops-engine-flux.md) | GitOps engine: Flux via the Flux Operator |
| [0003](0003-apps-request-platform-provides-kro.md) | Apps request, platform provides: KRO behind a prototype gate |
| [0004](0004-environments-and-dev-loop.md) | Environments: kind dev synced from a local artifact, qa deferred, Talos prod |
| [0005](0005-dev-container-runtime.md) | Dev container runtime: Podman first, with a tested fallback ladder (result: rung 1, kind on rootless Podman, ADR 0018) |
| [0006](0006-storage-longhorn.md) | Storage: Longhorn, one replica until more nodes |
| [0007](0007-external-resources-and-interfaces.md) | External resources: OpenTofu, HCP Terraform, external-dns; one interface per external purpose |
| [0008](0008-secrets.md) | Secrets: OpenBao in-cluster; root secrets from the vault via a bootstrap adapter |
| [0009](0009-database.md) | Database: one CloudNativePG cluster, a Database and a DatabaseRole per app |
| [0010](0010-operator-ui-and-observability.md) | Operator UI: Headlamp with the Flux plugin; observability deferred to VictoriaMetrics |
| [0011](0011-backups-deferred.md) | Backups: VolSync, deferred until the base platform works |
| [0012](0012-deletion-safety.md) | Deletion safety under Flux |
| [0013](0013-github-access-and-merge-guard.md) | GitHub access through an App; the merge is the operator's alone |
| [0014](0014-agent-harness.md) | The Claude Code harness: sandbox, skills, hooks, memory, flows (router bullet superseded by 0015, gate clause by 0016, runtime sentence by 0018) |
| [0015](0015-skill-visibility-and-routing.md) | Skill visibility by the documented rule; the hl-flow router retired; two flow tiers (three passages superseded by 0016) |
| [0016](0016-engineer-flow-and-skill-divergence.md) | The engineer flow ends at tickets; divergences from downloaded skills climb a ladder |
| [0017](0017-downloaded-skills-restored-not-committed.md) | Downloaded skills are restored per checkout from skills-lock.json, not committed |
| [0018](0018-dev-runtime-user-and-sandbox-tunnel.md) | Dev runtime: rootless Podman under its own user, reached from the sandbox through SSH |
| [0019](0019-monorepo-on-bazel.md) | Monorepo on Bazel; tools from Bazel; languages wired when first used |
