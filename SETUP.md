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

## Performance Reference

| Game | Without DLSS | With DLSS 4 + MFG |
|------|-------------|-------------------|
| Cyberpunk 2077 | ~50 FPS @ 1080p medium | 175+ FPS |

The 273 GB/s memory bandwidth is the main bottleneck for rasterization. DLSS is effectively mandatory for demanding titles.

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
