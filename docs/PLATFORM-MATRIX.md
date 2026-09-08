# Platform matrix — what a result here generalises to

Written 2026-09-08, when the Spark Game Launcher planning made it necessary to state precisely
which facts are properties of *the platform* and which are properties of *this box*.

## DGX Spark: a fixed platform

Every DGX Spark is the same machine. Vendors differ; the silicon does not.

| | |
|---|---|
| SoC | **NVIDIA GB10** Grace-Blackwell, always |
| CPU | 20 ARM64 cores — 10 × Cortex-X925 + 10 × Cortex-A725. **No 32-bit ARM support at all** |
| Memory | **128 GB unified** (LPDDR5X), coherent between CPU and GPU (`free -g` shows ~121 GiB) |
| OS | Linux only. **DGX OS**, an Ubuntu base image from the NVIDIA/Canonical partnership — a single vendor for the image |
| Memory bandwidth | fixed — a property of the soldered LPDDR5X configuration, not a purchasable option |
| Networking | AGB: identical across vendors. **One observation does not fit — see below.** |
| Varies | **storage capacity only**, plus case and branding |

Verified on this unit (HP ZGX Nano G1n, 2026-09-08):

```
nvidia-smi         NVIDIA GB10, driver 580.173.02
lscpu              aarch64; 10 x Cortex-X925 + 10 x Cortex-A725 = 20 cores
lsmem              127.9G total online, 1 NUMA node   (free -g says 121 GiB: kernel reserve)
lsblk              nvme0n1  931.5G  (the 1 TB unit — this is the ONLY real variable)
dmi product_family DGX Spark        dmi sys_vendor  HP
```

Cosmetic vendor differences are real but superficial — AGB's NVIDIA-branded units have no
chassis power LED; HP added one to the front of the ZGX. Nice, and irrelevant to any result.

### Open discrepancy: networking on this unit

**This HP ZGX Nano G1n presents no Mellanox/ConnectX device on PCI at all.** The full `lspci` is
one NVMe controller, a Realtek `10ec:8127` Ethernet controller, a MediaTek MT7925 Wi-Fi part, the
GPU, and NVIDIA PCI bridges. Nothing from vendor `15b3`, and `/sys/class/infiniband` does not
exist.

Yet DGX OS has the whole Mellanox stack **loaded** — `mlx5_core`, `mlx5_ib`, `mlxfw`, `ib_core`,
`ib_uverbs`, `rdma_cm` — which is what you would expect from an image built for a platform that
normally carries a ConnectX NIC.

Three readings, and this unit cannot distinguish them:

1. The HP "Nano" variant genuinely omits the ConnectX/QSFP networking.
2. It is present but disabled in firmware, so it never enumerates.
3. It is attached by some path `lspci` does not show.

If (1), then **networking is a second vendor variable**, not an invariant, and this document
should say so. AGB has NVIDIA-branded units; one command on one of them settles it:

```bash
lspci -nn | grep -i '15b3\|mellanox\|connectx' ; ls /sys/class/infiniband
```

Recorded rather than resolved, because asserting "networking is identical across vendors" while
sitting in front of a machine that appears to contradict it is exactly the kind of unchecked
claim this repo exists to avoid. It has **no bearing on any gaming result** — it is flagged for
accuracy, not because it changes a conclusion.

Verified on this unit: `nvidia-smi` reports `NVIDIA GB10`, driver 580.173.02; `lscpu` reports the
20-core X925/A725 split; `free -g` reports 121 GiB.

**Vendor-independent identification.** DMI reports the *family* regardless of who built the box:

```
/sys/devices/virtual/dmi/id/product_family   ->  DGX Spark
/sys/devices/virtual/dmi/id/sys_vendor       ->  HP
/sys/devices/virtual/dmi/id/product_name     ->  HP ZGX Nano G1n AI Station
```

So `product_family` is the key to detect the platform, and `sys_vendor`/`product_name` are
cosmetic. Anything reading these should key on the family.

### What that buys this log

**A result measured here applies to every DGX Spark, from any vendor.** The usual caveat on a
compatibility log — "worked on my machine, which is not your machine" — does not apply. The only
axes that can differ between two DGX Sparks are storage capacity, driver/OS version, and
installed software. That is a much stronger claim than a normal PC compatibility list can make,
and it is the reason this repo's results are worth publishing.

