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

1. Use **Proton 10.0** (stable, not Experimental) as the compatibility layer
2. Enable **DLSS 4 + Multi-Frame Generation** in supported games
3. Target **5120x1440 @ 120Hz** (HDMI 2.1a limit without DSC on Linux)

## ARM64 Compatibility Guidelines

Games run through a multi-layer translation stack: Game → Proton/Wine → DXVK or VKD3D → FEX-Emu Vulkan thunk → native ARM64 NVIDIA driver. Not all Vulkan extensions are thunked in FEX-Emu, so games that use newer extensions will crash. These guidelines maximize success:

### What Works Best

- **DX11 games** — Translated by DXVK to Vulkan. DXVK uses a mature, well-tested subset of Vulkan that FEX's thunks fully support. This is the sweet spot.
- **Older DX9/DX10 games** — Also go through DXVK, same well-tested path.
- **Proton 10.0 stable** — Use this, not Proton Experimental. All confirmed working games use 10.0.

### What Breaks

- **Native Vulkan games** — May use `VK_EXT_descriptor_buffer` and other extensions that FEX's `libvulkan-host.so` doesn't thunk. Calls return null → crash.
- **DX12 games** — Translated by VKD3D-Proton, which may use newer Vulkan extensions (descriptor buffers, etc.) that hit thunk gaps. However, not all DX12 games crash — Witcher 3 Next-Gen DX12 works with full RT and DLSS Frame Gen. The outcome depends on which Vulkan extensions the specific VKD3D-Proton code path uses. Worth testing on a per-game basis.
- **RTX Remix titles** — Dual-process bridge architecture (32-bit client ↔ 64-bit server via shared memory IPC) breaks under x86→ARM64 translation.
- **Proton Experimental** — More aggressive feature usage, less tested on ARM64.

### Key Environment Variables (auto-set by Proton)

- `DXVK_ENABLE_NVAPI=1` — Makes DXVK expose NVIDIA GPU identity (GB10, 93 GB VRAM). Without this, games see "Unknown GPU" or fail detection.
- `Vulkan: 1` in `~/.fex-emu/Config.json` — FEX thunks forward Vulkan calls directly to native ARM64 driver instead of JIT-emulating them. Critical for performance and correctness.
- `fsync` — Wine's futex-based sync, supported by the 6.17 kernel. Active on all working games.

### Troubleshooting Tips

- If a game crashes at startup, try adding `-force d3d11` or `-dx11` to launch options (game-specific flag) to avoid DX12/Vulkan native paths.
- Use **Proton 10.0**, not Experimental.
- The `vkGetPhysicalDeviceDescriptorSizeEXT` error in Steam logs is the telltale sign of a FEX thunk gap — the game requires unthunked Vulkan extensions.
- Pressure-vessel Vulkan layer warnings (`nvidia_layers.json not in overrides`) are harmless — they fire on both working and broken games.
- Steam's own GPU topology shows `llvmpipe` — this is normal on ARM64 (the Steam UI runs under FEX). Games inside Proton see the real GPU via DXVK+NVAPI.

## Game Compatibility

### Why DLSS 4 Matters

The GB10's main bottleneck is memory bandwidth (273 GB/s vs ~900+ GB/s on a discrete RTX 5070). Without DLSS, the GPU is bandwidth-starved. With DLSS 4 Multi-Frame Generation, the GPU renders at a lower internal resolution and generates 3 out of every 4 frames via AI on the Tensor Cores — sidestepping the bottleneck entirely. Cyberpunk goes from ~50 FPS to 175+ FPS. DLSS is effectively mandatory for demanding titles.

### Tested by AGB

Games personally tested on this DGX Spark (GB10, Proton 10.0, FEX-Emu, driver 580.126.09).

