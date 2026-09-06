# DLSS 5 on DGX Spark (GB10) — Definitive Assessment, 2026-09-05

## 1. VERDICT

**No.** DLSS 5 does not run on a DGX Spark today, by any route, sanctioned or otherwise. Nobody on Earth has run it on ARM64.

But the *reason* is now completely different from what the prior analysis said, and the honest full verdict has three parts:

- **Officially: No, and no path exists.** NVIDIA scopes DLSS 5 to GeForce RTX 50 Series ([nvidia.com DLSS 5 launch article, 2026-09-01](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/), NVIDIA-official). No Linux driver on **any** architecture ships DLSS 5's feature module. There is no public DLSS 5 SDK and no Streamline 2.14.
- **Unofficially: Conditionally, untested, and almost certainly unplayable.** DLSS 5 Neural Rendering was made to run under Linux/Proton for the first time on **2026-09-04** — on driver **610.57.04**, the branch this machine can install today. The mechanism bypasses the driver entirely. GB10 clears every hardware gate that was measured. But the route requires a ~165 MB proprietary DLL that ships inside retail games, has never been attempted on ARM64/FEX, is unstable even on x86-64, and would cost 40-60% of frame time on a GPU with a seventh of an RTX 5090's memory bandwidth.
- **Practically, for a person deciding where to spend a weekend: No.** The realistic best case is "NGX feature 18 returns `Success` and composites a correct frame on a GB10" — a genuine first, worth a log entry — not a playable setting.

The prior analysis reached the right answer for four wrong-ish reasons. Correcting them matters, because three of the four are now actively misleading in this repo's log.

---

## 2. WHAT CHANGED — auditing the four prior blockers

| # | Prior blocker | Verdict | Correction |
|---|---|---|---|
| 1 | No R615/R616 *Linux* driver exists | **True but not load-bearing** | The fact is confirmed at primary source. The inference drawn from it is wrong. |
| 2 | GB10 pinned to 580; sbsa tops at 580.178.04; users bricked Sparks on 590+ | **False on all three counts** | Demolished by direct apt/repo evidence. |
| 3 | DLSS 5 scoped to RTX 50 desktop/laptop; workstation Blackwell is DLSS 4 tier | **Substantially broken** | Marketing scope, not a silicon wall. |
| 4 | dxvk-nvapi 0.9.2 only reaches R595 NVAPI; no Streamline 2.14 entry points | **True as fact, refuted as blocker; premise itself is a misreading** | DLSS 5 does not use Streamline or the NVAPI DLSS surface. |

### Blocker 1 — survives as fact, dies as reasoning

Confirmed at NVIDIA's own artifact index: [download.nvidia.com/XFree86/Linux-aarch64/](https://download.nvidia.com/XFree86/Linux-aarch64/) and `/Linux-x86_64/` both top out at **610.57.04** (dated 2026-07-29). Direct HTTP probes of 611/612/613/615/616/620 return 404 against a 200 control. [nvidia.com/en-us/drivers/unix/](https://www.nvidia.com/en-us/drivers/unix/) lists Production 595.99.02 / New Feature 610.57.04 for x86_64, aarch64, FreeBSD and Solaris identically. NVIDIA/open-gpu-kernel-modules git tags agree.

**But waiting for R615 Linux is waiting for something that does not contain what is being waited for.** An R615-branch Linux aarch64 `libnvidia-ngx.so` **already exists and is publicly downloadable** — version 615.41, shipped as the WSL payload inside NVIDIA's Windows-on-Arm driver package. Its 39 exported symbols are byte-identical to 610.57.04's, and `strings | grep -ci dlssnr` returns **0**, exactly as it does for 580.173.02, 610.43.02 and 610.57.04. Every Linux NGX core ever shipped knows exactly three DLSS features: `dlss`, `dlssd`, `dlssg`.

DLSS 5's model does not come from the driver on *any* platform. NVIDIA's own 616.00 ARM64 package was enumerated exhaustively (276 entries): it ships `nvngx_dlssg.dll` but no `nvngx_dlssnr.dll`, and `grep -aoic dlssnr` over the raw 775 MB installer returns 0.

### Blocker 2 — demolished

Verified first-hand on this machine:

```
apt-cache policy nvidia-open        → Candidate: 610.57.04-1ubuntu1  (sbsa CUDA repo)
apt-cache policy nvidia-driver-610-open → Candidate: 610.43.02-0ubuntu0.24.04.1
                                          (ports.ubuntu.com noble-updates/multiverse arm64)
linux-modules-nvidia-610-open-6.17.0-1032-nvidia  6.17.0-1032.32   ← exact running kernel
```

The sbsa repo carries `nvidia-open` at 590.44.01, 590.48.01, 595.45.04–595.91.07, 610.43.02 and 610.57.04 for arm64 ([repo index](https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa/), NVIDIA-official). The prior analysis was misled by a packaging change: from R590 onward NVIDIA dropped the branch-numbered `nvidia-driver-<N>-open` metapackage in favour of unversioned `nvidia-open`.

