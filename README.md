# DGX Spark Steam Gaming Setup

## Status

| Component | Status | Version (as of 2026-09-05) |
|-----------|--------|---------|
| NVIDIA driver | Verified | 580.173.02 open kernel — **stay on the 580 branch**, see [Driver Branch Policy](#driver-branch-policy) |
| Vulkan (modeset=1) | Verified | Vulkan 1.4.312 / NVIDIA GB10 |
| FEX-Emu | Installed | `fex-emu-armv8.4` 2607 + `fex-emu-wine` 2608 (PPA) |
| Steam | Installed + Launched | client auto-updated 2026-09-05 |
| Box64 | Installed | **v0.4.4** (Dynarec, armv9.2-a) |
| Proton | Configured | **11.0-2c** x86-64 (keeps DLSS); 11.0-2c ARM64 + 10.0-4b also installed — see [Which Proton](#which-proton-on-arm64) |
| DLSS | Working | **DLSS 4 + MFG**. DLSS 5 is **not reachable** — see [DLSS 5 Status](#dlss-5-status-2026-09-05) |

> This table is the **reference configuration** proven on the DGX Sparks (target versions). For
> the live bring-up state of a given machine, run the [Prerequisites Checklist](#prerequisites-checklist).

## Stack Currency (2026-09-05)

Every layer re-checked against upstream on **5 Sep 2026**. "Latest" is not automatically "take it" —
the driver row is a deliberate hold.

| Layer | Running here | Latest upstream | Action |
|-------|--------------|-----------------|--------|
| NVIDIA driver | 580.173.02 (open kernel) | 610.57.04 (new-feature) / 595.99.02 (production) | **Hold at 580** — see [Driver Branch Policy](#driver-branch-policy) |
| NVIDIA HWE kernel | 6.17.0-1032-nvidia | same | Updated 2026-09-05 (reboot pending); `linux-modules-nvidia-580-open` bumped in lockstep |
| FEX-Emu | `fex-emu-armv8.4` 2607 + `fex-emu-wine` 2608 | FEX-2608 | PPA candidate = installed. `armv8.4` is the highest PPA variant and is the right one for ARMv9.2 Cortex-X925 |
| Box64 | **v0.4.4** (was v0.4.3) | v0.4.4 (2026-08-02) | Rebuilt from source 2026-09-05. A `v0.4.5-1` git tag exists but is **not** a published release — don't chase it |
| Proton | **11.0-2c x86-64** (+ 11.0-2c ARM64, 10.0-4b) | 11.0-2 (2026-08-21) | Bundles FEX-2607, DXVK 2.7.1, VKD3D-Proton 3.0a, dxvk-nvapi 0.9.2. Installed 2026-09-05; Experimental retained |
| Steam client | auto-updated 2026-09-05 | — | Self-updates on launch (~460 MB after a long gap) |
| DLSS | **4 + Multi-Frame Generation** | DLSS 5 (2026-09-03) | **DLSS 5 unreachable** — see below |

### DLSS 5 Status (2026-09-05)

**Verdict: DLSS 5 cannot be enabled on a GB10 today.** It launched 3 Sep 2026 (NBA 2K27 first).
Four independent blockers, any one of which is on its own sufficient:

1. **No Linux driver exists.** DLSS 5 requires **Game Ready 616.64** (Windows R616). NVIDIA's Linux
   and Windows branches ship in near-lockstep (e.g. `610.57.04 Linux / 610.88 Windows`), and the
   newest Unix driver — x86_64 *and* aarch64 alike — is **610.57.04** (Ubuntu noble packages
   610.43.02). There is no R615/R616 Unix driver at all. This blocks DLSS 5 on *every* Linux box,
   not just ARM ones.
2. **GB10 is pinned to the 580 branch.** NVIDIA's own `sbsa` CUDA repo tops out at 580.178.04 for
   GB10, DGX OS pins the 580 metapackage, and owners who forced 590+ have bricked Sparks. Even if a
   616 Linux driver existed, GB10 could not take it for a long while.
3. **GB10 is not on the support list.** DLSS 5 is scoped to **GeForce RTX 50 desktop/laptop**. RTX 40
   is excluded "due to hardware constraints", and RTX PRO Blackwell *workstation* parts are still
   documented at the DLSS 4 MFG tier — which is exactly the tier GB10 sits in. GB10 is
   architecturally plausible (5th-gen Tensor Cores, FP4; modders have already back-ported DLSS 5 to
   RTX 40 by patching incompatible CUDA instructions), but plausible is not supported.
4. **Nothing in the Proton stack implements it.** DLSS 5 needs **Streamline 2.14+**. Proton 11.0-2
   bundles dxvk-nvapi 0.9.2, whose newest DLSS driver settings only reach the R595-era NVAPI builds.
   Streamline 2.14 entry points are not there to call.

**What to watch, in dependency order:** an R615/R616 **Linux** driver appears → GB10 lands on a
post-580 branch in NVIDIA's `sbsa` repo → dxvk-nvapi picks up Streamline 2.14. Until the first of
those happens there is literally nothing to test. **TODO:** re-check
[NVIDIA's Unix driver page](https://www.nvidia.com/en-us/drivers/unix/) each quarter.

**Meanwhile DLSS 4 + MFG works, and on this part it is the thing that matters** — see
[Why DLSS 4 Matters](#why-dlss-4-matters). Do not trade it away for a newer Proton.

### Which Proton on ARM64

Valve now ships **two** Proton 11 builds, and on GB10 the choice is a genuine trade-off:

| Build | Steam AppID | Installed as | What it is | DLSS |
|-------|-------------|--------------|------------|------|
| **Proton 11.0** | `4628710` | `proton-11.0-2c-x86_64` | Ordinary x86-64 Proton — the whole stack runs under FEX, exactly as Proton 10 did | ✅ **Yes** |
| **Proton 11.0 (ARM64)** | `4628740` | `proton-11.0-2c-arm64` | Valve's native-ARM64 Wine PE stack with bundled FEX in an **ARM64EC** configuration; only the game's own x86-64 code is translated | ❌ **No** — see below |
| Proton 10.0-4 | `3658110` | `proton-10.0-4b` | What NVIDIA's Cyberpunk-on-Spark guide specifies, and what most results in this log were recorded on | ✅ Yes |

The ARM64 build is the architecturally exciting one — dramatically less CPU translation overhead.
But it loses DLSS, and **not for the reason usually cited.**

#### Why the ARM64 build loses DLSS (diagnosed on this rig, 2026-09-05)

*This is a code-plus-filesystem diagnosis — Proton's own resolution logic read against what is
actually on disk — not yet an in-game observation. The final confirmation is still a **TODO**: launch
a DLSS title under the ARM64 build and check whether the DLSS toggle is greyed out.*

[Proton #9439](https://github.com/ValveSoftware/Proton/issues/9439) (filed Feb 2026, still open)
reports that commit `2ee837e` disabled dxvk-nvapi on aarch64 builds. **That is no longer what ships.**
`proton-11.0-2c-arm64` contains real DXVK-NVAPI binaries and the `proton` script's `use_nvapi` path
is fully intact:

```
files/lib/wine/nvapi/x86_64-windows/nvapi64.dll     # 1.4 MB, PE machine 0x8664, "DXVK-NVAPI"
files/lib/wine/nvapi/x86_64-windows/nvofapi64.dll
files/lib/wine/nvapi/i386-windows/nvapi.dll
```

The break is one layer down, in **NGX resolution**. Proton finds the DLSS DLLs by locating whichever
`libGLX_nvidia.so` it has loaded and looking for a `nvidia/wine/nvngx.dll` *sibling* of it
(`get_nvidia_wine_dir()`, ~line 440 of `proton`); if that file is absent the function returns `None`
and every NGX feature silently disables. The two builds resolve to different drivers:

| | x86-64 Proton | ARM64 Proton |
|---|---|---|
| `libGLX_nvidia.so` it loads | RootFS `…/x86_64-linux-gnu/` | **host** `/usr/lib/aarch64-linux-gnu/` |
| looks for | `…/x86_64-linux-gnu/nvidia/wine/nvngx.dll` | `/usr/lib/aarch64-linux-gnu/nvidia/wine/nvngx.dll` |
| present? | ✅ yes — Step 2 puts it there | ❌ **no such directory** |

NVIDIA ships the `nvidia/wine/` NGX bridge DLLs (`nvngx.dll`, `_nvngx.dll`, `nvngx_dlssg.dll`) **only
in the x86_64 driver package**. The aarch64 driver has no equivalent, so on the native-ARM64 path
there is simply nothing for Proton to find. NVAPI is present; the NGX bridge behind it is not.

**TODO — cheap experiment worth running:** create `/usr/lib/aarch64-linux-gnu/nvidia/wine/` and drop
the x86-64 `nvngx.dll` / `_nvngx.dll` / `nvngx_dlssg.dll` into it, and see whether `get_nvidia_wine_dir()`
is satisfied and DLSS initialises. Expect it to fail — `nvngx.dll` is the Wine-side shim that
`dlopen`s the *Linux* `libnvidia-ngx.so`, so an ARM64 unix side really wants an **ARM64 PE**
`nvngx.dll` that NVIDIA does not ship — but the test costs one directory and confirms whether this is
a packaging gap NVIDIA could close or a genuine architectural wall.

**Default to Proton 11.0 x86-64 (`4628710`) for anything demanding.** On a part whose defining
bottleneck is 273 GB/s of memory bandwidth, losing MFG costs far more than the CPU translation the
ARM64 build saves. Reach for the ARM64 build on CPU-bound titles that never wanted DLSS anyway —
simulation, strategy, older engines — where it should be a clear win. All three are installed here;
pick per-game in Properties → Compatibility.

**TODO:** head-to-head the two Proton 11 builds on one CPU-bound title (Stellaris/Factorio-shaped)
and one GPU-bound DLSS title, and record the split.

### Driver Branch Policy

**Stay on 580.** Not conservatism for its own sake — that is where GB10 support lives:

- NVIDIA's `sbsa` CUDA repo (`developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa`)
  offers **580.65.06 → 580.178.04** and nothing newer. That repo is GB10's actual support channel.
- `ports.ubuntu.com` will happily offer `nvidia-driver-595-open` and `nvidia-driver-610-open` for
  arm64. Those are generic Ubuntu arm64 builds, **not** GB10-validated. DGX Spark owners who took
  them report `nvidia-smi: No devices found` / `NVIDIA-GB10 not supported`.
- `apt upgrade` is safe *as long as it only moves within 580*. Check before confirming:
  ```bash
  apt list --upgradable 2>/dev/null | grep -iE 'nvidia|linux-'
  ```
  Kernel bumps are fine when `linux-image-nvidia-hwe-24.04` and
  `linux-modules-nvidia-580-open-nvidia-hwe-24.04` move **together** — that is what keeps the module
  matched to the kernel. If only one of the two shows up, hold both until the other lands.

### RootFS driver drift (re-sync after every host driver bump)

**This one is silent and easy to miss.** The FEX RootFS carries its own copy of the *x86_64 and
i386* NVIDIA userspace libs — that is how Proton finds `libGLX_nvidia.so.0` and the NGX/DLSS DLLs.
Those copies are made once, by hand, in Step 2. When `apt` later bumps the **host aarch64** driver,
nothing updates the RootFS copies, so the x86 GL/NGX libs Proton loads drift out of sync with the
running kernel driver.

Found on this rig 2026-09-05: host at **580.173.02**, RootFS still at **580.159.03** — a drift
introduced by a routine `apt upgrade` some time after the June bring-up.

Check:
```bash
RF=~/.fex-emu/RootFS/Ubuntu_24_04
cat /sys/module/nvidia/version                                        # host
ls $RF/lib/x86_64-linux-gnu/ | grep -E 'libnvidia-glcore\.so\.[0-9]'  # RootFS — must match
```

Re-sync (same commands as Step 2's manual fix; no sudo needed):
```bash
RF=~/.fex-emu/RootFS/Ubuntu_24_04; ver=$(cat /sys/module/nvidia/version)
cd ~ && wget "https://download.nvidia.com/XFree86/Linux-x86_64/$ver/NVIDIA-Linux-x86_64-$ver.run"
sh NVIDIA-Linux-x86_64-$ver.run -x && cd NVIDIA-Linux-x86_64-$ver
mkdir -p "$RF/usr/lib/x86_64-linux-gnu/nvidia/wine" && cp -f ./*.dll "$_"
for d in *.so.$ver; do cp -f "$d" "$RF/lib/x86_64-linux-gnu/$d"; b=$(echo "$d"|cut -d. -f1-2); \
  (cd "$RF/lib/x86_64-linux-gnu"; ln -sf "$d" "$b.0"; ln -sf "$d" "$b.1"; ln -sf "$d" "$b.2"); done
cd 32; for d in *.so.$ver; do cp -f "$d" "$RF/lib/i386-linux-gnu/$d"; b=$(echo "$d"|cut -d. -f1-2); \
  (cd "$RF/lib/i386-linux-gnu"; ln -sf "$d" "$b.0"; ln -sf "$d" "$b.1"; ln -sf "$d" "$b.2"); done
```

Then delete the superseded version's blobs. Repointing the `.0/.1/.2` symlinks orphans the old
`.so.<oldver>` files, and they are **~1.2 GB per stale version** — which matters on the ZGX Nano's
1 TB drive:
```bash
find $RF/lib/x86_64-linux-gnu $RF/lib/i386-linux-gnu -maxdepth 1 -name "*.so.<oldver>" -delete
find $RF/lib/x86_64-linux-gnu $RF/lib/i386-linux-gnu -maxdepth 1 -xtype l   # must print nothing
```

## System Info

This testing spans two **GB10 Grace Blackwell** machines. The HP ZGX Nano G1n is a variant of
the NVIDIA DGX Spark — both are built on the *same* GB10 superchip and ship NVIDIA DGX OS, so
they are spec-identical at the SoC level (CPU, GPU, memory, AI compute). The differences are in
storage, networking, display outputs, and chassis. **Every compatibility finding in this
document transfers between the two**, since the translation stack runs on the identical SoC.

| Spec | NVIDIA DGX Spark (Founders Edition) | HP ZGX Nano G1n AI Station |
|------|-------------------------------------|---------------------------|
| **SoC** | NVIDIA GB10 Grace Blackwell Superchip | NVIDIA GB10 Grace Blackwell Superchip |
| **CPU** | 20-core Arm: 10× Cortex-X925 + 10× Cortex-A725 (aarch64) | 20-core Arm: 10× Cortex-X925 + 10× Cortex-A725 (aarch64) |
| **GPU** | NVIDIA GB10 Blackwell — 6,144 CUDA cores, 48 RT cores, Vulkan 1.4 | NVIDIA GB10 Blackwell — 6,144 CUDA cores, 48 RT cores, Vulkan 1.4 |
| **AI compute** | 1,000 TOPS FP4 (≈1 petaFLOP) | 1,000 TOPS FP4 (≈1 petaFLOP) |
| **Memory** | 128 GB unified LPDDR5x, 273 GB/s | 128 GB unified LPDDR5x, 273 GB/s |
| **Storage** | 4 TB NVMe M.2 | **1 TB** NVMe M.2 SSD (this unit; HP also offers 2 TB / 4 TB) |
| **Wired net** | 10 GbE RJ-45 + ConnectX-7 dual QSFP (200 Gbps) | Realtek RTL8127-CG 10 GbE + ConnectX-7 dual 200GbE QSFP112 |
| **Wireless** | Wi-Fi 7, Bluetooth 5.3 | Wi-Fi 7 (2×2), Bluetooth 5.4 |
| **Display / USB-C** | HDMI 2.1 + 4× USB-C (1× 240 W PD, DP alt mode) | HDMI 2.1a (8K@30) + 3× USB-C 3.2 @ 20 Gbps with **DisplayPort 1.4a** alt mode (8K@60) |
| **OS** | NVIDIA DGX OS (Ubuntu-based) | NVIDIA DGX OS (Ubuntu-based) |
| **Dimensions** | 150 × 150 × 50.5 mm, 1.2 kg | 150 × 150 × 51 mm |
| **Peak power** | 240 W (GB10 SoC TDP 140 W) | ~228 W |

> **Gaming-relevant difference:** the ZGX Nano exposes **DisplayPort 1.4a** over USB-C alt
> mode, whereas the DGX Spark's only video-out used here was HDMI 2.1a. DP 1.4a supports DSC,
> which may lift the 5120×1440 @ 120 Hz HDMI ceiling noted in [Display Notes](#display-notes) —
> untested, worth trying.

**This test rig (HP ZGX Nano G1n, 1 TB):**
- **Display:** Samsung Odyssey G9 OLED (5120×1440) via HDMI 2.1a
- **OS:** Ubuntu 24.04.4 LTS (Noble Numbat) / DGX OS
- **Driver:** NVIDIA 580.173.02 (open kernel), CUDA 13.0 — *was 580.159.03 at bring-up; see [RootFS driver drift](#rootfs-driver-drift-re-sync-after-every-host-driver-bump)*
- **Kernel:** 6.17.0-1032-nvidia (installed 2026-09-05; 1031 until reboot)
- **Storage:** 1 TB NVMe (~931 GiB usable) — notably smaller than the 4 TB DGX Sparks; game library size is the main practical constraint here

## Architecture

Steam and x86 games run through translation layers on ARM64:

```
Windows Game (x86_64 .exe)
  → Proton/Wine (Win32/DX → Linux/Vulkan)
    → FEX-Emu or Box64 (x86_64 → ARM64 JIT translation)
      → Native ARM64 NVIDIA Vulkan driver (GPU runs natively)
```

GPU shaders run natively — only CPU-side code is translated.

## Prerequisites Checklist

Run these checks to see what a machine still needs before it can run games. Each row links to
the detailed install/fix in **Setup Steps** below. A factory DGX OS box ships with the NVIDIA
driver, CUDA, and the NVIDIA Vulkan ICD already present — but the entire x86 translation stack
(modeset, FEX-Emu, Box64, Steam, Proton) must be installed by hand.

| # | Prerequisite | Verify command | Pass condition | Fix |
|---|--------------|----------------|----------------|-----|
| 1 | NVIDIA driver (open kernel) | `cat /proc/driver/nvidia/version` | shows `580.x` (or newer) | pre-installed on DGX OS |
| 2 | CUDA toolkit | `nvcc --version` | `release 13.0` (or newer) | pre-installed on DGX OS |
| 3 | NVIDIA Vulkan ICD | `ls /usr/share/vulkan/icd.d/nvidia_icd.json` | file exists | ships with driver |
| 4 | `nvidia-drm modeset=1` | `cat /sys/module/nvidia_drm/parameters/modeset` | prints `Y` | Step 1 (reboot) |
| 5 | vulkan-tools | `vulkaninfo --summary \| grep deviceName` | shows `NVIDIA GB10` (not just llvmpipe) | Step 1 — `sudo apt install vulkan-tools` |
| 6 | user in `video`+`render` | `id -nG \| grep -ow 'video\|render'` | both printed | Step 1 — `sudo usermod -aG video,render $USER` |
| 7 | FEX-Emu | `FEXInterpreter --version` | prints a version | Step 2 (autoinstaller) |
| 8 | FEX RootFS + GPU thunk config | `ls ~/.fex-emu/Config.json` | file exists | Step 2 |
| 9 | Steam (under FEX) | `command -v steam` | path printed | Step 2 |
| 10 | Box64 | `box64 --version` | prints `Box64 ... with Dynarec` | Step 3 |
| 11 | x86 binfmt handlers | `ls /proc/sys/fs/binfmt_misc/ \| grep -iE 'box64\|FEX'` | at least one handler | registered by Steps 2–3 |
| 12 | Proton 10.0 (stable) | Steam → Settings → Compatibility | 10.0 selectable | Step 4 |

### Status on the test rig (HP ZGX Nano G1n — 2026-06-18)

Freshly provisioned. Base NVIDIA stack present; **the gaming stack is not yet installed.**

| Prereq | State | Prereq | State |
|--------|-------|--------|-------|
| 1 · NVIDIA driver | ✅ 580.159.03 | 7 · FEX-Emu | ✅ 2605~n (+wine) |
| 2 · CUDA | ✅ 13.0 | 8 · FEX RootFS/Config | ✅ Ubuntu 24.04 + thunks |
| 3 · NVIDIA Vulkan ICD | ✅ present | 9 · Steam | ✅ 1.0.0.81 (ARM64-patched) |
| 4 · modeset=1 | ✅ live (DRM card1) | 10 · Box64 | ✅ v0.4.3 (Dynarec) |
| 5 · vulkan-tools | ✅ GB10 via Vulkan 1.4 | 11 · x86 binfmt | ✅ box64+box32 enabled |
| 6 · video/render groups | ✅ both active | 12 · Proton | ✅ Steam Play working (Experimental) |

**Bring-up COMPLETE (2026-06-18).** All layers verified end-to-end: **Half-Life 2 ran great at
full ultrawide on the GB10 *via Proton*** (DX9 → DXVK; confirmed by the `compatdata/220` prefix —
not the native Linux build). Vulkan graphics live; FEX + RootFS + NGX libs + ARM64-patched Steam;
Box64 v0.4.3 + binfmt; Steam UI signed in and **stable after the `steamwebhelper` crash-loop fix**
(Step 2 launch note — disable Chromium hardware accel in `Local State`).

Two known caveats on this unit:
1. **Proton version:** only **Proton Experimental** is installed and it's the working Steam Play
   default. Selecting **Proton 10.0** (or any non-Experimental) in Settings → Compatibility
   currently triggers the `steamwebhelper` crash (the flaky CEF dropdown), so it can't be picked
   via the GUI. Experimental works and is a near-superset of 10.0; the rest of this log's results
   were on 10.0, so note minor per-title Proton-version variance is possible. To force 10.0 later:
   `steam steam://install/<proton10_appid>` to download it GUI-free, then set
   `CompatToolMapping "0" → "name" "proton_10"` in `config.vdf` (with Steam closed).
2. **Steam UI** still crashes occasionally (known, not-yet-fully-fixed FEX/CEF interaction) — it
   recovers and **does not affect running games** (HL2 kept running through a UI crash). Launch a
   game and a UI hiccup won't interrupt it; minimize store/library browsing to reduce crashes.

### Update — 2026-09-05 (stack refresh)

| Prereq | Was (2026-06-18) | Now |
|--------|------------------|-----|
| 1 · NVIDIA driver | 580.159.03 | **580.173.02** (apt, still 580 branch) |
| — · NVIDIA HWE kernel | 6.17.0-1021 | **6.17.0-1032** — *installed, reboot pending* |
| 7 · FEX-Emu | 2605~n | **2607** (`armv8.4`) + **2608** (`wine`) |
| 8 · FEX RootFS | NVIDIA libs @ 580.159.03 | **re-synced to 580.173.02**; 1.2 GB of orphaned 580.159.03 blobs removed |
| 9 · Steam | 1.0.0.81 | client auto-updated (~460 MB) |
| 10 · Box64 | v0.4.3 | **v0.4.4** (rebuilt from source) |
| 12 · Proton | Experimental only | **11.0 (x86-64), 11.0 (ARM64), 10.0-4** all installed |

Caveat 1 above is **resolved** — the Protons were installed via `steam://install/<appid>`, which
sidesteps the CEF Compatibility dropdown entirely (one Install confirmation click each; AppIDs in
[Which Proton on ARM64](#which-proton-on-arm64)). Caveat 2 (occasional Steam UI crashes) still
stands, and a related trap surfaced: **Steam silently swallows `steam://` URLs while its UI is still
on "Loading user data…"** — under FEX that can take several minutes after launch. Wait for the
library to render before firing them.

Full upstream-vs-installed comparison, and why the driver is deliberately held at 580, are in
[Stack Currency](#stack-currency-2026-09-05).

## Setup Steps

### Step 1: Fix Vulkan Support (requires reboot)

The DGX Spark ships with `nvidia-drm modeset=0` (compute-only default), which prevents Vulkan from initializing the GPU for graphics.

**Changes applied:**

1. Enabled nvidia-drm modesetting:
   ```bash
   sudo sed -i 's/options nvidia-drm modeset=0/options nvidia-drm modeset=1/' \
     /etc/modprobe.d/zz-nvidia-drm-override.conf
   ```

2. Rebuilt initramfs:
   ```bash
   sudo update-initramfs -u
   ```

3. Added user to GPU groups:
   ```bash
   sudo usermod -aG video,render $USER
   ```

4. Installed vulkan-tools for verification:
   ```bash
   sudo apt install -y vulkan-tools
   ```

**After reboot, verify with:**
```bash
vulkaninfo --summary
```
Should show `NVIDIA GB10` with Vulkan 1.4+ (not just `llvmpipe`).

### Step 2: Install FEX-Emu and Steam

Using the NVIDIA-endorsed FEX autoinstaller:
```bash
cd ~
git clone https://github.com/esullivan-nvidia/fex_autoinstall.git
cd fex_autoinstall
bash fex_autoinstall_poc.sh
```

This script handles:
- FEX PPA + `fex-emu-armv8.4` and `fex-emu-wine` packages
- Steam `.deb` from repo.steampowered.com
- FEX RootFS (Ubuntu 24.04 x86_64 sysroot)
- GPU thunking config (`~/.fex-emu/Config.json`) — Vulkan/GL calls bypass emulation
- AppArmor profiles for FEXBash and Steam
- x86_64 NVIDIA driver libs + DLSS DLLs copied into RootFS
- ARM64 patch applied to `/usr/lib/steam/bin_steam.sh`

> **⚠️ Autoinstaller is unreliable (hit on ZGX Nano, 2026-06-18) — root cause + reliable fix.**
> The script runs `FEXRootFSFetcher` from inside a `mktemp -d` working dir and has a
> `trap cleanup EXIT` that does `rm -rf "$TEMP_DIR"`. The RootFS download/extract does not persist
> to `~/.fex-emu/RootFS/`, so when the script exits the **extracted userland is deleted** — you're
> left with a RootFS dir that has the skeleton but **no `bash`, no `libc`, no `ld-linux`**. Then,
> because the dir is empty, the NVIDIA `.so` copy to `$rootfs/lib/x86_64-linux-gnu/` fails (no
> top-level `lib` symlink either), and `set -e` aborts — which also **silently skips the Steam
> ARM64 patch**. Net result: FEX, the fex/Steam `.deb`s, AppArmor, and the NGX wine DLLs install,
> but Steam won't launch — `FEXBash` reports *"Invalid or Unsupported elf file ... misconfigured
> x86-64 RootFS"* because the guest loader/bash are missing.
>
> **Reliable completion — run these manually after the script (no sudo except the Steam patch):**
> ```bash
> RF=~/.fex-emu/RootFS/Ubuntu_24_04
> ver=$(cat /sys/module/nvidia/version)
> # 1. Fetch a RootFS that actually persists (run from $HOME, NOT a temp dir):
> rm -rf "$RF"; cd ~ && FEXRootFSFetcher -y -x          # ~500 MB sqsh -> ~1.2 GB extracted
> #    Verify it took:  test -x "$RF/usr/bin/bash" && find "$RF" -name ld-linux-x86-64.so.2
> # 2. Copy the x86_64 + i386 NVIDIA driver libs into the RootFS (for DLSS/NGX):
> cd ~ && wget "https://download.nvidia.com/XFree86/Linux-x86_64/$ver/NVIDIA-Linux-x86_64-$ver.run"
> sh NVIDIA-Linux-x86_64-$ver.run -x && cd NVIDIA-Linux-x86_64-$ver
> mkdir -p "$RF/usr/lib/x86_64-linux-gnu/nvidia/wine" && cp -f ./*.dll "$_"
> for d in *.so.$ver; do cp -f "$d" "$RF/lib/x86_64-linux-gnu/$d"; b=$(echo "$d"|cut -d. -f1-2); \
>   (cd "$RF/lib/x86_64-linux-gnu"; ln -sf "$d" "$b.0"; ln -sf "$d" "$b.1"; ln -sf "$d" "$b.2"); done
> cd 32; for d in *.so.$ver; do cp -f "$d" "$RF/lib/i386-linux-gnu/$d"; b=$(echo "$d"|cut -d. -f1-2); \
>   (cd "$RF/lib/i386-linux-gnu"; ln -sf "$d" "$b.0"; ln -sf "$d" "$b.1"; ln -sf "$d" "$b.2"); done
> # 3. Apply the Steam ARM64 patch the script never reached:
> cd ~/fex_autoinstall && sudo patch -p1 /usr/lib/steam/bin_steam.sh < patch_steam_for_arm64.patch
> ```
> Verify the whole stack: `FEXBash -c 'uname -m'` → `x86_64` (proves the RootFS loads);
> `ls $RF/lib/x86_64-linux-gnu/libGLX_nvidia.so.0` (Proton `dlopen`s it to find the NGX/DLSS DLLs);
> `grep -c FEXBash /usr/lib/steam/bin_steam.sh` → ≥1.
>
> Harmless: `FEXBash` prints `Unknown configuration option 'X87StrictReducedPrecision' / 'ABILocalFlags'
> / 'ParanoidTSO'` — the shipped `Config.json` carries keys this FEX build (2605) doesn't know; they're ignored.

**Launch Steam:**
```bash
FEXBash steam
```

Note: The desktop shortcut does not work — always launch from terminal via `FEXBash steam`.

> **⚠️ Steam `steamwebhelper` crash-loop on first launch (hit on ZGX Nano, 2026-06-18).** Steam
> may open, then the window closes/reopens endlessly (and the desktop work-area/your terminal may
> shrink each cycle). Root cause: Steam's CEF UI spawns a **GPU process that crashes under FEX**
> (`cef_log.txt`: `GPU process exited unexpectedly: exit_code=8704`), taking the UI down → Steam
> relaunches it forever. Steam's `-cef-disable-gpu` launch flag does **not** propagate to the
> helper, and the in-app setting is unreachable because the UI won't stay open. This is a known
> FEX/Steam-CEF interaction (see [FEX #3900](https://github.com/FEX-Emu/FEX/issues/3900),
> [Valve #9780](https://github.com/ValveSoftware/steam-for-linux/issues/9780)).
>
> **The fix that worked — disable GPU acceleration at the Chromium level** (kill Steam first):
> ```bash
> pkill -9 -f ubuntu12; pkill -9 -f steamwebhelper        # stop the loop
> python3 - <<'PY'
> import json, os, shutil
> p = os.path.expanduser("~/.local/share/Steam/config/htmlcache/Local State")
> shutil.copy(p, p + ".bak")
> d = json.load(open(p))
> d.setdefault("hardware_acceleration_mode", {})["enabled"] = False
> d["hardware_acceleration_mode_previous"] = False
> json.dump(d, open(p, "w"), separators=(",", ":"))
> PY
> ```
> Then relaunch `FEXBash steam` — the UI loads and stays up. The Steam storefront/library then
> renders in software (fine; it's just the UI). **Games are unaffected** — they render through
> Proton/DXVK/VKD3D on the real GPU regardless of this setting.
>
> Contributing mitigations applied first (recommended, but the Local State change is the decisive
> one): disable FEX logging (`~/.fex-emu/Config.json` → `"OutputLog":""`, the FEX-dev mitigation
> for a separate CEF FD-handling crash); remove conflicting `libz/libfreetype/libfontconfig/libdbus-1`
> from `~/.local/share/Steam/ubuntu12_32/steam-runtime` so the helper uses RootFS libs (FEX wiki);
> and wipe `~/.cache/nvidia/GLCache`. Opting into Steam Client Beta did **not** help.

### Step 3: Build Box64 from Source (Cortex-X925 optimized)

```bash
cd ~
git clone https://github.com/ptitSeb/box64.git
cd box64
mkdir build && cd build
cmake .. \
  -DARM_DYNAREC=ON \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBOX32=ON \
  -DBOX32_BINFMT=ON \
  -DCMAKE_C_FLAGS="-march=armv9.2-a+crc+sve2-aes+sve2-bitperm+sve2-sha3+sve2-sm4+memtag+profile"
make -j$(nproc)
sudo make install
sudo systemctl daemon-reload
sudo systemctl restart systemd-binfmt
```

Installs to `/usr/local/bin/box64` with binfmt handlers for x86_64 and i386 ELFs.

> **New in v0.4.4:** `make install` also drops a `box64-configurator` GUI (plus a `.desktop` entry)
> for managing per-application `RCFILE` profiles, and v0.4.4 enables **DynaCache** by default —
> Box64 now caches translated blocks across runs, so second launches start faster. Upgrading in
> place is just `git pull && cd build && cmake .. -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
> && make -j$(nproc) && sudo make install && sudo systemctl restart systemd-binfmt`.

**Verify:**
```bash
box64 --version
# Box64 arm64 v0.4.4 ... with Dynarec
```

### Step 4: Configure Steam for Gaming

1. Use **Proton 11.0 x86-64** (AppID `4628710`) as the default compatibility layer — *not* the
   ARM64 build, which has no NVAPI and therefore no DLSS. See
   [Which Proton on ARM64](#which-proton-on-arm64). Proton 10.0-4 (`3658110`) remains a valid
   known-good fallback and is what NVIDIA's own Spark guide specifies.
2. Enable **DLSS 4 + Multi-Frame Generation** in supported games. DLSS 5 is not reachable on GB10 —
   see [DLSS 5 Status](#dlss-5-status-2026-09-05).
3. Target **5120x1440 @ 120Hz** (HDMI 2.1a limit without DSC on Linux)

**Installing a Proton build without touching the Compatibility dropdown** (that dropdown is the CEF
widget that trips the `steamwebhelper` crash). With Steam *running and fully loaded* — the URL is
silently dropped if the UI is still on "Loading user data…", which costs several confusing retries:
```bash
steam steam://install/4628710   # Proton 11.0  (x86-64 — keeps DLSS)
steam steam://install/4628740   # Proton 11.0 (ARM64) — native, no DLSS
steam steam://install/3658110   # Proton 10.0-4 — known-good baseline
```
Each one raises a single **Install** confirmation dialog you click through — that is all the GUI
involved, and it is not the crashy widget. Confirm with
`ls ~/.local/share/Steam/steamapps/appmanifest_*.acf` and watch
`~/.steam/steam/logs/content_log.txt` for `update finished`.

> **⚠️ Installing a Proton does *not* pull its runtime.** Every Proton declares a
> `require_tool_appid` in its `toolmanifest.vdf`, and a `steam://install` of the Proton alone leaves
> that dependency missing — the game then fails with no useful message. Check and install it too:
> ```bash
> grep require_tool_appid ~/.local/share/Steam/steamapps/common/"Proton 11.0"/toolmanifest.vdf
> ```
>
> | Proton | Requires runtime | AppID | Installed as |
> |--------|------------------|-------|--------------|
> | Proton 10.0-4b | Steam Linux Runtime **3.0 (sniper)** | `1628350` | `SteamLinuxRuntime_sniper` |
> | Proton 11.0 x86-64 | Steam Linux Runtime **4.0** | `4183110` | `SteamLinuxRuntime_4` |
> | Proton Experimental | Steam Linux Runtime **4.0** | `4183110` | `SteamLinuxRuntime_4` |
> | **Proton 11.0 (ARM64)** | Steam Linux Runtime **4.0 - Arm64** | `4185400` | `SteamLinuxRuntime_4-arm64` |
>
> The ARM64 Proton wants a **different, ARM64-specific runtime** — easy to miss, and nothing in the
> Steam UI says so.
>
> **Don't try to run `proton run <game>.exe` directly from a shell** to skip Steam. Proton expects to
> be inside its pressure-vessel runtime container; run bare it prints
> `fsync: up and running` and exits 1 with no log, even with `PROTON_LOG=1`. Launch through Steam.
>
> Harmless noise on first prefix creation:
> `Error while copying to ".../system32/amdxcffx64.dll": No such file or directory` — that copy is
> `optional=True` in the `proton` script and the file is absent from every non-Experimental build.

To set the global default without any GUI at all, close Steam and edit
`~/.local/share/Steam/config/config.vdf` → `CompatToolMapping "0" → "name"`.

## ARM64 Compatibility Guidelines

Games run through a multi-layer translation stack: Game → Proton/Wine → DXVK or VKD3D → FEX-Emu Vulkan thunk → native ARM64 NVIDIA driver. Not all Vulkan extensions are thunked in FEX-Emu, so games that use newer extensions will crash. These guidelines maximize success:

### What Works Best

- **DX11 games** — Translated by DXVK to Vulkan. DXVK uses a mature, well-tested subset of Vulkan that FEX's thunks fully support. This is the sweet spot.
- **Older DX9/DX10 games** — Also go through DXVK, same well-tested path.
- **Proton 11.0 x86-64** — the current default. Supersedes Proton 10.0, which is what the results
  below were recorded on. Keep it x86-64: the ARM64 build drops NVAPI and with it DLSS.

### What Breaks

- **Native Vulkan games** — May use `VK_EXT_descriptor_buffer` and other extensions that FEX's `libvulkan-host.so` doesn't thunk. Calls return null → crash.
- **DX12 games** — Translated by VKD3D-Proton, which may use newer Vulkan extensions (descriptor buffers, etc.) that hit thunk gaps. However, not all DX12 games crash — Witcher 3 Next-Gen DX12 works with full RT and DLSS Frame Gen. The outcome depends on which Vulkan extensions the specific VKD3D-Proton code path uses. Worth testing on a per-game basis.
- **RTX Remix titles** — Dual-process bridge architecture (32-bit client ↔ 64-bit server via shared memory IPC) breaks under x86→ARM64 translation.
- **Proton Experimental** — More aggressive feature usage, less tested on ARM64.
- **Proton 11.0 (ARM64)** for anything GPU-bound — it is fast on the CPU side, and it *does* ship
  dxvk-nvapi, but NGX resolution fails because the aarch64 driver has no `nvidia/wine/nvngx.dll`, so
  DLSS and Frame Generation silently disable
  ([why](#why-the-arm64-build-loses-dlss-verified-on-this-rig-2026-09-05)). On a 273 GB/s part that
  is usually a net loss.

### Key Environment Variables (auto-set by Proton)

- `DXVK_ENABLE_NVAPI=1` — Makes DXVK expose NVIDIA GPU identity (GB10, 93 GB VRAM). Without this, games see "Unknown GPU" or fail detection.
- `Vulkan: 1` in `~/.fex-emu/Config.json` — FEX thunks forward Vulkan calls directly to native ARM64 driver instead of JIT-emulating them. Critical for performance and correctness.
- `fsync` — Wine's futex-based sync, supported by the 6.17 kernel. Active on all working games.

### Troubleshooting Tips

- If a game crashes at startup, try adding `-force d3d11` or `-dx11` to launch options (game-specific flag) to avoid DX12/Vulkan native paths.
- Use **Proton 11.0 x86-64**, not Experimental and not the ARM64 build.
- The `vkGetPhysicalDeviceDescriptorSizeEXT` error in Steam logs is the telltale sign of a FEX thunk gap — the game requires unthunked Vulkan extensions.
- Pressure-vessel Vulkan layer warnings (`nvidia_layers.json not in overrides`) are harmless — they fire on both working and broken games.
- Steam's own GPU topology shows `llvmpipe` — this is normal on ARM64 (the Steam UI runs under FEX). Games inside Proton see the real GPU via DXVK+NVAPI.

## Game Compatibility

### Why DLSS 4 Matters

The GB10's main bottleneck is memory bandwidth (273 GB/s vs ~900+ GB/s on a discrete RTX 5070). Without DLSS, the GPU is bandwidth-starved. With DLSS 4 Multi-Frame Generation, the GPU renders at a lower internal resolution and generates 3 out of every 4 frames via AI on the Tensor Cores — sidestepping the bottleneck entirely. Cyberpunk goes from ~50 FPS to 175+ FPS. DLSS is effectively mandatory for demanding titles.

### Tested by AGB

Games personally tested on this DGX Spark (GB10, Proton 10.0, FEX-Emu, driver 580.126.09).

> These results were recorded on **Proton 10.0 / driver 580.126.09**. The stack has since moved to
> **Proton 11.0-2 / driver 580.173.02** ([Stack Currency](#stack-currency-2026-09-05)); expect minor
> per-title variance and re-verify before treating an old row as gospel.

| Game | API | Performance | Notes |
|------|-----|------------|-------|
| **Age of Empires II DE** | DX11 | Smooth, 39+ min sessions | DX11 via DXVK. GPU detected as NVIDIA GB10 (93 GB VRAM). Clean exits, no crashes. |
| **Balatro** | DX11 | Smooth, fullscreen | No issues. |
| **BioShock Remastered** | DX11 | Smooth, maxed settings | DX11 via DXVK. No issues. |
| **Brotato** | DX11 | Smooth, fullscreen | No issues. |
| **Dark Souls II: Scholar of the First Sin** | DX11 | Smooth, maxed settings | DX11 via DXVK. No issues. |
| **DOOM 64** | KEX | Smooth | KEX engine (SDL2/FMOD). No issues. |
| **DOOM + DOOM II** (remastered) | KEX | Smooth | Non-DOS remastered version. Runs great. |
| **DOOM II** (non-DOS) | KEX | Playable, choppy menus | Non-DOS version. Menus and loading screens choppy, but gameplay itself is smooth. |
| **DOOM (2016)** | Vulkan | Smooth, maxed, 5120x1440 | id Tech 6, native Vulkan renderer. Incredible performance. Confirms id Tech Vulkan works on Spark (id Tech 7/Doom Eternal also works). |
| **Esoteric Ebb** | DX11 | Smooth, maxed settings | Unity 6 (IL2CPP) via DXVK. No issues. |
| **Data Center Demo** | DX11 | Smooth, maxed settings | No issues. |
| **Control** | DX12 | Smooth, near-max, 5120x1440 | Northlight Engine via VKD3D-Proton. Ray tracing on (medium — higher tanks FPS). DX12 auto-enabled with RT. Another DX12+RT title working via VKD3D-Proton alongside Witcher 3 and Oblivion Remastered. |
| **Death Stranding: Director's Cut** | DX12 | Smooth, maxed settings, DLSS on | Decima Engine via VKD3D-Proton. Max resolution the game supports (doesn't support full 5120x1440 ultrawide). All settings maxed with DLSS enabled. |
| **CS2D** | DX/OpenGL | Smooth | 2D top-down game. No issues. |
| **Counter-Strike 2** | DX11 | Smooth, maxed, 5120x1440 | Source 2 engine via DXVK. Native Linux build doesn't work (Steam Linux Runtime/Sniper), requires Proton 10. No issues. |
| **Counter-Strike: Source** | DX9 | Smooth, maxed, 5120x1440 | Source engine via DXVK. Gameplay excellent. Video stress test crashes to desktop (silent exit), but actual gameplay is stable and smooth. |
| **Crab Champions** | DX11 | Smooth, maxed, 5120x1440 | UE4 via DXVK. Flawless at full ultrawide. |
| **Crysis 2: Game of the Year** | DX11 | Smooth visually, maxed, 5120x1440 | CryEngine 3 via DXVK. Renders great at full ultrawide, snappy menus. Audio is choppy and desynchronizes. **TODO:** Investigate audio issue. |
| **Crysis Warhead** | DX10 | Smooth, maxed, 1920x1080 | CryEngine 1 via DXVK. Much smoother than original Crysis despite same engine. Max native resolution 1920x1080. |
| **Crysis** | DX10 | Choppy, maxed, 1920x1080 | CryEngine 1 via DXVK. Runs but inconsistent FPS — smooth in some areas, choppy in others (especially water). CPU-heavy engine + translation overhead likely the bottleneck. **TODO:** Retest at 5120x1440 ultrawide. |
| **Cyberpunk 2077** | DX12 | 175+ FPS (DLSS 4 MFG, path tracing, 3840x1080) | ~50 FPS without DLSS. Launch options: `PROTON_ENABLE_NGX_UPDATER=1 PROTON_ENABLE_NVAPI=1 %command%`. NGX updater pulls DLSS 4 MFG from driver 580 automatically. |
| **Far Cry 2** | DX10 | Playable, choppy at max | Dunia Engine via DXVK. DX10 smoother than DX9. Reducing physics settings from Very High to High helps. **TODO:** Retest to find optimal settings balance. |
| **Golf with your Friends** | DX11 | 100+ FPS, maxed settings | DX11 via DXVK. No launch options needed. |
| **Hexen: Beyond Heretic** | DOS | Smooth | Classic DOS version. No issues. |
| **Heretic: Shadow of the Serpent Riders** | DOS | Smooth | Classic DOS version. No issues. |
| **Heretic + Hexen** (remastered) | KEX | Smooth | KEX remaster (SDL3). Both Heretic and Hexen from the same launcher. No issues. |
| **Half-Life** | OpenGL | Smooth, maxed, 5120x1440 | GoldSrc engine via DXVK. No issues. |
| **Half-Life 2** | DX9 | Smooth, maxed, 5120x1440 | Source engine via DXVK. No issues. |
| **Half-Life 2: Episode One** | DX9 | Smooth, maxed, 5120x1440 | Source engine via DXVK. No issues. |
| **Half-Life 2: Episode Two** | DX9 | Smooth, maxed, 5120x1440 | Source engine via DXVK. No issues. |
| **Half-Life 2: Lost Coast** | DX9 | Smooth, maxed, 5120x1440 | Source engine via DXVK. No issues. |
| **Half-Life: Source Deathmatch** | DX9 | Smooth, 1920x1080 windowed | Source engine via DXVK. Fullscreen at 5120x1440 causes main-loop stall and cross-thread pipe deadlock, freezing Gnome session. Launch options: `%command% -windowed -noborder -w 1920 -h 1080 -threads 1`. |
| **Hellpoint** | DX11 | Smooth, maxed, 5120x1440 | Unity engine via DXVK. No issues. |
| **Just Cause 3** | DX11 | Smooth, maxed, 5120x1440 | Avalanche engine via DXVK. No issues. |
| **Left 4 Dead** | DX9 | Playable, 25-30 FPS, 5120x1440 | Source engine via DXVK. Maxed settings but low FPS — similar to UT2004, older CPU-heavy engines suffer under translation. **TODO:** Retest with lower settings to find optimal balance. |
| **Lord of the Rings Online** | DX11 | Smooth, maxed out | DX11 via DXVK. Launcher patches from game servers fine. No launch options needed. |
| **Lost Planet: Extreme Condition** | DX10 | Smooth, maxed settings | DX10 via DXVK. No issues. |
| **Master Levels for DOOM II** | DOS | Smooth | Launches in MS-DOS emulation. Plays very well. |
| **Mafia II: Definitive Edition** | DX11 | Smooth, maxed settings | DX11 via DXVK. High FPS, no issues. |
| **Painkiller: Black Edition** | DX9 | Smooth, maxed (640x480) | Must use 640x480 — higher resolutions render in a tiny portion of the window. Changing resolution in-game crashes to desktop. Other settings maxed, runs well. |
| **Quake 2** (remaster) | Vulkan | Smooth, maxed, 5120x1440 | KEX engine remaster, Vulkan renderer. No issues. |
| **Quake III Arena** | OpenGL | Smooth, maxed, 1600x1024 | id Tech 3 engine. Limited resolution options (r_mode 11 max). No issues otherwise. |
| **Quake II RTX** | Vulkan (RT) | Smooth, maxed settings | Full path-traced ray tracing via Vulkan. Works perfectly — id Tech Vulkan + RT extensions all thunked correctly. |
| **RoboCop: Rogue City** | DX12 | Smooth, 5120x1440 w/ DLSS+FG | UE5 via VKD3D-Proton. Requires DLSS and Frame Generation for smooth performance at full ultrawide. Another DX12+DLSS UE5 title working alongside Oblivion Remastered. |
| **RV There Yet?** | DX11 | Smooth, maxed settings | UE4 via DXVK. No issues. |
| **PEAK** | Vulkan | Smooth when stable, maxed settings | Native Vulkan (Unity). Frequent crashes to desktop and server disconnects — also observed on Windows machines in the same session. Game-wide stability issues, not Spark-specific. **TODO:** Retest with DX11/DX12 renderer — may be more stable via DXVK/VKD3D. |
| **Oblivion Remastered** | DX12 | 100+ FPS, near-max, ultrawide | UE5 via VKD3D-Proton. Frame Generation available and working. Stunning at max settings. |
| **S.T.A.L.K.E.R.: Call of Pripyat** | DX9 | Smooth, 1280x1024 | R2.5 renderer (High preset). Most polished X-Ray engine build, runs well. |
| **S.T.A.L.K.E.R.: Clear Sky** | DX9 | Choppy, playable indoors | Original X-Ray engine. R2 renderer (High preset, 1280x1024) loads faster than R3 but chugs outdoors. 45s framerate stabilization after load. **Use Enhanced Edition instead.** |
| **S.T.A.L.K.E.R.: Call of Prypiat - Enhanced Edition** | DX11 | Smooth, high FPS | DLSS Max Performance. Same cutscene rendering bug as other EEs. Ran on Proton Hotfix. |
| **S.T.A.L.K.E.R.: Clear Sky - Enhanced Edition** | DX11 | Smooth, high FPS | DLSS Max Performance. Known issues: fire particle texture glitches; cutscenes render as bright yellow rectangles with black checker pattern (audio plays, Escape to skip). Enhanced Editions are the way to go over original X-Ray engine. |
| **S.T.A.L.K.E.R.: Shadow of Chernobyl** | DX9 | Smooth, solid FPS | Original X-Ray engine, but runs much better than Clear Sky. R2 renderer (High preset, 1280x1024), fluid movement. SoC's X-Ray build is lighter than CS's. |
| **S.T.A.L.K.E.R.: Shadow of Chornobyl - Enhanced Edition** | DX11 | Smooth, high FPS, ultrawide | DLSS Max Performance. Same cutscene rendering bug as other EEs (yellow rectangles, Escape to skip). Gameplay smooth, looks great at full ultrawide. Enhanced Editions recommended over originals. |
| **Sekiro: Shadows Die Twice** | DX11 | Smooth, maxed out | DX11 via DXVK. No launch options needed. |
| **Shadow of the Tomb Raider** | DX12 | Smooth, maxed settings | **Do not use native Linux port** — Feral's Vulkan renderer is ~1 FPS under FEX. Force Proton 10.0 (DX12 → VKD3D-Proton). Missing dialogue fix: change Steam language to French, download voice pack, launch, switch voice back to English in-game. |
| **Star Wars: The Old Republic** | DX9 | Smooth, maxed, 5120x1440, 120 FPS | HeroEngine via DXVK. First launch takes 10+ minutes compiling Vulkan shaders. No issues after that. |
| **Strange Brigade** | Vulkan | Smooth, maxed, 5120x1440 | Asura Engine, native Vulkan renderer. DX12 mode crashes to desktop (silent exit). Vulkan mode runs perfectly. |
| **Supermarket Together** | DX11 | Smooth, maxed, 5120x1440 | Unity engine via DXVK. No issues. |
| **Space Engineers** | DX11 | Smooth initially, unstable at max | DX11 via DXVK. Runs well at full ultrawide with high settings. "Photo" quality preset causes grinding halt after a few minutes (had to Alt+F4). **TODO:** Retest with High preset instead of Photo/Extreme to find stable ceiling. |
| **Sledding Game Demo** | DX11 | Smooth, maxed, 300 Hz | Online multiplayer tested. No issues. |
| **Thomas & Friends: Wonders of Sodor** | DX11 | Smooth, maxed, 5120x1440 | No launch options or Proton changes needed. No issues. |
| **The Witcher 3** (next-gen) | DX12 | Gorgeous, near-max | RT + DLSS Quality + Frame Gen via VKD3D-Proton. See launch options below. |
| **Unreal Tournament 2004** | DX9 | Playable, maxed settings | DX9 via DXVK. Lower FPS than expected for a 2004 title — likely FEX translation overhead on the old engine's CPU-heavy code paths. |

**Witcher 3 Next-Gen DX12 launch options (RT + DLSS Frame Gen):**
```
PROTON_ENABLE_NVAPI=1 PROTON_ENABLE_NGX_UPDATER=1 PROTON_HIDE_NVIDIA_GPU=0 DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE=on %command% --launcher-skip
```
Stable max settings: RT on (GI, AO, shadows, radiance), DLSS Quality + Frame Generation, HairWorks=1 (Geralt only), SSR on, GPU cloth sim on, FPS uncapped. HairWorks=2 and increased draw distances crash.

### Community-Reported Working

Games reported working on DGX Spark or GB10-based systems by other users. Not personally verified by AGB — your mileage may vary.

| Game | Performance | Source |
|------|------------|--------|
| **Brotato** | Runs perfectly | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Clair Obscur: Expedition 33** | Playable | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Counter-Strike 2** | Smooth, multi-hour sessions | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Cyberpunk 2077** | 70.5 FPS (RT Low + DLSS 4 SR, 1080p) | [ComputerBase](https://www.computerbase.de/artikel/pc-systeme/nvidia-dgx-spark-asus-ascent-gx10-test.94895/seite-4) |
| **Cyberpunk 2077** | Smooth | [Level1Techs / Wendell](https://forum.level1techs.com/t/nvidia-spark-gb10-msi-edgexpert-running-steam-games-cyberpunk-2077-doom-eternal-and-more-quickie-how-to/240557) |
| **Doom Eternal** | Smooth | [Level1Techs / Wendell](https://forum.level1techs.com/t/nvidia-spark-gb10-msi-edgexpert-running-steam-games-cyberpunk-2077-doom-eternal-and-more-quickie-how-to/240557) |
| **Dota 2** | Smooth | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Dunecrawl** | Smooth | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Factorio** | Runs perfectly | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Garry's Mod** | Smooth | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Golf with your Friends** | 100+ FPS | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Half-Life 2** | Smooth | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Hollow Knight: Silksong** | Very smooth | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **HunterXHunter** | Smooth | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Lonely Mountains: Snow Riders** | Smooth | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Marvel Cosmic Invasion** | No notable issues | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Outer Wilds** | Smooth, 20+ min sessions | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **PEAK** | Stable | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Portal 2** | Smooth | [Canonical / Mitchell Augustin](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Returnal** | Smooth gameplay (opening videos slow) | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Satisfactory** | Very smooth | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Shadow of the Tomb Raider** | 108 FPS | [ComputerBase](https://www.computerbase.de/artikel/pc-systeme/nvidia-dgx-spark-asus-ascent-gx10-test.94895/seite-4) |
| **Soul Calibur VI** | Runs great | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |
| **Vampire Survivors** | Runs great | [marsprite](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719) |

Console emulation also reported working: Skate 3 (PS3 via RPCS3) at 60 FPS, Forza Motorsport (Xbox via Xemu) at 30 FPS @ 1080p — [ETA Prime / HotHardware](https://hothardware.com/news/dgx-spark-gaming-tests).

### Likely to Work (DLSS 4 MFG + Proton Gold/Platinum, unconfirmed on Spark)

| Game | Why It Would Impress |
|------|---------------------|
| **Alan Wake 2** | Arguably the best-looking game ever made. Full path tracing. Proton Gold. |
| ~~Black Myth: Wukong~~ | Crashes — see Known Issues below. |
| **FINAL FANTASY XVI** | Spectacular visual effects. |
| **God of War Ragnarok** | Sony's flagship visual showcase on PC. |
| ~~Half-Life 2 RTX~~ | Crashes — see Known Issues below. |
| **Hogwarts Legacy** | Beautiful open world with RT reflections. Proton Gold. |
| **Indiana Jones and the Great Circle** | id Tech engine, DLSS 4 support. |
| **S.T.A.L.K.E.R. 2** | Unreal Engine 5, atmospheric visuals. |
| **SILENT HILL 2 Remake** | Unreal Engine 5, atmospheric horror. |

### Known Issues

| Game | Issue |
|------|-------|
| **Black Myth: Wukong** | DX12-only (UE5). Crashes ~50s in during level load. Root cause: game ships AMD-optimized compute shaders that hard-require `WaveSize(64)` (AMD wavefront width) with no Wave32 fallback. NVIDIA GPUs (including GB10) only support Wave32 (subgroup size 32). VKD3D-Proton correctly rejects the pipeline: `Required WaveSize range [64, 64], but supported range is [32, 32]`. Not an ARM/FEX issue — would fail on any NVIDIA GPU via VKD3D-Proton. Descriptor_buffer thunk gap (original diagnosis) was a red herring. Needs Game Science to add Wave32 shader permutations, or a VKD3D-Proton workaround to emulate Wave64 on Wave32 hardware. |
| **Elden Ring** | DX12-only. Same `VK_EXT_descriptor_buffer` crash as Halo Infinite — identical EasyAntiCheat loading screen followed by crash. |
| **Half-Life 2 RTX** | RTX Remix bridge incompatible with ARM64 translation. **FEX-Emu:** access violation (0xc0000005) in NvRemixBridge.exe during `CreateDevice`. **Box64:** gets further — device creates successfully and draw calls flow, but deadlocks on Present semaphore (cross-process sync failure between 32-bit client and 64-bit server). Root cause: RTX Remix's dual-process shared-memory IPC architecture breaks under x86→ARM64 translation. Regular Half-Life 2 works fine. |
| **Halo Infinite** | DX12-only. Crashes at launch — `vkGetPhysicalDeviceDescriptorSizeEXT` unthunked in FEX. Same `VK_EXT_descriptor_buffer` gap as NMS and Wukong. Fails on both Proton 10.0 and Proton Experimental. |
| **No Man's Sky** | Crashes ~16 seconds into launch, never renders a frame. `vkGetPhysicalDeviceDescriptorSizeEXT` unthunked in FEX. `-force d3d11` launch option does not help — game still probes Vulkan extensions and crashes. Tested on Proton 10.0 and Experimental. |
| **The Legend of Khiimori Demo** | .NET 9 WPF application (system check tool, not a game). Hangs indefinitely on launch — WPF/PresentationCore initialization never completes. Wine's WPF support is fundamentally incomplete; not a FEX-specific issue. |
| **Final Doom** | Launches but doesn't load into gameplay — hangs at title screen. Multiple launch options available but not yet iterated through. |
| **Far Cry 3 / Blood Dragon / 4 / 5 / Primal / New Dawn / 6** | Ubisoft Connect launcher crashes with unrecoverable error. Tested on Proton 10.0 and Experimental, online and offline mode. FC3 and Blood Dragon confirmed; remaining titles expected identical. Direct-launching Blood Dragon's `fc3_blooddragon_d3d11.exe` bypasses the launcher and the DX11 renderer works — game runs, but forced online server check blocks gameplay progression, resolution defaults wrong, and audio loops during Bink sequences. The game engine (Dunia) is compatible; Ubisoft Connect is the blocker. |
| **Far Cry** | DX9 (CryEngine 1, 2004). Launches but nearly unplayable. ~10 minute map load times. Menus smooth, HUD renders, audio and movement work, but 3D playfield is entirely black — no world geometry or textures visible. Same engine family as Crysis (which was choppy but at least rendered). |
| **Burnout Paradise: The Ultimate Box** | DX9. Refuses to launch — error dialog: "This machine does not support the SSE2 Command Set." Game's CPUID check doesn't detect SSE2 under FEX translation, even though FEX fully supports SSE2 emulation. |
| **DOOM 3** | 32-bit x86 OpenGL (id Tech 4). Launches, initializes OpenGL (ARB2 renderer), loads to menu, crashes on map load. x87 FPU stack corruption — NaN/INF values, engine's FPU state check fails: `the FPU stack is not empty at the end of the frame`. 32-bit binary goes through BOX32 mode. |
| **DOOM 3 BFG Edition** | 64-bit OpenGL (id Tech 4 remaster). Same FPU stack check crash as DOOM 3 — engine validates x87 state every frame. FPU values are clean (all zeros) but engine still bails. GLSL `gl_FragColor` deprecation warnings are cosmetic, not the cause. id Tech 4's aggressive FPU validation is incompatible with FEX's x87 translation. id Tech 6+ (DOOM 2016, Eternal, Q2 RTX) all work fine — newer engines dropped x87 checks. |
| **Prey (2006)** | OpenGL (id Tech 4 variant, Human Head). Same x87 FPU stack crash as DOOM 3 and BFG Edition. All id Tech 4 games are broken on the Spark due to FPU state validation. |
| **Dark Souls: Prepare to Die Edition** | DX9 via DXVK. Crashes at launch — GStreamer deadlock in Wine's media pipeline during intro video playback. Log shows `Trying to join task from its thread would deadlock`. The infamously bad PC port uses Windows Media Foundation for videos, which Wine handles via GStreamer — the threading model breaks under FEX translation. |
| **Dark Souls III** | DX11 via DXVK. Launches and renders the intro cutscene, but crashes to desktop at the cutscene-to-gameplay transition every time. Crash occurs whether skipping or watching the cutscene, and with movie files removed entirely. No crash dump or Vulkan extension error — silent exit. Surprising given Sekiro (same studio, same API) works flawlessly. |
| **Red Dead Redemption 2** | Requires Proton Experimental (Proton 10.0 can't launch Rockstar Launcher). Gets to main menu on Vulkan renderer, but crashes with `EXCEPTION_FLT_INVALID_OPERATION` (0xc0000090) during world load — FPU translation issue under FEX. DX12 mode fails to get past the launcher. Freezes when changing graphics settings. Neither renderer is viable. |

### Compatibility Test Plan

These games are selected to validate the hypothesis that DX11 games (via DXVK) work reliably on the ARM64/FEX stack, while native Vulkan and DX12 games crash due to unthunked `VK_EXT_descriptor_buffer` extensions. Doom Eternal (native Vulkan, confirmed working) suggests the issue is extension-specific, not all native Vulkan.

| # | Game | Graphics API | What It Tests | Expected | Result |
|---|------|-------------|---------------|----------|--------|
| 1 | **Shadow of the Tomb Raider** | DX11 + DX12 | Same game, two API paths. Best single test of the hypothesis. | DX11 works, DX12 crashes | **Native Linux Vulkan port: ~1 FPS** (Feral renderer unusable under FEX). **Proton DX12 → VKD3D-Proton: works great**, maxed settings. Missing dialogue fix: download French voice pack via Steam language switch, then revert in-game. |
| 2 | **Red Dead Redemption 2** | Vulkan native + DX12 | Native Vulkan without RTX Remix complexity. Tests if NMS crash is extension-specific. | Likely crashes (both modes) | **Confirmed crash.** Vulkan: reaches main menu, FPU exception (0xc0000090) on world load. DX12: can't get past Rockstar Launcher. Requires Proton Experimental (10.0 fails at launcher). |
| 3 | **The Witcher 3** (next-gen) | DX11 / DX12 RT | Classic DX11 vs next-gen DX12 RT mode. Another dual-API split test. | DX11 works, DX12 crashes | **Surprise:** DX12 works with RT + DLSS FG! DX11 crashes on cutscene skip (Bink video). HairWorks=2 crashes, HairWorks=1 stable. |
| 4 | **Halo Infinite** | DX12 only | Pure VKD3D-Proton, no DX11 fallback. | Crashes | **Confirmed.** `vkGetPhysicalDeviceDescriptorSizeEXT` unthunked. Crashes on both Proton 10.0 and Experimental. |
| 5 | **Sekiro: Shadows Die Twice** | DX11 only | Demanding DX11 positive control. | Works | **Confirmed.** Maxed out, no issues. |
| 6 | **Lord of the Rings Online** | DX9/DX11 | Oldest engine in the set (2007 MMO). Floor test for the DXVK path. | Works | **Confirmed.** Maxed out, no issues. |

### Installed — Not Yet Tested

Games installed on this system but not yet launched/tested. Grouped by expected compatibility based on graphics API. Sorted alphabetically within each group.

**Priority flags:** Games marked with :star: are high-priority — they test specific engine/API hypotheses or are particularly interesting showcase titles.

**DX11 — Expected to Work (DXVK sweet spot):**

| Game | API | Notes |
|------|-----|-------|
| :star: Aliens vs. Predator | DX11 | Demanding DX11 shooter (Rebellion, 2010). Good stress test. |
| :star: Borderlands GOTY Enhanced | DX11 | UE/DX11, popular co-op. Enhanced version should be smoother than original. |
| :star: Darksiders Warmastered Edition | DX11 | Remastered DX11 path. Vigil/THQ. |
| :star: Ghostrunner | DX11/DX12 | UE4 with RTX. DX11 should work, DX12 uncertain. |
| :star: Hellblade: Senua's Sacrifice | DX11 | UE4. Visually stunning. |
| :star: L.A. Noire | DX11 | Rockstar DX11. Tests whether Rockstar's FPU issues (seen in RDR2) affect DX11 titles too. |
| :star: Mafia: Definitive Edition | DX11 | Illusion Engine remake. |
| :star: Mirror's Edge | DX9/11 | Unreal Engine 3 (DICE). |
| Age of Empires III: Definitive Edition | DX11 | Bang! Engine. Same family as AoE2 DE (which works). |
| Alien Shooter 2: Reloaded | DX9 | Top-down shooter, lightweight. |
| American Truck Simulator | DX11 | SCS engine. Driving sim. |
| ASTRONEER | DX11 | UE4. |
| Back 4 Blood | DX11 | UE4. L4D spiritual successor. |
| Bulletstorm: Full Clip Edition | DX11 | UE3. |
| Anomaly Warzone Earth | DX9/11 | Tower offense, lightweight. |
| A.R.E.S. | DX9 | Side-scroller. |
| Bionic Commando Rearmed | DX9 | Capcom platformer remaster. |
| Blocks That Matter | DX9 | Indie puzzle. |
| Bunch Of Heroes | DX11 | Co-op top-down shooter. |
| Cloning Clyde | DX9 | XBLA port. |
| Command & Conquer Remastered | DX11 | Classic RTS remaster. |
| Company of Heroes / Legacy Edition | DX9/11 | Essence Engine (Relic). |
| Containment: The Zombie Puzzler | DX9 | Puzzle game. |
| Critical Mass | DX9 | Puzzle game. |
| Data Jammers: FastForward | DX9 | Indie racing. |
| Dead Horde | DX9 | Co-op zombie shooter. |
| Defense Grid: The Awakening | DX9 | Tower defense classic. |
| Delve Deeper | DX9 | Strategy. |
| Dino D-Day | DX9 | Source engine multiplayer. Should work like other Source games. |
| Dune: Spice Wars | DX11 | Shiro Games RTS. |
| EDGE | DX9 | Indie puzzle platformer. |
| Eufloria / Eufloria HD | DX9/11 | Ambient strategy. |
| Far Cry 3: Blood Dragon | DX11 | Same engine as FC3 — Ubisoft Connect blocker, but DX11 renderer works when bypassed. |
| Far Cry 4 | DX11 | Dunia Engine — Ubisoft Connect blocker expected. |
| Far Cry 5 | DX11 | Dunia Engine — Ubisoft Connect blocker expected. |
| Far Cry New Dawn | DX11 | Same engine as FC5 — Ubisoft Connect blocker expected. |
| Far Cry Primal | DX11 | Dunia Engine — Ubisoft Connect blocker expected. |
| Flight Control HD | DX9 | Casual port. |
| Foreign Legion: Buckets of Blood | DX9 | Indie shooter. |
| Fortix 2 | DX9 | Arcade puzzle. |
| Geometry Wars: Retro Evolved | DX9 | Twin-stick shooter. |
| Ghostbusters: The Video Game | DX9 | Infernal Engine. |
| GRAV | DX9/11 | UE4. |
| HOARD | DX9 | Arcade strategy. |
| Hydrophobia: Prophecy | DX11 | Third-person action. |
| inMomentum | DX9 | Parkour FPS. |
| Ironclads: Chincha Islands War 1866 | DX9 | Naval strategy. |
| Lead and Gold | DX9 | Third-person multiplayer shooter. |
| Monday Night Combat | DX11 | UE3 class-based shooter. |
| Nuclear Dawn | DX9 | Source engine FPS/RTS hybrid. Should work like other Source games. |
| Orcs Must Die! | DX9/11 | UE3 tower defense. |
| Painkiller Overdose | DX9 | Same engine as Painkiller Black. |
| Painkiller: Redemption | DX9 | Same engine as Painkiller Black. |
| Really Big Sky | DX9 | Twin-stick shooter. |
| Revenge of the Titans | DX9 | Tower defense. |
| RoboBlitz | DX9 | UE3. |
| Runespell: Overture | DX9 | RPG/card game. |
| Sanctum | DX9 | UE3 FPS/tower defense. |
| Scoregasm | DX9 | Twin-stick shooter. |
| Shattered Horizon | DX10 | DX10-only space FPS. Interesting DX10 test. |
| Sniper Elite | DX9 | Asura Engine. Same engine family as Strange Brigade (which works on Vulkan). |
| Snuggle Truck | DX9 | Physics puzzle. |
| Steel Storm: Burning Retribution | DX9 | Top-down shooter. |
| Stroke of Fate: Operation Valkyrie | DX9 | Adventure. |
| Swords and Soldiers HD | DX9 | Side-scrolling RTS. |
| Tobe's Vertical Adventure | DX9 | Platformer. |
| Trapped Dead | DX9 | Isometric zombie RTS. |
| TRAUMA | DX9 | Point-and-click puzzle. |
| Unstoppable Gorg | DX9 | Tower defense. |
| Vertex Dispenser | DX9 | Abstract strategy. |
| Your Doodles Are Bugged! | DX9 | Puzzle. |
| Zombie Shooter | DX9 | Top-down shooter. |
| Zombie Shooter 2 | DX9 | Top-down shooter. |

**DX9 — Major Titles (DXVK, high interest):**

| Game | API | Notes |
|------|-----|-------|
| :star: Batman: Arkham Asylum GOTY | DX9 | UE3, major AAA. High-profile DX9 DXVK test. |
| :star: Bully: Scholarship Edition | DX9 | Rockstar DX9. Tests Rockstar FPU behavior (RDR2 has FPU crash). |
| :star: Call of Duty 4: Modern Warfare | DX9 | IW3 engine, classic FPS. Interesting engine test. |
| :star: GTA IV: The Complete Edition | DX9 | RAGE engine. Infamously bad PC port + GFWL. Rockstar FPU test. |
| :star: GTA San Andreas | DX9 | RenderWare. Classic Rockstar. |
| :star: Mass Effect (2007) | DX9 | UE3, BioWare classic. |
| :star: Neverwinter Nights 2: Platinum | DX9 | Electron Engine (Obsidian). Complex RPG. |
| Alpha Prime | DX9 | Czech FPS (id Tech-like). |
| Battlefield 2 | DX9 | Refractor 2 engine (DICE). Old but interesting. |
| Borderlands GOTY | DX9 | UE2.5. Original version, may have quirks the Enhanced version fixed. |
| Darksiders | DX9 | Original DX9 version. |
| Dead Island | DX9 | Chrome Engine 5. |
| Depths of Peril | DX9 | Indie ARPG. |
| Deus Ex: Game of the Year Edition | DX9 | Unreal Engine 1 (1999). Classic immersive sim. |
| Deus Ex: Invisible War | DX9 | Ion Storm, modified Unreal engine. |
| DiRT | DX9 | EGO engine (Codemasters). |
| Duke Nukem Forever | DX9 | Heavily modified UE2.5. |
| GTA III | DX9 | RenderWare. |
| GTA 2 | DX9 | 2D top-down, very old. |
| GTA | DX9 | 2D top-down, original. |
| Half-Life 2: Deathmatch | DX9 | Source engine, same as HL2. |
| Hard Reset | DX9 | Flying Wild Hog. Same devs as Shadow Warrior reboot. |
| Hitman: Blood Money | DX9 | Glacier engine (IO Interactive). |
| Indigo Prophecy (Fahrenheit) | DX9 | Quantic Dream, early cinematic adventure. |
| Jade Empire: Special Edition | DX9 | BioWare, Odyssey Engine variant. |
| Just Cause | DX9 | Avalanche engine (precursor to JC3 which works). |
| Majesty 2 Collection | DX9 | Fantasy RTS. |
| Manhunt | DX9 | RenderWare (Rockstar). Another Rockstar FPU test. |
| Max Payne 2 | DX9 | MAX-FX engine (Remedy). |
| Medal of Honor: Airborne | DX9 | UE3. |
| Medal of Honor (2010) SP + MP | DX9 | UE3 (SP) / Frostbite 1 (MP). Interesting dual-engine. |
| Midnight Club II | DX9 | RAGE predecessor (Rockstar). |
| Mount & Blade | DX9 | Custom engine. |
| Panzer Dragoon: Remake | DX9/11 | UE4 remake. |
| PAYDAY: The Heist | DX9 | Diesel engine. |
| Psychonauts | DX9 | Double Fine, custom engine. |
| Red Orchestra: Ostfront 41-45 | DX9 | UE2.5. |
| Saints Row 2 | DX9 | Notoriously bad PC port. Interesting stress test. |
| Sonic Adventure DX | DX9 | Dreamcast port. |
| Star Wars: Battlefront 2 Classic | DX9 | Pandemic, classic. |
| Star Wars: Empire at War Gold | DX9 | Petroglyph RTS. |
| Street Fighter IV | DX9 | MT Framework (Capcom). |
| The Elder Scrolls IV: Oblivion GOTY (2009) | DX9 | Gamebryo engine. Not the UE5 remaster. |
| The Witcher | DX9 | Aurora Engine (BioWare/CD Projekt, 2007). |
| The Witcher 2 | DX9 | RED Engine. |
| Titan Quest / Anniversary / Immortal Throne | DX9 | Iron Lore ARPG. Three versions installed. |
| ToCA Race Driver 3 | DX9 | Codemasters. |
| Torchlight | DX9 | OGRE engine. Diablo-like ARPG. |
| Trine | DX9 | Frozenbyte custom engine. |
| Unreal Gold | DX9 | Unreal Engine 1 (1998). |
| Unreal II: The Awakening | DX9 | Unreal Engine 2. |
| Unreal Tournament GOTY | DX9 | Unreal Engine 1. |

**id Tech Engine Family — Diagnostic Priority:**

These test the id Tech 4 FPU crash pattern (DOOM 3, BFG, Prey all crash on x87 FPU validation) and whether id Tech 5 inherits the issue. id Tech 3 (Q3A) and id Tech 6+ (DOOM 2016, Eternal) work fine.

| Game | Engine | Notes |
|------|--------|-------|
| :star: Quake 4 | id Tech 4 | **Critical test.** Same engine as DOOM 3 which crashes on x87 FPU. Will it crash too? |
| :star: RAGE | id Tech 5 (OpenGL) | **Critical test.** Bridges broken id Tech 4 and working id Tech 6. Does id Tech 5 still have x87 FPU checks? |
| :star: The Chronicles of Riddick: Assault on Dark Athena | Modified id Tech 4 (Starbreeze) | Third-party id Tech 4 variant. Tests if the FPU issue is in shared engine code or id-specific. |
| :star: DEATHLOOP | Void Engine (id Tech variant) | Arkane's id Tech fork. Tests whether Arkane's branch has FPU issues. Vulkan renderer. |
| Return to Castle Wolfenstein | id Tech 3 (OpenGL) | Q3A (same engine) works. Should confirm id Tech 3 is solid. |
| Daikatana | id Tech 2 (Quake II engine) | Ion Storm. |
| HeXen II | id Tech 2 (Quake engine) | Raven Software. |
| Hexen: Deathkings of the Dark Citadel | id Tech 1 | Hexen expansion. |
| Quake | id Tech 1/2 | Original Quake, very lightweight. |
| Quake II expansion packs (Ground Zero, The Reckoning) | KEX (remaster) | Same engine as working Quake 2 remaster. Should work. |
| Quake III: Team Arena | id Tech 3 | Expansion for working Q3A. |
| Quake Mission Packs (Scourge of Armagon, Dissolution of Eternity) | id Tech 1 | Original Quake expansions. |
| DOOM 3: Resurrection of Evil | id Tech 4 | Expansion — same engine as broken DOOM 3. Expect same FPU crash. |

**Source Engine — Expected to Work (HL2, CS:S, etc. all confirmed):**

| Game | Notes |
|------|-------|
| Counter-Strike | GoldSrc (HL1 engine). |
| Counter-Strike: Condition Zero | GoldSrc. |
| Darkest Hour: Europe '44-'45 | Red Orchestra mod (UE2.5). |
| Day of Defeat: Source | Source engine. |
| Deathmatch Classic | GoldSrc. |
| Garry's Mod | Source engine. Community-reported working. |
| Half-Life: Blue Shift | GoldSrc. |
| Half-Life: Opposing Force | GoldSrc. |
| Half-Life: Source | Source engine remake of HL1. |
| Portal | Source engine. Should work like HL2/Portal 2. |
| Portal 2 | Source engine. Should work. |
| Team Fortress Classic | GoldSrc. |
| Zeno Clash | Source engine. |

**OpenGL / HPL Engine — Uncertain (FEX GL thunks enabled):**

| Game | API | Notes |
|------|-----|-------|
| :star: Amnesia: The Dark Descent | OpenGL (HPL2) | Frictional Games. Tests HPL2 engine under FEX GL thunks. |
| :star: Star Wars: Knights of the Old Republic | OpenGL | BioWare Odyssey Engine. Classic RPG. |
| Aliens versus Predator Classic 2000 | OpenGL | Very old (1999). |
| Penumbra: Overture / Black Plague / Requiem | OpenGL (HPL1) | Frictional Games, predecessor to Amnesia. |
| Serious Sam Classics: Revolution | OpenGL | Serious Engine 1. |
| Serious Sam Classic: The First Encounter | OpenGL | Serious Engine 1. |
| Serious Sam Classic: The Second Encounter | OpenGL | Serious Engine 1. |

**DX11 Remasters / Newer (DXVK):**

| Game | API | Notes |
|------|-----|-------|
| Serious Sam Fusion 2017 | DX11/Vulkan | Serious Engine 4. May use Vulkan natively. |
| Serious Sam HD: The First Encounter | DX9/11 | Serious Engine 3. |
| Serious Sam HD: The Second Encounter | DX9/11 | Serious Engine 3. |
| Serious Sam: The Random Encounter | DX9 | RPG spinoff. |
| Serious Sam Double D XXL | DX9 | Side-scroller spinoff. |

**DX12 — May Work (VKD3D-Proton, mixed results):**

| Game | API | Notes |
|------|-----|-------|
| Elden Ring: Nightreign | DX12 | Same engine as Elden Ring — base game crashes (descriptor_buffer). Expect same result. |
| Far Cry 6 | DX12 | Dunia Engine, DX12 primary renderer — Ubisoft Connect blocker expected. |
| Grand Theft Auto V Enhanced | DX12 | New RAGE engine build, DX12-only. Rockstar Launcher may be an obstacle (same issue as RDR2). |

**Classic / DOS / ScummVM / Point-and-Click:**

| Game | Notes |
|------|-------|
| Commander Keen Complete Pack | DOS. |
| Delta Force 1 / 2 / Land Warrior / Task Force Dagger | Voxel engine (NovaLogic). |
| Harvester | DOS FMV adventure (1996). |
| Indiana Jones and the Fate of Atlantis | ScummVM/DOS. LucasArts classic. |
| Indiana Jones and the Last Crusade | ScummVM/DOS. LucasArts classic. |
| Loom | ScummVM/DOS. LucasArts classic. |
| The Dig | ScummVM/DOS. LucasArts classic. |
| The Secret of Monkey Island: Special Edition | DX9 remaster with classic mode. |
| Star Wars: Dark Forces | DOS (Build engine variant). |
| Star Wars: Jedi Knight: Dark Forces II | DX (DirectDraw/D3D, 1997). |
| Star Wars: Jedi Knight: Mysteries of the Sith | DX (same engine as JK:DF2). |
| Star Wars: Starfighter | DX9. |
| Wolfenstein 3D: Spear of Destiny | DOS. |
| X-COM: UFO Defense / Terror from the Deep / Interceptor / Apocalypse / Enforcer | DOS-era strategy classics. |

**Indie / Lightweight / 2D (likely to work, low priority):**

| Game | Notes |
|------|-------|
| And Yet It Moves | Physics platformer. |
| Armikrog | Point-and-click (Pencil Test Studios). |
| Aquaria | 2D metroidvania. |
| Atom Zombie Smasher | Strategy. |
| Beat Hazard | Twin-stick music shooter. |
| Before the Echo | Rhythm RPG. |
| Ben There, Dan That! / Time Gentlemen, Please! | Point-and-click comedy. |
| Binding of Isaac | Flash-based roguelike. |
| BIT.TRIP RUNNER | Rhythm platformer. |
| Blackwell Legacy / Unbound / Convergence | AGS adventure games. |
| Botanicula | Amanita Design, point-and-click. |
| Braid | DX9 puzzle platformer. |
| Breath of Death VII / Cthulhu Saves the World | Retro RPGs. |
| Cave Story+ | Classic indie platformer. |
| Chains | Physics puzzle. |
| Cogs | 3D puzzle. |
| Crayon Physics Deluxe | Physics sandbox. |
| Cricket Revolution | Sports. |
| Crysis Wars | DX10. Multiplayer standalone for Crysis Warhead. |
| Darwinia / Multiwinia / Uplink / DEFCON | Introversion Software bundle. |
| Dinner Date | Experimental narrative. |
| Disciples II: Gallean's Return | Turn-based strategy. |
| Dungeons of Dredmor | Roguelike. |
| Dwarf Fortress | SDL/OpenGL. Very lightweight graphically. |
| Eets | Puzzle. |
| Fate of the World | Strategy. |
| FOTONICA | First-person runner. |
| Fractal: Make Blooms Not War | Puzzle. |
| Freedom Force / vs. the 3rd Reich | Irrational Games, superhero RTS. |
| Frozen Synapse | Turn-based tactics. |
| Gemini Rue | AGS adventure. |
| Gish | Physics platformer. |
| Gratuitous Space Battles | Strategy. |
| Greed Corp | Turn-based strategy. |
| Hack, Slash, Loot | Roguelike. |
| Hacker Evolution / Untold / Duality | Hacking sim. |
| Hammerfight | Physics combat. |
| Inside a Star-filled Sky | Recursive shooter. |
| ISLANDERS | Minimalist city builder. |
| Jamestown | Shoot-em-up. |
| Jolly Rover | Point-and-click. |
| LIMBO | Atmospheric platformer. |
| Lugaru HD | 3D combat. |
| Lume | Puzzle adventure. |
| Machinarium | Amanita Design, point-and-click. |
| Making History: The Calm & The Storm | Grand strategy. |
| Marathon | Bungie (upcoming reboot). |
| NightSky | Physics platformer. |
| Nimbus | Flying puzzle. |
| Numen: Contest of Heroes | ARPG. |
| Oddworld: Abe's Oddysee / Abe's Exoddus | Classic platformers. |
| Oddworld: Munch's Oddysee / Stranger's Wrath HD | 3D Oddworld. |
| On the Rain-Slick Precipice of Darkness Ep1/Ep2 | Penny Arcade RPG. |
| PixelJunk Eden | Platformer. |
| Plants vs. Zombies: GOTY | PopCap classic. |
| Poker Night at the Inventory | Telltale card game. |
| The Polynomial | Fractal music game. |
| QuantZ | Puzzle. |
| Raycatcher | Puzzle. |
| Return to Dark Castle | Platformer. |
| RTX Sweeper | RTX demo. |
| Saira | Platformer. |
| Samorost 2 | Amanita Design. |
| Shadowgrounds / Shadowgrounds: Survivor | Top-down shooters (Frozenbyte). |
| Shank | Side-scrolling brawler. |
| SpaceChem | Puzzle. |
| Star Raiders | Atari classic remake. |
| Super Meat Boy | Hardcore platformer. |
| Terraria | 2D sandbox. Very popular. |
| The Alien Way | Indie. |
| The Dream Machine | Clay-animated adventure. |
| The Suicide of Rachel Foster | UE4. |
| Toki Tori | Puzzle platformer. |
| VVVVVV | Platformer. |
| Windosill | Art toy. |
| Worms Armageddon | 2D classic. |
| World of Goo | Physics puzzle. |
| Zen Bound 2 | 3D puzzle. |

**Classic Doom — TODO: Iterate launch options:**

| Game | Notes |
|------|-------|
| DOOM + DOOM II / DOOM II / Final Doom | Multiple launch options (DOS, non-DOS, remastered) with varying results. Need to test each configuration. |

### Downloading / Not Yet Installed

| Game | State | Notes |
|------|-------|-------|
| Dota 2 | Needs download | Source 2 engine. Native Linux build may have same issues as CS2 (requires Proton). |

### Known Not to Launch

- Lara Croft: Angel of Darkness
- Lara Croft and the Guardian of Light

## Other Game Clients on ARM64

The Cortex-X925/A725 cores in the DGX Spark do not support 32-bit ARM instructions, so Box86 is not an option. All x86 translation must go through FEX-Emu or Box64 (with BOX32 mode for 32-bit x86).

### Confirmed Working on ARM64

| Client | Translation Layer | Notes |
|--------|-------------------|-------|
| **Steam** | FEX-Emu | Best supported path. NVIDIA autoinstaller + Canonical ARM64 Snap both work. |
| **Heroic Games Launcher** (Epic/GOG/Amazon) | Box64 + Wine/Proton | Confirmed on ARM64 SBCs. No official ARM64 binary — must compile from source. Box64 v0.2.2+ required for Electron/libcef. |
| **CrossOver ARM64 Preview** | Native ARM64 Wine | Commercial. Mentioned working on DGX OS in Level1Techs thread. No emulation layer needed for the launcher itself. |
| **Battle.net** | Box64 v0.4.0+ Wine | Partially working — "getting stable," some games launch. |

### Likely to Work (manual setup required)

| Client | Notes |
|--------|-------|
| **Lutris** | Python/GTK app, ARM64 packages exist. Tries to download x86 runners by default — needs manual config to use Box64/FEX Wine runners. |
| **Minigalaxy** (lightweight GOG client) | Pure Python/GTK, should run natively on ARM64. Games still need Box64/FEX. |
| **GOG direct installers** | Shell script installers work via `box64 script.sh`. Linux-native GOG games through Box64, Windows titles through Box64 + Wine. |

### Known Not to Work

| Client | Why |
|--------|-----|
| **Bottles** | Flatpak is x86_64 only, bundled Wine runners have no ARM64 builds. |
| **EA App** | Windows-only, poor Wine compatibility even on x86 Linux. |
| **Ubisoft Connect** | Same — no confirmed ARM64 reports. |
| **Epic Games Store** (native client) | Barely works on x86 Wine. Use Heroic instead. |
| **GOG Galaxy** | No Linux client exists (any architecture). |
| **itch.io app** | No ARM64 build. Unconfirmed via emulation. |

## Native ARM64 Games (No Translation Overhead)

These games run natively on ARM64 — no FEX-Emu, Box64, Proton, or DXVK in the loop. The entire stack is native: ARM64 binary → native OpenGL/Vulkan → native NVIDIA driver → GPU. This eliminates the x86 translation bottleneck entirely and avoids all Vulkan thunk gaps.

| Game | Install | Why It's Interesting on Spark |
|------|---------|-------------------------------|
| **Minecraft Java Edition** | `flatpak install flathub org.prismlauncher.PrismLauncher` | Java runs natively on ARM64. PrismLauncher handles LWJGL ARM64 library swapping automatically. With 128 GB RAM and the GB10, this may be the best Minecraft machine ever built — massive render distances, heavy shader packs (Iris/Sodium) at native speed. |
| **SuperTuxKart** | `sudo apt install supertuxkart` or Flatpak | Native Vulkan renderer, ARM64 builds available. Good native performance benchmark. |
| **0 A.D.** | `sudo apt install 0ad` | Open-source RTS (Age of Empires-like). CPU-heavy with large battles — 10x Cortex-X925 cores shine without translation overhead. |
| **OpenMW** (Morrowind engine) | Build from source or Flatpak | Open-source Morrowind reimplementation. Native ARM64, OpenGL. Load the entire game with texture mods into 128 GB RAM. |
| **Veloren** | Build from source (Rust) | Voxel RPG, Vulkan via wgpu. Good test of native Vulkan performance vs translated games. |
| **Xonotic** | Flatpak (aarch64) | Arena FPS, Darkplaces engine, OpenGL. Good for raw frame rate testing without translation. |

## Display Notes

- HDMI 2.1a only (no DisplayPort) — limits ultrawide refresh rate
- NVIDIA on Linux does not yet support DSC — expect 5120x1440 @ 120Hz max
- DLSS upscaling helps: render at lower internal resolution, output at native

## Key Resources

- [FEX Autoinstaller (NVIDIA)](https://github.com/esullivan-nvidia/fex_autoinstall)
- [Vulkan Fix Gist](https://gist.github.com/solatticus/14313d9629c4896abfdf57aaf421a07a)
- [Box64](https://github.com/ptitSeb/box64) — currently v0.4.4
- [Canonical ARM64 Steam Snap](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719)
- [Level1Techs GB10 Gaming How-To](https://forum.level1techs.com/t/nvidia-spark-gb10-msi-edgexpert-running-steam-games-cyberpunk-2077-doom-eternal-and-more-quickie-how-to/240557)
- [NVIDIA Developer Forum: Vulkan on GB10](https://forums.developer.nvidia.com/t/vulkan-on-nvidia-dgx-spark-gb10-working-repeatable/356570)
- [DGX Spark Software Updates 02/2026](https://forums.developer.nvidia.com/t/dgx-spark-software-updates-02-2026/360362)
- [NVIDIA Unix driver versions](https://www.nvidia.com/en-us/drivers/unix/) — the page to watch for a DLSS 5-capable Linux driver
- [Proton #9439 — re-enable dxvk-nvapi on aarch64](https://github.com/ValveSoftware/Proton/issues/9439) — why Proton 11.0 (ARM64) has no DLSS
- [NVIDIA Developer Forum: DLSS support for GB10/Spark?](https://forums.developer.nvidia.com/t/dlss-support-for-gb10-spark/364161)
- [GeForce driver 616.64 — DLSS 5 launch notes](https://www.nvidia.com/en-us/geforce/news/nba-2k27-dlss-5-3d-guided-neural-rendering-geforce-game-ready-driver/) — the 616.64 / Streamline 2.14 requirement
- [Valve Proton releases](https://github.com/ValveSoftware/Proton/releases)
