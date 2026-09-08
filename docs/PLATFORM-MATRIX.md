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
| Memory bandwidth | **273 GB/s**, fixed — a property of the soldered LPDDR5X configuration |
| GPU detail | 6,144 CUDA cores, 48 RT cores, Vulkan 1.4 |
| Networking | 10 GbE + **ConnectX-7 dual 200GbE QSFP** — present on every unit. See the note below before probing for it |
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

### Networking: the ConnectX-7 is present but does not enumerate — do not re-probe

**Every DGX Spark, including the HP ZGX Nano G1n, has ConnectX-7 dual 200GbE QSFP networking.**
It is simply **inactive**, and it is not reachable by any obvious probe path. Networking is NOT a
vendor variable.

The full spec matrix — both units side by side, including this line — has been in **`README.md`
(the "System Info" section, the `Wired net` row)** since commit `8d0480c`:

```
| Wired net | 10 GbE RJ-45 + ConnectX-7 dual QSFP (200 Gbps)
           | Realtek RTL8127-CG 10 GbE + ConnectX-7 dual 200GbE QSFP112 |
```

The naive probes look like a flat contradiction and are not:

```
lspci                  -> NVMe, Realtek 10ec:8127, MediaTek MT7925, GPU, NVIDIA bridges.
                          NOTHING from vendor 15b3.
/sys/class/infiniband  -> does not exist
lsmod                  -> mlx5_core, mlx5_ib, mlxfw, ib_core, ib_uverbs ALL LOADED
```

Drivers loaded with no visible device reads like "this variant omits the NIC". It is not that. An
inactive device that never enumerates on PCI produces exactly this picture.

> **Do not re-derive the ConnectX story from `lspci`, `lsmod` or `/sys/class/infiniband`.** The
> absence is expected and means nothing. If you actually need the device, ask AGB for the probe
> path rather than rediscovering that the obvious ones do not work.

**How this went wrong, twice.** Two agents have now run this investigation and reached the same
dead end. The second was me, on 2026-09-08: I ran `lspci`, saw no `15b3`, and wrote it up as an
"open discrepancy" contradicting AGB's account — **without reading `README.md`, which had the
answer in a spec table the whole time.** CLAUDE.md's first instruction is to read the README. The
failure was not the probe; it was preferring a fresh measurement over the log this project exists
to maintain. When a stated fact seems to conflict with a quick probe, **read the log before
doubting the human** — the probe is the thing more likely to be incomplete.

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
