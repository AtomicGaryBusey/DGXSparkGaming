# DGX Spark Steam Gaming Setup

## Status

| Component | Status | Version |
|-----------|--------|---------|
| Vulkan (modeset=1) | Verified | Vulkan 1.4.328 / NVIDIA GB10 |
| FEX-Emu | Installed | fex-emu-armv8.4 (PPA) |
| Steam | Installed + Launched | 1.0.0.81 |
| Box64 | Installed | v0.4.1 (Dynarec, armv9.2-a) |
| Proton | Pending | Configure Proton 10.0-2 beta |

## System Info
- **Hardware:** NVIDIA DGX Spark (GB10 Grace Blackwell Superchip)
- **CPU:** 10x Cortex-X925 + 10x Cortex-A725 (20 cores, aarch64)
- **GPU:** NVIDIA GB10 — 6,144 CUDA cores, 48 RT Cores, Vulkan 1.4, Blackwell arch
- **Memory:** 128 GB unified LPDDR5x (273 GB/s)
- **Storage:** Samsung 3.7 TB NVMe
- **Display:** Samsung Odyssey G9 OLED (5120x1440) via HDMI 2.1a
- **OS:** Ubuntu 24.04.4 LTS (Noble Numbat)
- **Driver:** NVIDIA 580.126.09 (open kernel), CUDA 13.0
- **Kernel:** 6.17.0-1008-nvidia

## Architecture

Steam and x86 games run through translation layers on ARM64:

```
Windows Game (x86_64 .exe)
  → Proton/Wine (Win32/DX → Linux/Vulkan)
    → FEX-Emu or Box64 (x86_64 → ARM64 JIT translation)
      → Native ARM64 NVIDIA Vulkan driver (GPU runs natively)
```

GPU shaders run natively — only CPU-side code is translated.

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

**Launch Steam:**
```bash
FEXBash steam
```

Note: The desktop shortcut does not work — always launch from terminal via `FEXBash steam`.

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

**Verify:**
```bash
box64 --version
# Box64 arm64 v0.4.1 ... with Dynarec
```

### Step 4: Configure Steam for Gaming

1. Use **Proton 10.0-2 beta** as the compatibility layer
2. Enable **DLSS 4 + Multi-Frame Generation** in supported games
3. Target **5120x1440 @ 120Hz** (HDMI 2.1a limit without DSC on Linux)

## Game Compatibility

### Why DLSS 4 Matters

The GB10's main bottleneck is memory bandwidth (273 GB/s vs ~900+ GB/s on a discrete RTX 5070). Without DLSS, the GPU is bandwidth-starved. With DLSS 4 Multi-Frame Generation, the GPU renders at a lower internal resolution and generates 3 out of every 4 frames via AI on the Tensor Cores — sidestepping the bottleneck entirely. Cyberpunk goes from ~50 FPS to 175+ FPS. DLSS is effectively mandatory for demanding titles.

### Confirmed Working on DGX Spark

| Game | Performance | Notes |
|------|------------|-------|
| **Cyberpunk 2077** | 175+ FPS (DLSS 4 MFG, path tracing, 1080p high) | ~50 FPS without DLSS. THE showpiece — full ray-traced Night City on a mini ARM PC. |
| **Returnal** | Smooth gameplay | PS5 exclusive running through x86 emulation + Proton. Opening videos slow, gameplay smooth. |
| **Clair Obscur: Expedition 33** | Playable | Unreal Engine 5 RPG, one of the prettiest games of 2025. |
| **Counter-Strike 2** | Smooth, multi-hour sessions | Competitive multiplayer FPS, no notable issues. |
| **Satisfactory** | Very smooth | Large open-world factory builder. |
| **Doom Eternal** | Smooth | id Tech 7, runs well at 1440p high settings. |
| **Outer Wilds** | Smooth, 20+ min sessions | No notable performance issues. |
| **Soul Calibur VI** | Runs great | — |
| **Marvel Cosmic Invasion** | No notable issues | — |
| **Hollow Knight: Silksong** | Very smooth | — |
| **PEAK** | Stable | Consistent across multiple test sessions. |
| **Half-Life 2** | Smooth | — |
| **Portal 2** | Smooth | — |
| **Dota 2** | Smooth | — |
| **Factorio** | Runs perfectly | — |
| **Garry's Mod** | Smooth | — |
| **Brotato** | Runs perfectly | — |
| **Vampire Survivors** | Runs great | — |
| **Golf with your Friends** | 100+ FPS | — |

Console emulation also works: Skate 3 (PS3 via RPCS3) at 60 FPS, Forza Motorsport (Xbox via Xemu) at 30 FPS @ 1080p.

### Likely to Work (DLSS 4 MFG + Proton Gold/Platinum, unconfirmed on Spark)

| Game | Why It Would Impress |
|------|---------------------|
| **Alan Wake 2** | Arguably the best-looking game ever made. Full path tracing. Proton Gold. |
| **Black Myth: Wukong** | Stunning visuals, path tracing, DLSS 4 support. |
| **God of War Ragnarok** | Sony's flagship visual showcase on PC. |
| **Hogwarts Legacy** | Beautiful open world with RT reflections. Proton Gold. |
| **Indiana Jones and the Great Circle** | id Tech engine, DLSS 4 support. |
| ~~Half-Life 2 RTX~~ | Crashes — see Known Issues below. |
| **S.T.A.L.K.E.R. 2** | Unreal Engine 5, atmospheric visuals. |
| **FINAL FANTASY XVI** | Spectacular visual effects. |
| **SILENT HILL 2 Remake** | Unreal Engine 5, atmospheric horror. |

### Known Issues

| Game | Issue |
|------|-------|
| **Half-Life 2 RTX** | RTX Remix bridge incompatible with ARM64 translation. **FEX-Emu:** access violation (0xc0000005) in NvRemixBridge.exe during `CreateDevice`. **Box64:** gets further — device creates successfully and draw calls flow, but deadlocks on Present semaphore (cross-process sync failure between 32-bit client and 64-bit server). Root cause: RTX Remix's dual-process shared-memory IPC architecture breaks under x86→ARM64 translation. Regular Half-Life 2 works fine. |

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

## Display Notes

- HDMI 2.1a only (no DisplayPort) — limits ultrawide refresh rate
- NVIDIA on Linux does not yet support DSC — expect 5120x1440 @ 120Hz max
- DLSS upscaling helps: render at lower internal resolution, output at native

## Key Resources

- [FEX Autoinstaller (NVIDIA)](https://github.com/esullivan-nvidia/fex_autoinstall)
- [Vulkan Fix Gist](https://gist.github.com/solatticus/14313d9629c4896abfdf57aaf421a07a)
- [Box64 v0.4.1](https://github.com/ptitSeb/box64)
- [Canonical ARM64 Steam Snap](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719)
- [Level1Techs GB10 Gaming How-To](https://forum.level1techs.com/t/nvidia-spark-gb10-msi-edgexpert-running-steam-games-cyberpunk-2077-doom-eternal-and-more-quickie-how-to/240557)
- [NVIDIA Developer Forum: Vulkan on GB10](https://forums.developer.nvidia.com/t/vulkan-on-nvidia-dgx-spark-gb10-working-repeatable/356570)
- [DGX Spark Software Updates 02/2026](https://forums.developer.nvidia.com/t/dgx-spark-software-updates-02-2026/360362)