| Game | API | Performance | Notes |
|------|-----|------------|-------|
| **Age of Empires II DE** | DX11 | Smooth, 39+ min sessions | DX11 via DXVK. GPU detected as NVIDIA GB10 (93 GB VRAM). Clean exits, no crashes. |
| **Balatro** | DX11 | Smooth, fullscreen | No issues. |
| **BioShock Remastered** | DX11 | Smooth, maxed settings | DX11 via DXVK. No issues. |
| **Brotato** | DX11 | Smooth, fullscreen | No issues. |
| **Data Center Demo** | DX11 | Smooth, maxed settings | No issues. |
| **Crab Champions** | DX11 | Smooth, maxed, 5120x1440 | UE4 via DXVK. Flawless at full ultrawide. |
| **Crysis** | DX10 | Choppy, maxed, 1920x1080 | CryEngine 1 via DXVK. Runs but inconsistent FPS — smooth in some areas, choppy in others (especially water). CPU-heavy engine + translation overhead likely the bottleneck. **TODO:** Retest at 5120x1440 ultrawide. |
| **Cyberpunk 2077** | DX12 | 175+ FPS (DLSS 4 MFG, path tracing, 3840x1080) | ~50 FPS without DLSS. Launch options: `PROTON_ENABLE_NGX_UPDATER=1 PROTON_ENABLE_NVAPI=1 %command%`. NGX updater pulls DLSS 4 MFG from driver 580 automatically. |
| **Golf with your Friends** | DX11 | 100+ FPS, maxed settings | DX11 via DXVK. No launch options needed. |
| **Lord of the Rings Online** | DX11 | Smooth, maxed out | DX11 via DXVK. Launcher patches from game servers fine. No launch options needed. |
| **Lost Planet: Extreme Condition** | DX10 | Smooth, maxed settings | DX10 via DXVK. No issues. |
| **Mafia II: Definitive Edition** | DX11 | Smooth, maxed settings | DX11 via DXVK. High FPS, no issues. |
| **Painkiller: Black Edition** | DX9 | Smooth, maxed (640x480) | Must use 640x480 — higher resolutions render in a tiny portion of the window. Changing resolution in-game crashes to desktop. Other settings maxed, runs well. |
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
| **Sledding Game Demo** | DX11 | Smooth, maxed, 300 Hz | Online multiplayer tested. No issues. |
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
| **Black Myth: Wukong** | DX12-only (Unreal Engine 5, no DX11 fallback). Crashes ~18 seconds in during level load — gets to loading screen with cloud icons but dies when renderer hits VKD3D-Proton descriptor_buffer gap. Both regular and compatibility mode crash identically. Needs FEX `VK_EXT_descriptor_buffer` support. |
| **Elden Ring** | DX12-only. Same `VK_EXT_descriptor_buffer` crash as Halo Infinite — identical EasyAntiCheat loading screen followed by crash. |
| **Half-Life 2 RTX** | RTX Remix bridge incompatible with ARM64 translation. **FEX-Emu:** access violation (0xc0000005) in NvRemixBridge.exe during `CreateDevice`. **Box64:** gets further — device creates successfully and draw calls flow, but deadlocks on Present semaphore (cross-process sync failure between 32-bit client and 64-bit server). Root cause: RTX Remix's dual-process shared-memory IPC architecture breaks under x86→ARM64 translation. Regular Half-Life 2 works fine. |
| **Halo Infinite** | DX12-only. Crashes at launch — `vkGetPhysicalDeviceDescriptorSizeEXT` unthunked in FEX. Same `VK_EXT_descriptor_buffer` gap as NMS and Wukong. Fails on both Proton 10.0 and Proton Experimental. |
| **No Man's Sky** | Crashes ~16 seconds into launch, never renders a frame. `vkGetPhysicalDeviceDescriptorSizeEXT` unthunked in FEX. `-force d3d11` launch option does not help — game still probes Vulkan extensions and crashes. Tested on Proton 10.0 and Experimental. |
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

**DX9/DX10/DX11 — Expected to Work (DXVK sweet spot):**