**GB10 (PCI `2E12`) is listed as a supported product in every Linux aarch64 driver from 580.173.02 through 610.57.04.** Verbatim from [610.57.04's supportedchips.html](https://download.nvidia.com/XFree86/Linux-aarch64/610.57.04/README/supportedchips.html): `NVIDIA GB10   2E12 10DE 21EC`.

The apt pins on this box (`/etc/apt/preferences.d/cuda-compute-repo-lowpri2`) deprioritise only **branch-580** packages from the CUDA repo, steering the box to Ubuntu's 580 build. Nothing blocks 590/595/610. No `nvidia-driver-pinning-*` package is installed. The DGX Spark OTA repo contains **zero driver packages**.

**"Bricked Sparks" has no primary source.** The whole gathered corpus contains one rhetorical use of "brick" in a saved ChatGPT transcript. What actually exists is: an NVIDIA staff caveat of 2026-03-12 ("driver 590 and hwe kernels are not yet supported on the Spark"), one user reporting a frozen desktop on 590 recovered by an apt downgrade over SSH, and a [documented success on 610.43.02](https://forums.developer.nvidia.com/t/upgraded-driver-of-spark-to-610-43-02-so-far-so-good/373994) (forum, 2026-06-21, single user, with follow-up confirmation 2026-07-07).

The real constraint is **support policy**: [NVIDIA DGX OS 7 User Guide](https://docs.nvidia.com/dgx/dgx-os-7-user-guide/additional_software.html), page last updated **2026-09-05**, states verbatim *"The DGX B300, DGX Spark, and DGX GB300 require the Release 580 family of the NVIDIA open GPU kernel modules."* — and, in the same page, *"For driver release 595 and later, upgrading to DGX OS 8 is recommended."* (DGX OS 8 has no public documentation; the URL 404s.)

**This correction should be made in the repo's log regardless of the DLSS question.** "GB10 is pinned to 580" is currently recorded as a hardware fact and it is a policy statement.

### Blocker 3 — substantially broken

Two NVIDIA-official pages now contradict each other:

- [nvidia.com/en-us/products/rtx-spark/](https://www.nvidia.com/en-us/products/rtx-spark/) spec table, verified by raw HTML fetch: `NVIDIA DLSS | DLSS 5` for a **6144-core Blackwell RTX GPU + 20-core Grace CPU + up to 128 GB LPDDR5X** — the DGX Spark GB10 configuration exactly.
- [The DLSS 5 launch article](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/) names only "all GeForce RTX 50 Series GPUs and laptops, and GeForce NOW", and never mentions RTX Spark, N1X, GB10, RTX PRO or Linux.

Independently, the gate is demonstrably software:

- NVIDIA told Wccftech on the record (journalism relaying an NVIDIA statement): *"Once RTX 50 Series performance is more fully tuned, we plan to work on expanding official support to the GeForce RTX 40 Series."* ([wccftech](https://wccftech.com/nvidia-dlss-5-rtx-40-gpus-support-confirmed/), 2026-09-03)
- Modders run DLSS 5 NR on Ada, Ampere and Turing by rewriting the DLL's CUDA fatbins ([dev-camo/dlssnr-patcher](https://github.com/dev-camo/dlssnr-patcher), source read directly; [Tom's Hardware](https://www.tomshardware.com/pc-components/gpus/exclusive-dlss-5-has-already-been-ported-to-work-on-rtx-4000-series-graphics-cards-incompatible-cuda-instructions-get-patched-to-work-on-previous-gen-hardware), journalism).
- It has been reimplemented from scratch in HIP for AMD RDNA3/4 ([danielblnc/DLSS-NR-on-AMD](https://github.com/danielblnc/DLSS-NR-on-AMD), 659 stars, created 2026-09-03).
- The FP4/5th-gen-Tensor-core theory is wrong: DLSS 5 runs in **FP8**, which Ada supports natively — which is *why* the RTX 40 backport works.

**Measured on this GB10** (first-hand, reproducible): an inline-PTX `mma.sync.aligned.m16n8k32.row.col.f32.e4m3.e4m3.f32` compiled `-gencode arch=compute_120,code=sm_120` with no PTX fallback lowers to a genuine `QMMA.16832.F32.E4M3.E4M3` tensor-core op and **executes correctly** (`D = 32 32 32 32`, the exact expected e4m3 k=32 accumulation). GB10 can run DLSS 5's arithmetic.

Downgrade blocker 3 from "architectural barrier" to "product-tier marketing scope."

### Blocker 4 — refuted as a blocker, and the premise was a misreading

The version facts hold: dxvk-nvapi's newest release is v0.9.2 (2026-05-12, R595 headers); public Streamline tops out at [v2.12.0](https://github.com/NVIDIA-RTX/Streamline/releases) (2026-06-23, single `main` branch, no neural-rendering header in `include/`).

But **"Streamline 2.14+" is not a DLSS 5 requirement.** In [NVIDIA's own Game Ready article](https://www.nvidia.com/en-us/geforce/news/nba-2k27-dlss-5-3d-guided-neural-rendering-geforce-game-ready-driver/) that sentence sits in the **DLSS 4.5 Dynamic Multi Frame Generation** frame-limiter / V-Sync section, not the DLSS 5 section. If 2.14 were a hard DLSS 5 dependency, DLSS 5 would be impossible for everyone, since NVIDIA has never published it.

And the working path uses neither Streamline nor NVAPI's DLSS surface. What it *does* use from dxvk-nvapi is the **D3D12 CUDA-interop family** — `NvAPI_D3D12_CreateCubinComputeShader{,Ex,ExV2,WithName}`, `CreateCuFunction`, `CreateCuModule`, `LaunchCubinShader`, `GetCudaSurfaceObject`, `GetCudaTextureObject`, `GetCudaMergedTextureSamplerObject`, `GetCudaIndependentDescriptorObject`, `DestroyCubinComputeShader` — **all 12 of which are already exported by the `nvapi64.dll` shipped in Proton 11.0 on this machine** (verified by `strings` on `Proton 11.0/files/lib/wine/nvapi/x86_64-windows/nvapi64.dll`, version file `dxvk-nvapi (v0.9.2)`).

Separately, GB10 **already reports as consumer Blackwell** through dxvk-nvapi with no spoofing: `NvapiAdapter::GetArchitectureId()` returns `NV_GPU_ARCHITECTURE_GB200` when `VK_KHR_compute_shader_derivatives` is present and `meshAndTaskShaderDerivatives` is true — both verified true via `vulkaninfo` on this GB10.

### What the "September 2026 leads" actually were

Two things landed in the Sept 3-5 window, and neither is what it was reported to be:

1. **NVIDIA's RTX Spark spec-table wave (Sept 3-4).** The product page gained a spec table listing DLSS 5 sometime between 2026-06-11 (Wayback snapshot: zero `<table>` elements, zero occurrences of "N1X") and 2026-09-05. NVIDIA's May 31 press release and June coverage said **DLSS 4.5** ([PCWorld, 2026-06-02](https://www.pcworld.com/article/3153578/nvidia-rtx-spark-could-be-game-changing-for-gaming-handhelds.html) explicitly: "RTX Spark only supports DLSS 4.5"). This is a real, recent, NVIDIA-official change — about a different product.
2. **A GitHub DLSS 5 modding ecosystem that exploded 2026-08-29 → 2026-09-05**, including the first working Linux/Proton implementation. This is almost certainly the actual substance behind "posts from today suggesting paths forward," and it is genuinely significant.

**What was searched and found empty:** the NVIDIA DGX Spark/GB10 developer forum category (all Sept 1-5 traffic is LLM inference and GB10 retail pricing); Hacker News (DLSS 5 and Spark are disjoint communities there); the one on-point thread [*"DLSS support for GB10/Spark?"*](https://forums.developer.nvidia.com/t/dlss-support-for-gb10-spark/364161) has **one post and zero replies since 2026-03-20**. Reddit was unreachable (crawler blocked) and remains the one unchecked venue.

---

## 3. RTX SPARK — what it actually is

**NVIDIA-official facts** ([product page](https://www.nvidia.com/en-us/products/rtx-spark/), [IFA blog 2026-09-03](https://blogs.nvidia.com/blog/local-ai-ifa-next-gen-agents-nv-pair-rtx-spark/)):

- RTX Spark N1X, two configs: 6144-core Blackwell RTX + 20-core Grace (up to 128 GB LPDDR5X, 45-80 W laptop / 140 W desktop), and 5120-core + 18-core (up to 64 GB).
- 4th-gen RT cores, 5th-gen Tensor cores, **DLSS 5**, Reflex 2 with Frame Warp.
- **OS Support: Windows 11.** No Linux row exists anywhere on the page.
- Ships **October 2026**; OEMs Acer, ASUS, Dell, Gigabyte, HP, Lenovo, Microsoft, MSI. No official pricing (every dollar figure in circulation traces to a Morgan Stanley analyst note).

### Same silicon as GB10?

**Same family, adjacent device IDs, one Linux driver — but not proven bit-identical, and different PCI devices.**

| | Device ID | Subsystem | Codename (pci.ids) |
|---|---|---|---|
| DGX Spark (this box) | `10de:2E12` | `10DE:21EC` | GB20B [GB10] |
| RTX Spark N1X 6144c | `10de:2E03` | `1043` (ASUS) / `1414` (Microsoft) | GB20B [RTX Spark N1X] |
| RTX Spark N1X 5120c | `10de:2E06` | same | GB20B [RTX Spark N1X] |
| "NVIDIA Desktop Device" | `10de:2E13` | `1414` | GB20B [Desktop Device] |

**For:** Huang stated on the record that N1 is the processor going into DGX Spark ([VideoCardz](https://videocardz.com/newz/nvidia-ceo-confirms-n1-chip-is-actually-gb10-superchip-used-in-dgx-spark), journalism; Tom's Hardware original paywalled). GPU/CPU/memory configurations match exactly. Upstream pci.ids marks all four as the same **GB20B** silicon designation. Most importantly: **NVIDIA's Linux aarch64 610.57.04 driver lists GB10 `2E12` and N1X `2E03`/`2E06` in the same supported-chips table** — one driver, one code path. The N1X entries are *new* in 610.57.04 (absent from 610.43.02).

**Against:** Huang said *N1*, not N1X, and said nothing about dies being identical. ServeTheHome (2026-06-01) explicitly declines: *"it is not even clear if N1X is a distinct chip."* And there is concrete hardware counter-evidence — NVIDIA's RTX Spark Windows INF binds ACPI NPU/DLA devices (`ACPI\NVDA200A`, `ACPI\NVDA2042`, "NVIDIA NPU"). This DGX Spark has no such device: `ls /dev/nvhost* /dev/dla*` returns nothing and `lspci` shows no NPU.

### Does RTX Spark's DLSS 5 imply anything for this machine?

**Directly: no.** It is a Windows-11-on-N1X claim about `2E03`/`2E06`. This box is `2E12` running Linux. NVIDIA's ARM64 Windows driver (616.00, `nv_surface_woa.inf`, DriverVer 07/13/2026) binds only `2E03`, `2E06`, `2E13`, every one SUBSYS-locked to `0x1414` (Microsoft). `2E12` appears nowhere. And no ARM64 616.64 exists — probed and 404, while the x86-64 616.64 WHQL returns 200.

**Indirectly: yes, and this is the single best structural reason for hope.** It kills the "GB10 is architecturally excluded" theory outright — NVIDIA is shipping DLSS 5 on a Grace-Blackwell ARM SoC with GB10's exact GPU configuration. And because *one* Linux aarch64 driver already serves both device IDs, if NVIDIA ever ships DLSS 5 in a Linux driver for N1X, GB10 sits in the same table. That is a real structural argument, not wishful thinking. It is also entirely speculative: RTX Spark is announced as Windows-only, and NVIDIA has never answered the community's DLSS-on-GB10 question in six months.

---

## 4. SURVIVING PATHS

### Path A — Community NGX feature-18 forwarder under Proton x86-64 + FEX
**Status: the only path that survived refutation. Never attempted on ARM64 by anyone.**

**Why it survives.** DLSS 5 Neural Rendering is delivered as a game-shipped snippet (`nvngx_dlssnr.dll`, build 310.8.x, ~165 MB), and the working implementations call the *snippet's own exports* directly, bypassing the driver's NGX dispatch entirely. From [NapXDD/addon-dlssnr-linux](https://github.com/NapXDD/addon-dlssnr-linux)'s `nr_forwarder.cpp`, read directly:

> *"nvngx_dlssnr.dll resolves the module owning its return address and requires that module's path to contain `nvngx.dll` (the driver core is `_nvngx.dll`); everything else gets FAIL_PlatformError before a single argument is read. So this DLL is named `nvngx.dll_nrfwd.dll` and does nothing but load the snippet and forward Init/Create/Evaluate/Release."*

It calls `NVSDK_NGX_D3D12_Init_Ext(...)` then `CreateFeature(cmd, 18, params, &handle)` on the snippet itself, reusing only the driver core's capability parameter block ("the block's setters are the driver's own and check nothing"). Results are stored through a `volatile` to defeat tail-call optimisation, because a `jmp` would make the snippet resolve its caller past the forwarder.

**Two independent working Linux reports, both this week** (forum/issue-tracker claims, but with verbatim runtime logs, from different reporters on different hardware, distros and Proton builds):
- Issue #1: RTX 5070, **driver 610.57.04**, Arch, Proton 10.0 — `CreateFeature(18) => 0x1 (Success)`, ~21,600 consecutive successful evaluates over eight minutes.
- Issue #3: RTX 4080 (Ada), driver 610.57.04, GE-Proton11-6, GTA V Enhanced — 16,200 evaluations with a community-patched model, no failures.

**What GB10 already satisfies, all measured first-hand on this machine:**
- NGX architecture gate: the 610 core logs `Blackwell detected, chip is 5b` → `GPU architecture : 0x1B0` — exactly the `NVSDK_NGX_GPU_Arch_Blackwell2` value the snippet demands. (The installed 580 core reports `0x7FFFFFF`, even more permissive.)
- FP8 e4m3 tensor-core MMA compiled sm_120-only executes correctly (`QMMA.16832.F32.E4M3.E4M3`).
- Vulkan: `VK_NVX_binary_import` rev 2 and `VK_NVX_image_view_handle` rev 3 — satisfying vkd3d-proton's `supports_cubin_64bit` gate exactly.
- FEX-2607 thunks `vkCreateCuModuleNVX`, `vkCreateCuFunctionNVX`, `vkCmdCuLaunchKernelNVX`, `vkGetImageViewHandle64NVX` on both host and guest sides, with custom repacking for `VkCuLaunchInfoNVX`. **This is not another `VK_EXT_descriptor_buffer`-style gap.**
- Proton 11.0's `nvapi64.dll` exports all 12 D3D12 CUDA-interop entry points; its vkd3d-proton contains `CreateCubinComputeShaderExV2`.
- GB10 reports as `GB200`/`GB202` to NVAPI with no spoofing.

**Concrete next steps, in order:**
1. **Acquire the model legitimately.** Buy and install a DLSS 5 title (NBA 2K27 is the only shipping one) and confirm it ships `nvngx_dlssnr.dll`. Do not use community redistribution points or one-click installers — see §5.
2. **Answer the one decidable unknown before anything else:** carve the fatbins out of the PE (`cuobjdump` returns a false negative on PE containers — scan raw bytes for `0xBA55ED50` / `e_machine == 190`) and check whether the ELF images are `sm_120`/`sm_120f` or `sm_120a`. **Measured on this GB10: `sm_120` and `sm_120f` load; `sm_120a` fails with `CUDA_ERROR_NO_BINARY_FOR_GPU`.** Mitigating: `dlssnr-patcher` hard-asserts every DLSS-NR fatbin contains exactly one PTX image, so JIT fallback probably rescues even the bad case — and NVIDIA's own shipped snippets ship sm_75/80/86/89 cubins plus sm_89 PTX with zero Blackwell code, reaching Blackwell purely by driver JIT.
3. Use **Proton 11.0 x86-64**, not Proton ARM64 (see §5). Prebuilt artifacts: `dlssnr-linux.addon64` + `nvngx.dll_nrfwd.dll` from NapXDD releases (v0.2.2, 2026-09-05). ReShade DX12/`dxgi` path. Launch options `PROTON_ENABLE_NVAPI=1 WINEDLLOVERRIDES="dxgi=n,b"`.
4. Consider upgrading to driver 610 first (Path B) — every working Linux report is on 610.57.04, and 610's NGX has Blackwell chip detection that 580's lacks entirely.
5. **Obey the repo's process hygiene.** Never wrap the launch in `timeout`; shut down with `wineserver -k` explicitly; never `pgrep -f` a pattern matching your own command line.

**Honest probability:**
- Feature 18 returns `Success` and composites a correct frame on GB10: **~20-30%.** Untested risks stack: Detours hooking x86-64 prologues under FEX's JIT; ReShade's `dxgi` hook under FEX; a 165 MB CUDA-bearing PE driving `nvcuda.dll` through the FEX/vkd3d/NVX chain.
- Playable frame rate: **~0%.** Cost is 39% on an RTX 4090 and ~51% on an RTX 5070 Ti at 4K. GB10 is 48 SMs on 273 GB/s unified LPDDR5X against an RTX 5090's ~1.8 TB/s, with FEX overhead on top. RTX 50 owners only make it usable by spending the recovered headroom on 4x/6x MFG, which GB10 does not have.

**A known instability even on x86-64:** [dxvk-nvapi issue #393](https://github.com/jp7677/dxvk-nvapi/issues/393) (open, 2026-09-06): `NvAPI_D3D12_GetCudaSurfaceObject` never returns, access violation reading `0x18`, on RTX 4080 + driver 610.57.04 + vkd3d-proton 3.0.1. Disabling those entry points avoids the crash but yields a constant black frame (output hash byte-identical across 4,338 evaluates) — proving the CUDA-object path is load-bearing.

### Path B — Upgrade to driver 610 and re-measure
**Status: survives as a worthwhile experiment. Delivers zero DLSS 5 on its own.**

`apt-get -s install nvidia-driver-610-open linux-modules-nvidia-610-open-nvidia-hwe-24.04` resolves cleanly on this box with a Canonical-signed prebuilt module matching the running `6.17.0-1032-nvidia` kernel — Secure Boot stays on. (One analysis pass found `nvidia-dkms-610-open` pulled as a hard dependency even so; **verify the simulation output yourself before committing.**)

Value: 610's NGX adds Blackwell chip detection (`Blackwell detected, chip is %x`, `nvmlArchToNGX`) that the r580 core lacks entirely, plus the `FGX` feature family; and it is the exact version every working Linux DLSS 5 report runs on.

Risks, stated honestly: it is **off NVIDIA's DGX OS validation path** — the DGX OS 7 guide, updated the day of this analysis, still says Spark requires R580. It will desync the FEX RootFS (`tools/sync-rootfs-nvidia.sh` must be re-run against **x86_64** 610 debs, not the arm64 ones). And the hand-made `/usr/lib/aarch64-linux-gnu/nvidia/wine/` bridge will not survive a driver reinstall.

**Do it with an SSH session held open from another machine.** The one documented failure mode (a frozen desktop on 590) was recovered by an apt downgrade over SSH.

Probability of a clean install: **~85%.** Probability it enables anything DLSS-5-related by itself: **0%.**

### Path C — Wait for NVIDIA
**Status: the sanctioned route. Low probability, but the only one that ends in something supportable.**

Probability a Linux aarch64 driver ships a `dlssnr` feature by end of 2026: **~10%.** The model is game-delivered on Windows; there is no Linux delivery channel; the NGX OTA updater has no NR package id at any branch; and NVIDIA has never answered a GB10 DLSS question in six months.

### Path D — GeForce NOW
**Status: works, but it is watching DLSS 5, not running it.**

DLSS 5 shipped on GFN on 2026-09-03, rendered on NVIDIA-operated RTX 5080 rigs ([NVIDIA blog](https://blogs.nvidia.com/blog/geforce-now-thursday-september-2026/)). NVIDIA's native Linux client is an **x86-64-only flatpak** (verified: the OSTree repo publishes exactly one ref, `app/com.nvidia.geforcenow/x86_64/master`; `GeForceNOWSetup.bin` is a native x86-64 ELF). The `geforcenow` snap's arm64 build is Canonical-published and frozen at rev 24 / 1.11.1 from 2025-12-11.

The browser path should work: Chrome 152 aarch64 with ARM64 Widevine is installed. Note that **no VA-API driver is installed** on this box (`/usr/lib/aarch64-linux-gnu/dri/` has no nvidia entry), so decode will be software. `nvidia-vaapi-driver` 0.0.8-1 is available for arm64 from noble/universe — worth installing before judging GFN's quality here.

### Adjacent opportunity (not DLSS 5, but real)
**Proton ARM64's missing NVAPI is a small, tractable, upstream-contributable fix, and this machine is the hardware nobody has.**

[Proton issue #9439](https://github.com/ValveSoftware/Proton/issues/9439) is **open**, and explicitly names the HP ZGX Nano AI station — this exact machine. Valve's `ivyl` (2026-01-27): *"It was originally disabled because it did not build with clang for ARM64. This may have changed since."* Contributor `Saancreed` (2026-01-28) successfully built `nvapi.dll` as ARM64EC with bylaws' llvm-mingw and posted a complete working meson cross file — but *"I don't have proper hardware to test this."*

Proton's `Makefile.in` already defines `DXVK_NVAPI_arm64ec_MESON_ARGS = --bindir=.../nvapi/aarch64-windows` and is missing only the `$(eval $(call rules-meson,dxvk-nvapi,arm64ec,windows))` line. The NGX bridge DLLs are **already correctly copied** into ARM64 prefixes (Proton's copy loop is not architecture-gated); the only missing file is `nvapi64.dll`. Note `PROTON_FORCE_NVAPI` cannot help — the arch test is ANDed *outside* the `forcenvapi` or-expression, so it is structurally unable to override.

That would restore DLSS **4** on native-ARM64 Proton, which is a real capability this repo currently records as lost.

---

## 5. DEFINITIVE DEAD ENDS

**Waiting for an R615/R616 Linux driver to ship DLSS 5.**
An R615 Linux aarch64 NGX core already exists (615.41, inside the WoA 616.00 package). Its exported symbols are byte-identical to 610.57.04's; its loadable-snippet table is the same 16 entries; `grep -ci dlssnr` = 0. NVIDIA ships the NR model in games, not drivers.

**Harvesting `_arm64_nvngx.dll` for Proton 11 ARM64.**
Two independent kills. (a) The binary is Windows-bound: build paths `nvngx_common_nvapi.cpp` / `nvngx_platform_windows.cpp`, it talks to `nvlddmkm.sys` via NVAPI, and there is no Linux/Unix-socket transport. (b) The diagnosis was wrong anyway — the NGX bridge DLLs are *already present* in ARM64 prefixes. The actual missing piece is `nvapi64.dll`, blocked upstream in dxvk-nvapi's `meson.build`, which has `if dxvk_cpu_family == 'x86_64' → target_suffix='64' else target_suffix=''` and no aarch64 case at all.

**Windows 11 on Arm with a modified INF adding `DEV_2E12`.**
`nv_surface_woa.inf` binds only `2E03`/`2E06`/`2E13`, all SUBSYS-locked to Microsoft `0x1414`; `2E12` absent. Secure Boot is **enabled** on this box (`mokutil --sb-state`), and Windows refuses `bcdedit testsigning` under Secure Boot. The only ARM64 Windows driver is 616.00 (branch r615, July) — six weeks *before* DLSS 5 launched — and no ARM64 616.64 exists (probed: 404 on every plausible filename, while x86-64 616.64 returns 200). *Trap for anyone who tries anyway:* that package's `_nvngx.dll` declares machine `0x8664` and `file` says "x86-64", but its `.hexpthk`/`.a64xrm` sections and `wddm2_arm64ec_release` PDB path prove it is **ARM64EC** — FEX cannot execute it.

**Windows VM with GPU passthrough.**
Platform firmware mandates a 1:1 IOMMU identity mapping. Verified first-hand: GPU alone in IOMMU group 20, `type = DMA`, two `direct` reserved regions (`0xa1600000-0xb97fffff`, `0x200000000-0x302ffffff`) byte-identical to those in [NVIDIA/OpenShell#1780](https://github.com/NVIDIA/OpenShell/issues/1780) — closed unresolved as a platform limitation. `echo identity > /sys/kernel/iommu_groups/20/type` → `Operation not permitted`. No hypervisor or QEMU version changes this.

**NGX OTA updater as an acquisition channel for the model.**
The r615 `nvidia-ngx-updater`'s complete Streamline package list is `sl_common_0, sl_deepdvc_0, sl_dlss_0, sl_dlss_d_0, sl_dlss_g_0, sl_nis_0, sl_nrd_0, sl_nvperf_0, sl_pcl_0, sl_reflex_0, sl_sdk_0` — no NR entry (`sl_nrd` is the unrelated Real-Time Denoisers SDK). Its only endpoint is a deprecated `static.nvidiagrid.net` debug path. Separately, the Linux NGX core says so in as many words: *"unable to launch NGX Updater to download newer updates for generic snippets. Can only use files that have already been downloaded to the cache."*

**Streamline 2.14, or any public DLSS 5 SDK.**
Streamline tops out at v2.12.0; DLSS SDK at v310.7.0 — both published 2026-06-23, ten weeks before DLSS 5 launched. The NR runtime is 310.8.x. There is no public header, feature enum, or struct layout to implement against.

**Spoofing GPU architecture or driver version via `DXVK_NVAPI_GPU_ARCH` / `DXVK_NVAPI_DRIVER_VERSION`.**
GB10 already reports as `GB200`/`GB202` with no intervention (capability probe, not device ID). And NGX's snippet validation compares the snippet's own signed metadata against driver-side values NVAPI does not participate in — `NGXValidateSnippetMetaData` cannot be reached from NVAPI. Nothing to fix, nothing to gain.

**`__OVERRIDE_FEATURE_DENY` / `__NV_SIGNED_LOAD_CHECK=none`.**
These override *denial* of a feature the NGX core already knows about. They cannot introduce a missing feature into r580's table — and the working path never asks the core for feature 18 anyway.

**One-click DLSS 5 installers.**
`faisalkindi/DLSS5oneclick` (30 releases, each a single `.exe`, 810 KB repo), `reiluisii/1-Click-DLSS5`, `dlss5feeder/DLSS-5-Feeder-RenoDX` (description is raw SEO keyword-stuffing). These distribute prebuilt Windows binaries around a leaked, unsigned NVIDIA DLL. One confirmed harm case: `yumlevi/renodx-dlss-installer#1` — hash-mismatched DLL causing permanent `0xBAD00002`. NapXDD's own warning is that a mismatched model *reports `Success` on every evaluate and then crashes the game minutes into gameplay*. OptiScaler itself carries a standing warning about impersonating sites.

**Redistributing `nvngx_dlssnr.dll`.** It is NVIDIA proprietary, ships inside retail games, and is not redistributable. It must never become a committed artifact of this repo, and community mirrors (rhi-repo tags, Discord pins) are not a legitimate acquisition route.

**The ReShade/RenoDX *add-on* route under Wine** (as distinct from NapXDD's forwarder). [dlss5-bridge issue #22](https://github.com/NIGos/dlss5-bridge/issues/22), diagnosed at binary-offset level by the maintainer: `renodx-dlss5.addon64` deadlocks on a re-entrant MSVC `std::mutex` because vkd3d-proton calls its own methods through a C vtable carrying the add-on's queue-submission hooks. Independent of DLL version.

**The "DLSS 4.5 breaks on 610 drivers" report** (forum post 371356 #298, 2026-09-04). Its own author retracted it in the same post ("I had one hard system freeze also on DLSS 310.7.0, so it could be related to temperatures after all"), and the thread resolved to a Resizable-BAR / Xid 56 issue on unrelated GeForce hardware.

**Superseded sources that should not be cited as current:** PCWorld's 2026-06-02 "RTX Spark only supports DLSS 4.5"; NVIDIA's 2026-05-31 press release "DLSS 4.5 Ray Reconstruction" for RTX Spark. Both predate the Sept 3-4 spec page.

---

## 6. WATCH LIST — in dependency order

**Tier 1 — would change everything (check first, cheap):**

1. **`strings libnvidia-ngx.so.<ver> | grep -ci dlssnr`** on each new NVIDIA Linux aarch64 driver. This is the single decisive driver-side test. Currently **0** at 580.173.02, 610.43.02, 610.57.04 and 615.41. Anything non-zero means NVIDIA is shipping DLSS 5 through the Linux driver, and everything above needs redoing.
2. **[NVIDIA/DLSS releases](https://github.com/NVIDIA/DLSS/releases)** past `v310.7.0` — especially a 310.8+/320.x tag, or the first-ever `lib/Linux_aarch64/` directory.
3. **`cuobjdump`/raw-fatbin scan of an actual `nvngx_dlssnr.dll`** for `sm_120` vs `sm_120a`. This is the one measurable unknown that gates Path A, and it needs only a copy of the DLL. `sm_120a` with no PTX = GB10 hard-excluded.

**Tier 2 — enables the sanctioned route:**

4. **[download.nvidia.com/XFree86/Linux-aarch64/](https://download.nvidia.com/XFree86/Linux-aarch64/)** index moving past 610.57.04 — and that version's `README/supportedchips.html` still containing `2E12`. (N1X `2E03`/`2E06` alone is *not* sufficient; it's a different device.)
5. **[NVIDIA-RTX/Streamline](https://github.com/NVIDIA-RTX/Streamline/releases)** past v2.12.0.
6. **NVIDIA's [DLSS technology page](https://www.nvidia.com/en-us/geforce/technologies/dlss/) feature matrix** adding any non-GeForce-RTX-50 part to the 3D-Guided Neural Rendering row.

**Tier 3 — enables or de-risks the community route:**

7. **[NapXDD/addon-dlssnr-linux](https://github.com/NapXDD/addon-dlssnr-linux)** issues and wiki — the first ARM64/GB10/aarch64 report from anyone. Currently zero across the whole ecosystem (verified via GitHub search API: `total_count: 0` for every query).
8. **[dxvk-nvapi issue #393](https://github.com/jp7677/dxvk-nvapi/issues/393)** — the CuBIN-interop crash. Its resolution determines whether Path A is even solid on x86-64.
9. **[optiscaler/OptiScaler PR #1116](https://github.com/optiscaler/OptiScaler/pull/1116)** (DLSS 5 NR as an optional module, with a native Vulkan path in progress) and [Dagherbou/OptiScaler_DLSSNR](https://github.com/Dagherbou/OptiScaler_DLSSNR/releases).

**Tier 4 — adjacent (DLSS 4 on ARM64 Proton):**

10. **[Proton issue #9439](https://github.com/ValveSoftware/Proton/issues/9439)** and Proton `Makefile.in` gaining `$(eval $(call rules-meson,dxvk-nvapi,arm64ec,windows))`.

**Tier 5 — context:**

11. **RTX Spark October launch** — whether any Linux support is announced, and whether `2E13` ("NVIDIA Desktop Device") reaches a Linux aarch64 supported-chips table.
12. **DGX OS 8** — referenced by NVIDIA's own current docs as the validated stack for R595+, but `docs.nvidia.com/dgx/dgx-os-8-user-guide/` returns 404.

---

## 7. CONFIDENCE AND UNCERTAINTY

### Solid — first-hand, reproducible on this machine
- GB10 is PCI `10de:2e12`, compute capability **12.1 (sm_121)**, driver 580.173.02.
- `sm_120` and `sm_120f` cubins load and execute correctly; **`sm_120a` fails** with `CUDA_ERROR_NO_BINARY_FOR_GPU`. `sm_75`/`sm_86`/`sm_89` PTX JITs fine.
- FP8 e4m3 tensor-core MMA compiled sm_120-only lowers to `QMMA.16832.F32.E4M3.E4M3` and executes correctly.
- **No Linux NGX core at any version** (580.173.02, 610.43.02, 610.57.04, 615.41) contains `dlssnr`. Feature tables are `dlss`/`dlssd`/`dlssg`.
- NGX arch gate reports `0x1B0` on 610 (chip `0x5b`) and `0x7FFFFFF` on 580 — both clear any snippet minimum.
- `/usr/lib/aarch64-linux-gnu/nvidia/wine/` is **hand-made and dpkg-unowned**; NVIDIA's aarch64 driver ships no Wine NGX bridge at any branch.
- GB10 exposes `VK_NVX_binary_import` r2, `VK_NVX_image_view_handle` r3, `VK_NV_cuda_kernel_launch`, and `meshAndTaskShaderDerivatives = true`.
- FEX-2607 thunks the full NVX cubin path both directions, with `VkCuLaunchInfoNVX` repacking.
- Proton 11.0's `nvapi64.dll` exports all 12 D3D12 CUDA-interop entry points; ARM64 Proton has no `nvapi64.dll` at all.
- Secure Boot enabled; Windows UEFI CA 2023 present in the db (and present since at least the March 2026 firmware — **not** new this week, contra StorageReview's framing).
- GPU IOMMU group has firmware-mandated identity mappings; passthrough impossible.
- apt offers 590/595/610 arm64; nothing pins against them.

### Solid — NVIDIA primary sources, fetched directly
- No Linux driver above 610.57.04 exists on any architecture.
- GB10 `2E12` is in supported-chips for every branch 580→610.57.04; N1X `2E03`/`2E06` are new in 610.57.04.
- RTX Spark page says DLSS 5, Windows 11, October 2026; the DLSS 5 launch article says RTX 50 Series only. Two NVIDIA pages disagree.
- WoA 616.00 INF binds only `2E03`/`2E06`/`2E13`, Microsoft SUBSYS; DriverVer 07/13/2026, branch r615.
- Streamline v2.12.0 / DLSS SDK v310.7.0 are the public ceilings, both 2026-06-23.
- DGX OS 7 guide (updated 2026-09-05) requires R580 on Spark.

### Thin — treat with care, do not write into the log as fact
- **"Feature 18 == DLSSNR."** Community consensus across four independent projects, and NVIDIA's own `nvsdk_ngx_defs.h` does reserve slots 14-18 with `// New features go here`. But NVIDIA has never named it, and one project's docs number features differently (1=SR, 11=FG, 13=RR). High-confidence, not certain.
- **"FGX == DLSS 5."** Circumstantial: FGX is the only new NGX feature in r610/r615 vs r580, and its telemetry parameters are `ProjectiveRendering`, `GBufferWidth`, `GBufferHeight` — a good match for 3D-Guided Neural Rendering, and definitively *not* frame generation (DLSSG is separately enumerated with its own MultiFrameCount/FlipMetering block). But no `neural`/`3D-guided`/`DLSS 5` string ties them. **Note FGX is not a useful tripwire: it is already present in 610.43.02, the driver this box can install today.**
- **"N1X is the same die as GB10."** Huang's on-record quote is about *N1*, not N1X, and does not say the dies are identical. ServeTheHome hedges explicitly. N1X's driver binds an ACPI NPU/DLA that this GB10 does not have.
- **The Linux DLSS 5 working reports.** Two reporters, two days old, RTX 50 and RTX 40 only. Detailed and log-backed, but not independently reproduced by anyone in this analysis.
- **The 590+ "bricking."** No primary source found in either direction.
- **Whether the 610.43.02 upgrade pulls DKMS.** Two analysis passes reached opposite conclusions from `apt-get -s`. Re-run it and read the output before committing.

### Nobody could establish
- **Whether `nvngx_dlssnr.dll` ships `sm_120` or `sm_120a` cubins.** No copy exists on this machine (`find / -xdev -iname '*dlssnr*'` returns only source repos). This is *the* decidable unknown, and it is one `cuobjdump`-equivalent away once a DLSS 5 game is installed.
- **Whether the ReShade + Detours + 165 MB CUDA-bearing PE stack survives FEX's JIT.** Zero prior art. GitHub searches for GB10/Spark/arm64/aarch64 across the entire DLSS 5 ecosystem return `total_count: 0`.
- **Whether NVIDIA has any Linux DLSS 5 plan.** The one on-point forum thread has sat unanswered for six months. An NVIDIA moderator confirmed on 2026-08-06 that DLSS 5 internals are undisclosed.
- **N1X's CUDA compute capability.** The CUDA 13.4 developer-preview release notes (the release adding Windows-on-Arm support) could not be retrieved; docs.nvidia.com served 13.3 U1 instead. If N1X is also sm_121, DLSS 5 kernels for this exact compute capability already exist in NVIDIA's builds.
- **The exact date NVIDIA's RTX Spark page changed to DLSS 5.** Internet Archive was offline. Bracketed to 2026-06-11 → 2026-09-05.

### Method caveat — read this before trusting the negative searches
**Every research angle exhausted the session's 200-call WebSearch budget**, most of them before issuing a single query. All findings above come from direct `curl`/WebFetch against primary URLs, the GitHub API via `gh`, the Snap Store and Discourse JSON APIs, NVIDIA's OSTree repo, and first-hand binary/system inspection — which is *better* evidence than search would have given, but it means no open-ended discovery was possible. **Reddit was unreachable throughout** (crawler blocked). If the user's "posts from today" were on Reddit, they were never checked. That is the single largest gap.

Several strong secondary sources refused fetches: videocardz (HTTP 402), Tom's Hardware / TechPowerUp / wccftech / guru3d / Phoronix (403). Where a claim rests only on those, it is labelled as journalism-relayed rather than verified.

---

## Bottom line for the log

DLSS 5 does not run on this machine and will not without either NVIDIA shipping it in a Linux aarch64 driver (no sign of this) or a first-ever ARM64 port of an unsanctioned community stack around a game-shipped proprietary DLL (never attempted, ~25% likely to composite a frame, ~0% likely to be playable).

The valuable output of this investigation is not the DLSS 5 answer — it is that **three of the four blockers this repo has been reasoning from are wrong**, that **GB10 is not pinned to driver 580**, and that **the reason Proton 11 ARM64 has no DLSS is a missing `nvapi64.dll` blocked by a one-line gap in upstream build files, on hardware Valve's own contributor says he lacks and this machine has.** That last one is a real, small, achievable contribution, and it is worth more than chasing DLSS 5.