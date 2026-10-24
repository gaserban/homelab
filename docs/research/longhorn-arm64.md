# Longhorn on arm64

Checked 2026-10-24 against **Longhorn v1.13.0**, the current stable release (published
[2026-09-29](https://github.com/longhorn/longhorn/releases/tag/v1.13.0)). The v1.12.2-rc1 release
candidate is newer, but it is a pre-release. This note answers what
[ADR 0006](../adr/0006-storage-longhorn.md) relies on: that Longhorn runs on every node this cluster
might have, and that it meets the repo's amd64 + arm64 image rule.

Scope: this is a targeted check on an existing decision, not a full adopt-or-build review. ADR 0006
already chose Longhorn, so the note covers only the multi-architecture item of the checklist in
[harness.md](../agents/harness.md) and gives no verdict.

## Short answer

- **Yes, arm64 is supported and generally available (GA).** It came in as experimental in v1.1.0
  (December 2020) and became GA in v1.4.0 (December 2022).
- **Every image in the v1.13.0 image list is multi-architecture.** That includes the CSI sidecars,
  the backing-image manager and the share-manager (the RWX image). Each image's manifest list
  includes `linux/amd64` and `linux/arm64`.
- **The default path (V1 data engine) has no arm64-specific prerequisites.** Two caveats are worth
  knowing:
  - The V2/SPDK engine has an open arm64 I/O-hang bug with NVMe-driver disks.
  - There is an open, unfixed backup crash on arm64 kernels that use 16K pages (reported on Apple
    Silicon / Asahi; the Raspberry Pi 5 may be affected too, unverified).
- **Mixed amd64 + arm64 clusters are not documented as supported or unsupported.** Multi-arch
  images let each node pull its own variant, but I found no first-party statement that covers
  replicas spread across both architectures.

## Findings

### Support status and history

- v1.1.0 release notes: "ARM64 support (experimental). Longhorn now supports ARM64 architecture in
  addition to AMD64. You can deploy Longhorn as usual in ARM64 without any modification."
  ([release v1.1.0](https://github.com/longhorn/longhorn/releases/tag/v1.1.0), published 2020-12-18).
- v1.4.0 release notes: "ARM64 has been experimental from Longhorn v1.1.0 ... ARM64 distribution has
  been stabilized with quality as per our regular regression testing, so it is qualified for general
  availability." ([release v1.4.0](https://github.com/longhorn/longhorn/releases/tag/v1.4.0),
  published 2022-12-30; tracked in [#4206](https://github.com/longhorn/longhorn/issues/4206),
  milestone v1.4.0. The goal of #4206 was to make "the coverage and testing result of arm64 ...
  consistent with amd64").
- The current docs list exactly two supported architectures: "Longhorn supports the following
  architectures: 1. AMD64 2. ARM64"
  ([Best Practices, Architecture, v1.13.0](https://longhorn.io/docs/1.13.0/best-practices/#architecture);
  [source](https://github.com/longhorn/website/blob/master/content/docs/1.13.0/best-practices.md)).
  32-bit ARM is not in that list. Maintainers noted a 32-bit-only volume-size limit back in
  [#1847](https://github.com/longhorn/longhorn/issues/1847).

### Images (Docker Hub manifests inspected directly)

I took the image list from
[`deploy/longhorn-images.txt` at v1.13.0](https://github.com/longhorn/longhorn/blob/v1.13.0/deploy/longhorn-images.txt).
I read each image's manifest from the Docker Hub registry API (`registry-1.docker.io/v2/<repo>/manifests/<tag>`,
with an anonymous pull token) on 2026-10-24. Platforms listed (`unknown`/attestation entries dropped):

| Image | Platforms |
|---|---|
| `longhornio/longhorn-manager:v1.13.0` | linux/amd64, linux/arm64 |
| `longhornio/longhorn-engine:v1.13.0` | linux/amd64, linux/arm64 |
| `longhornio/longhorn-instance-manager:v1.13.0` | linux/amd64, linux/arm64 |
| `longhornio/longhorn-ui:v1.13.0` | linux/amd64, linux/arm64 |
| `longhornio/longhorn-share-manager:v1.13.0` (RWX) | linux/amd64, linux/arm64 |
| `longhornio/backing-image-manager:v1.13.0` | linux/amd64, linux/arm64 |
| `longhornio/longhorn-cli:v1.13.0` | linux/amd64, linux/arm64 |
| `longhornio/support-bundle-kit:v0.0.98` | linux/amd64, linux/arm64 |
| `longhornio/csi-attacher:v4.13.0` | linux/amd64, linux/arm64, linux/arm/v7, linux/s390x |
| `longhornio/csi-provisioner:v6.3.0` | linux/amd64, linux/arm64, linux/arm/v7, linux/s390x |
| `longhornio/csi-resizer:v2.2.1` | linux/amd64, linux/arm64, linux/arm/v7, linux/s390x |
| `longhornio/csi-snapshotter:v8.6.0` | linux/amd64, linux/arm64, linux/arm/v7, linux/s390x |
| `longhornio/csi-node-driver-registrar:v2.18.0` | linux/amd64, linux/arm64, linux/arm/v7, linux/s390x, windows/amd64 |
| `longhornio/livenessprobe:v2.20.0` | linux/amd64, linux/arm64, linux/arm/v7, linux/s390x, windows/amd64 |

The Longhorn-built images are OCI image indexes. The CSI sidecars are Longhorn's mirrors of the
upstream Kubernetes CSI images; they are Docker manifest lists and carry the upstream platform set.
The `longhornctl`
preflight CLI also ships an arm64 binary
([install docs, v1.13.0](https://longhorn.io/docs/1.13.0/deploy/install/)).

To re-check a tag:

```sh
repo=longhornio/longhorn-manager; tag=v1.13.0
tok=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" | jq -r .token)
curl -s -H "Authorization: Bearer $tok" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://registry-1.docker.io/v2/$repo/manifests/$tag" | jq -r '.manifests[].platform | "\(.os)/\(.architecture)"'
```

### Prerequisites (same on both architectures)

- V1 data engine (the default): `open-iscsi` installed and `iscsid` running on all nodes. Open-iscsi
  2.1.12 should be avoided. An NFSv4 client (4.1 for RWX; v4, 4.1 or 4.2 for NFS backup targets) is
  needed on each node. `cryptsetup` and device-mapper are needed only for encrypted volumes
  ([install requirements, v1.13.0](https://longhorn.io/docs/1.13.0/deploy/install/)). The docs give
  no arm64-specific V1 requirement. The only CPU-specific line is "AMD64 CPUs require SSE4.2
  instruction support" ([Best Practices](https://longhorn.io/docs/1.13.0/best-practices/)).
- Minimum recommended hardware (V1): 3 nodes, 4 vCPUs per node, 4 GiB per node, SSD/NVMe preferred
  ([Best Practices](https://longhorn.io/docs/1.13.0/best-practices/)). The minimums are the same for
  both architectures. ADR 0006's one-node, one-replica start is below the recommended three nodes.
  That is a choice the ADR makes on purpose, not an arm64 issue.
- Talos: needs the `siderolabs/iscsi-tools` and `siderolabs/util-linux-tools` extensions, plus a
  kubelet `extraMounts` bind of `/var/mnt/longhorn` (`rshared`) on Talos v1.10+. The page says
  nothing architecture-specific
  ([Talos Linux support, v1.13.0](https://longhorn.io/docs/1.13.0/advanced-resources/os-distro-specific/talos-linux-support/)).
  These are "the two extensions" ADR 0006 refers to. Talos 1.13.4 is on the v1.13.0 verified-OS
  list; the list does not say which architectures were tested
  ([Best Practices, OS](https://longhorn.io/docs/1.13.0/best-practices/#operating-system)).
- V2 data engine (SPDK, optional): "AMD64 or ARM64 CPU". It also needs:
  - kernel 6.7+;
  - the `vfio_pci`, `uio_pci_generic` and `nvme-tcp` kernel modules;
  - 2 GiB of 2 MiB huge pages per node;
  - one extra CPU core per node.

  ([install, V2 requirements](https://longhorn.io/docs/1.13.0/deploy/install/);
  [Best Practices](https://longhorn.io/docs/1.13.0/best-practices/)). On Talos, every node must meet
  the V2 prerequisites before V2 volumes can be used
  ([Talos page](https://longhorn.io/docs/1.13.0/advanced-resources/os-distro-specific/talos-linux-support/)).
  `longhornctl --enable-spdk` failing on arm64 was fixed in v1.10.0
  ([#11551](https://github.com/longhorn/longhorn/issues/11551)).

### arm64-specific limitations

- **V2 + NVMe-driver disks on arm64 can hang I/O.** The v1.13.0 release notes, under "ARM64
  NVMe-backed Block-Type Node Disk Limitation", say: "On ARM64 systems, V2 volumes may experience
  stuck I/O when SPDK is configured with two or more CPU cores and node disks use the NVMe driver."
  The workaround is AIO-backed node disks
  ([release v1.13.0](https://github.com/longhorn/longhorn/releases/tag/v1.13.0)). The tracking issue
  is open, in the Backlog, with root cause unknown (kernel or SPDK suspected)
  ([#13243](https://github.com/longhorn/longhorn/issues/13243)). v1.13.0 also fixed an arm64/AIO
  write stall for sharded/EC volumes
  ([#13789](https://github.com/longhorn/longhorn/issues/13789), listed in the same release notes).
  None of this affects the default V1 engine.
- **16K-page arm64 kernels: backup crash, unresolved.**
  [#12929](https://github.com/longhorn/longhorn/issues/12929) reports the backup engine hitting a
  SIGSEGV at `deltablock.go:160` on aarch64 with a 16K-page kernel (Fedora Asahi Remix on Apple
  Silicon, Longhorn v1.11.1). It is open, in the Backlog, labelled `help wanted`. A maintainer
  (derekbit) said there was no bandwidth to investigate before v1.12.0. The v1.11.2 backport
  ([#12930](https://github.com/longhorn/longhorn/issues/12930)) was closed by a bot as "not
  planned", so no fix has shipped. I found no Longhorn issue that names the Raspberry Pi 5. If its
  default kernel uses 16K pages (not checked against a Raspberry Pi source here), the same risk
  applies by analogy and Pi 5 nodes would need a 4K-page kernel. The page size of Talos arm64
  images is also unverified (see open questions).
- There is a long-standing open task to document node page-size configuration in the best-practices
  page ([#4592](https://github.com/longhorn/longhorn/issues/4592)). The current docs say nothing
  about page size for V1.

### Mixed amd64 + arm64 clusters

- No Longhorn doc page or release note says mixed-architecture clusters are supported or
  unsupported. The architecture section lists both architectures and nothing more
  ([Best Practices](https://longhorn.io/docs/1.13.0/best-practices/#architecture)).
- Longhorn's DaemonSet images are multi-arch indexes (table above), so the scheduling works: each
  node pulls its own platform variant. Replica traffic goes over the network between engine and
  replica processes, so nothing obviously ties it to an architecture. That is my inference, not a
  documented guarantee.
- The only first-party issues that mention mixed architecture are unrelated bugs in mixed
  Raspberry Pi clusters (for example [#2386](https://github.com/longhorn/longhorn/issues/2386), an
  engine image stuck in deploying because of taint timing). None of them reports
  cross-architecture replica or data incompatibility.

## Open questions / not verified

- **Mixed-arch replica sets.** I found no first-party statement or test plan saying that one
  volume's replicas on amd64 and arm64 nodes (and rebuilds between them) are tested together. Worth
  asking in longhorn/longhorn Discussions, or testing once node two arrives.
- **Whether Longhorn's arm64 regression testing covers Talos.** The verified-OS list does not say
  which architecture each entry was tested on.
- **Raspberry Pi 5 specifically.** Not tested by Longhorn as far as I can find. The 16K-page risk is
  inferred from #12929 (Asahi), not reported on a Pi.
- **Page size of Talos arm64 kernels.** Not checked against Sidero's sources in this pass.
- **Whether the V1 engine is fully safe on 16K-page kernels outside backups.** #12929 covers only
  the backup path.
- **Helm chart defaults.** I did not check whether the v1.13.0 chart's default image tags match
  `longhorn-images.txt` exactly. They normally do, but check before pinning.