| Game | API | Notes |
|------|-----|-------|
| Burnout Paradise: The Ultimate Box | DX9 | Criterion racer, should be straightforward |
| Counter-Strike: Source | DX9 | Source engine, likely fine |
| Crysis 2: Game of the Year | DX9/DX11 | CryEngine 3, DX11 Ultra upgrade |
| Crysis Warhead | DX9/DX10 | CryEngine 1, same expectations as Crysis |
| CS2D | DX/OpenGL | 2D top-down game, trivial |
| Dark Souls: Prepare to Die Edition | DX9 | Original port, notoriously bad even on x86 |
| Dark Souls II: Scholar of the First Sin | DX11 | From Software, DX11 via DXVK |
| Dark Souls III | DX11 | From Software, DX11 via DXVK — high confidence |
| Far Cry | DX9 | CryEngine 1 (2004), very old |
| Far Cry 2 | DX9/DX10 | Dunia Engine |
| Far Cry 3 | DX9/DX11 | Dunia Engine 2 |
| Far Cry 3: Blood Dragon | DX11 | Same engine as FC3 |
| Far Cry 4 | DX11 | Dunia Engine |
| Far Cry 5 | DX11 | Dunia Engine |
| Far Cry New Dawn | DX11 | Same engine as FC5 |
| Far Cry Primal | DX11 | Dunia Engine |
| Half-Life | OpenGL/D3D | GoldSrc engine (1998) |
| Half-Life: Source Deathmatch | DX9 | Source engine |
| Half-Life 2: Deathmatch | DX9 | Source engine, same as HL2 |
| Hellpoint | DX11 | Unity engine |
| Just Cause 3 | DX11 | Avalanche engine, open world |
| Left 4 Dead | DX9 | Source engine |
| Quake 2 (remaster) | DX11/Vulkan | KEX engine remaster — test DX11 mode first |
| Space Engineers | DX11 | Voxel sandbox, CPU-heavy |
| Star Wars: The Old Republic | DX9 | MMO, HeroEngine — may need launcher workarounds |
| Supermarket Together | DX11 | Unity co-op game |
| The Elder Scrolls Online | DX11 | MMO (Zenimax Online dir), may need launcher work |
| The Witcher | DX9 | Aurora Engine (2007), old but janky |
| The Witcher 2 | DX9 | RED Engine, DX9 |

**DX12 — May Work (VKD3D-Proton, mixed results):**

| Game | API | Notes |
|------|-----|-------|
| Control | DX11/DX12 | Northlight Engine. Try DX11 mode first — DX12 mode with RT is the showcase but may hit thunk gaps |
| Death Stranding: Director's Cut | DX12 | Decima Engine. DLSS support. |
| Elden Ring: Nightreign | DX12 | Same engine as Elden Ring — base game crashes (descriptor_buffer). Expect same result. |
| Far Cry 6 | DX12 | Dunia Engine, DX12 primary renderer |
| Grand Theft Auto V Enhanced | DX12 | New RAGE engine build, DX12-only. Rockstar Launcher may be an obstacle (same issue as RDR2). |
| RoboCop: Rogue City | DX12 | UE5 — same engine as Black Myth: Wukong. Likely crashes. |
| Strange Brigade | DX12/Vulkan | Asura Engine. Has Vulkan renderer — test both. |

**Vulkan / OpenGL — Uncertain:**

| Game | API | Notes |
|------|-----|-------|
| DOOM (2016) | Vulkan | id Tech 6. Doom Eternal (id Tech 7) works — good sign, but different engine version. |
| DOOM 3 | OpenGL | id Tech 4, OpenGL renderer |
| DOOM 3 BFG Edition | OpenGL | id Tech 4 remaster, OpenGL |
| Prey (2006) | OpenGL | id Tech 4 variant (Human Head), old |
| Quake II RTX | Vulkan (RT) | RTX path tracing via Vulkan — may hit thunk gaps like other RT titles |

**Classic Doom (KEX Engine Rereleases) — Likely Trivial:**

| Game | API | Notes |
|------|-----|-------|
| Doom 2 | Vulkan/OpenGL | KEX engine rerelease, extremely lightweight |
| Final Doom | Vulkan/OpenGL | KEX engine rerelease |
| Master Levels of Doom | Vulkan/OpenGL | KEX engine rerelease |
| Ultimate Doom | Vulkan/OpenGL | KEX engine rerelease |

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
- [Box64 v0.4.1](https://github.com/ptitSeb/box64)
- [Canonical ARM64 Steam Snap](https://discourse.ubuntu.com/t/call-for-testing-steam-snap-for-arm64/74719)
- [Level1Techs GB10 Gaming How-To](https://forum.level1techs.com/t/nvidia-spark-gb10-msi-edgexpert-running-steam-games-cyberpunk-2077-doom-eternal-and-more-quickie-how-to/240557)
- [NVIDIA Developer Forum: Vulkan on GB10](https://forums.developer.nvidia.com/t/vulkan-on-nvidia-dgx-spark-gb10-working-repeatable/356570)
- [DGX Spark Software Updates 02/2026](https://forums.developer.nvidia.com/t/dgx-spark-software-updates-02-2026/360362)