It is also why re-running a result on a second unit validates nothing: it re-measures the same
variables. Additional units are useful for **capacity** (the 1 TB unit is the binding constraint;
NBA 2K27 alone is 102 GB) and for parking a long run, not for corroboration.

*Provenance:* the fleet-wide uniformity is **AGB's information** (2026-09-08). Public material
corroborates GB10 + 128 GB unified memory across NVIDIA's channel partners (Acer, ASUS, Dell,
Gigabyte, HP, Lenovo, MSI) but does not state per-vendor spec identity outright. Treat the core
spec as solid and the "100% of models" phrasing as AGB's, not as measured here.

## RTX Spark: NOT a fixed platform

The successor is expected to be materially more variable, so nothing above carries over
automatically.

| | |
|---|---|
| Form factor | primarily **laptops**, multiple vendors; desktops planned, including a **Microsoft RTX Dev box** in a DGX-Spark-like desk form |
| Memory | **varies by model** |
| CPU | possibly **binned GB10 parts with reduced core counts** sold cheaper alongside certified ones |
| OS | **Windows** |

*Provenance:* AGB, 2026-09-08, explicitly hedged ("from what I'm able to gather") on the binning.
Not verified here. Treat as a planning assumption, not a fact.

### What that means for the translation knowledge

**Most of this repo's translator findings are not expected to transfer**, and it would be
dishonest to imply otherwise. Windows-on-ARM runs x86-64 through Microsoft's **Prism** emulator,
not FEX-Emu or Box64. So the four Box64 bugs, the FEX 32-bit GLX failure, the x87 tag-word work
and the `a3`-store bug are all findings about *translators that will not be running there*.

What is expected to transfer, in rough order of confidence:

1. **The method** — evidence discipline, differential testing between runtimes, probes with
   answers from a specification rather than from whichever runtime ran first.
2. **Per-title profile structure** — render API, launcher quirks, config files owned by other
   programs, resolution/window traps, DRM and launcher shims. None of that is translator-specific.
3. **GPU/driver-layer behaviour** — Blackwell-generation driver quirks, DLSS/NGX, Vulkan
   extension availability.
4. **CPU-semantics probes** — `tools/isa-probe/` asks questions whose correct answers come from
   the Intel SDM. Pointed at Prism they would be a fresh, valid test suite on day one.

What almost certainly does **not** transfer: anything naming FEX, Box64, Proton, DXVK, VKD3D,
Wine, or `binfmt_misc`.

## Target priority for the launcher (AGB, 2026-09-08)

**The DGX Spark is the primary and only committed target.** RTX Spark is a *nice-to-have* —
same core platform, and NVIDIA bills it as "game ready", so it is worth not painting into a
corner, but it is not worth paying for upfront.

The practical rule that follows: **do not buy portability with abstraction you cannot yet
test.** A platform-abstraction layer written speculatively against hardware nobody has, for an
emulator (Prism) whose behaviour is unmeasured, is the kind of design that ages badly and slows
the thing that actually matters today. Instead:

- Pick a toolkit and a database that *can* run on Windows/ARM64, and confirm that at selection
  time. That is a one-off check, not an ongoing tax.
- Keep the seams honest and cheap: host-class as a data-model dimension (it costs one column),
  and platform-specific logic behind ordinary function boundaries rather than a framework.
- Ship the DGX Spark experience first and completely. A launcher that is excellent on the
  platform that exists beats one that is mediocre on two, one of which is hypothetical.

## Consequences for the Spark Game Launcher

- **Host profile must be a first-class dimension of the data model.** On DGX Spark it collapses
  to a constant, which is a pleasant special case — not a reason to omit the dimension.
- A game profile's **runtime/thunk section is host-class-specific** and must be keyed by host
  class (`dgx-spark-linux`, `rtx-spark-windows`, …), while identity, binary facts and most
  workarounds are shared.
- Detect the platform from DMI `product_family`, never from the vendor string.
- On RTX Spark, **core count and memory become real variables** and a performance result must
  record them. On DGX Spark they are constants and need recording only for provenance.
