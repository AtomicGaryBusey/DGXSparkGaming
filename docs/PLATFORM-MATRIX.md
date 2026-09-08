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

### Networking: SETTLED — do not re-probe this

**The Mellanox/ConnectX hardware IS present on the ZGX Spark. It is simply not active, and it
does not appear on any obvious probe path.** (AGB, 2026-09-08, from a prior investigation with
another agent.) Networking is therefore **not** a vendor variable — the platform invariants above
stand as written.

This is recorded because the naive probes look like a contradiction and are not:

```
lspci                     -> NVMe, Realtek 10ec:8127, MediaTek MT7925, GPU, NVIDIA bridges.
                             NOTHING from vendor 15b3.
/sys/class/infiniband     -> does not exist
lsmod                     -> mlx5_core, mlx5_ib, mlxfw, ib_core, ib_uverbs ALL LOADED
```

Drivers loaded with no device visible reads like "this variant omits the NIC". It is not that.
An inactive device that never enumerates on PCI produces exactly this picture.

**This exact investigation has now been run twice by two different agents**, reaching the same
dead end both times, because the negative result was never written down. That is the same failure
this repo hit when two probes were rebuilt from scratch after living outside version control. So:

> **Do not re-derive the ZGX networking story from `lspci`, `lsmod` or `/sys/class/infiniband`.**
> The absence is expected. If you actually need the device, ask AGB for the probe path rather
> than rediscovering that the obvious ones do not work.

It has no bearing on any gaming result.

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
