# What of this repo transfers to the RTX Spark (Surface Laptop Ultra, 128 GB)

> Provenance: desk research, 2026-11-12, before the hardware arrived. Sources are listed at the end.
> **Nothing in this file has been measured on an RTX Spark.** It is a test plan with predictions,
> written so that each prediction can be shown wrong on day one.

## 1. The machine, as far as sources agree

| | DGX Spark (this rig) | Surface Laptop Ultra 128 GB |
|---|---|---|
| SoC | GB10 (`10de:2E12`) | RTX Spark N1X. Repo's earlier INF read: `2E03` = 6144-core, SUBSYS `1414` (Microsoft) |
| CPU | 20 cores, 10+10 | 20 cores, **10 performance + 10 efficiency, no SMT** (StorageReview) |
| GPU | 6144 Blackwell cores | 6144 per most sources. **STH's spec list says 5120.** Settle with Device Manager → Hardware IDs (`2E03` vs `2E06`) |
| Memory | 128 GB, ~273 GB/s | 128 GB LPDDR5X-9400, 256-bit, ~300 GB/s theoretical; STREAM Triad measured ~122 GB/s |
| GPU memory | unified | **Split system/GPU: 64/64 as shipped, adjustable up to 96 GB in the NVIDIA app.** This is a new variable to record |
| Power | fixed desktop envelope | 45–80 W shared CPU+GPU; Windows power mode matters |
| OS | DGX OS, Linux | Windows 11 Pro **26H1 (Arm64)**, driver 32.0.16.1742 as reviewed |
| x86 translation | FEX / Box64, under Wine/Proton | **Microsoft Prism**, user-mode only, no Wine/Proton/DXVK/VKD3D |

**Same die?** Still not settled by NVIDIA. STH says both "consumer branding for GB10" and "N1X sibling to the GB10" in the same review. A different PCI ID and memory speed mean it is at least not the same SKU. `docs/SPARK-PLATFORM.md` stays as written until NVIDIA says otherwise.

**A known hazard for long test runs:** StorageReview had **hard power cuts under sustained all-core load** (Kernel-Power 41, bugcheck 0, no dump, no thermal event), on two units, not explained by Microsoft or NVIDIA at publication. If a long benchmark "crashes", check Event Viewer for Kernel-Power 41 before blaming the game.

## 2. What Prism is documented to do, and why it bears directly on our x87 work

From Microsoft Learn (*Adjust emulation settings on Arm*) and NVIDIA's *RTX Spark Porting Guide*:

- **x87 is approximated in 64-bit by default.** Microsoft: the per-app setting *Disable floating point optimization* makes "Prism use the full 80-bit precision instead of a 64-bit approximation."
- **NVIDIA goes further:** "Avoid x87 floating point instructions" because under emulation they may lack "full 80-bit precision, bit-accurate results, **or correct status flags**." Correct status flags are exactly what id Tech 4's `Sys_FPU_StackIsEmpty()` depends on, since it reads only the tag word.
- **32-bit apps see a smaller CPU.** AVX/AVX2/BMI/FMA/F16C are hidden from 32-bit x86 by default ("Show newer emulated CPU features" opts in), and "XSAVE and OSXSAVE feature bits are not available in 32-bit emulation." CPUID answers differ between 32- and 64-bit mode.
- **Per-app knobs exist:** Default/Safe/Strict/Very strict presets; memory-ordering strictness (Fast → Force single-core); strict self-modifying-code support; RWX-page optimisation off; CHPE hybrid binaries off (x86 only); app cache off.
- **Kernel-mode code is never emulated.** That is why kernel anti-cheat needs an ARM64 driver from its vendor.
- **Graphics:** NVIDIA ships native ARM64 and ARM64EC Vulkan loaders plus an ARM64X forwarder, and its ICDs "support the same features as the x86_64 ones". Windows' own ARM64X OpenGL loader serves both native and emulated processes. The porting guide **does not say whether 32-bit x86 OpenGL gets the NVIDIA ICD** or falls back to Microsoft's GL-on-D3D12 compatibility pack. That is the open question our WGL probes answer.

So Prism's per-app settings do on Windows what running FEX and Box64 side by side did here: they give a **second implementation to compare against**. That makes the x87 suite more useful there than it is here, not less.

## 3. What transfers

### 3a. Runs on day one, or after a small port: the probes (highest value)

| Repo asset | State for Windows | What it would settle |
|---|---|---|
| `tools/isa-probe/*.S` (x87tags, x87top, a3store, cpuid) | **Does NOT run as-is.** Each is a Linux ELF that ends in two `int $0x80` syscalls (write, exit), so `OPEN-QUESTIONS.md`'s "run it under Prism, no install" was wrong as written. **Ported the same day (section 6):** those two syscalls become calls into `tools/isa-probe/win/pe-stub32.S`; the probe bodies and `.expect` files are unchanged | Does Prism get the tag word, FINCSTP/FDECSTP rotation, the `a3` store and the CPUID DE/PSE bits right? Run each probe at **Default** and with **Disable floating point optimization** set. A tag-word failure that disappears with the setting would explain id Tech 4 under Prism before any game is installed |
| `tools/fex-tests/x87-*.S` | Same port as the row above | Same |
| `tools/fex-tests/x87-wine-context32.c` | 32-bit PE, runs natively | x87 state across exceptions and VEH under **real** WOW64. FEX zeroes it on `EXCEPTION_CONTINUE_EXECUTION` (CW=0x0000), so this is the first non-Wine control for that finding |
| `tools/probes/wgl/wgl-pixelformat32.c`, `wgl-formatsweep32.c` | 32-bit PE, runs natively | **Does 32-bit OpenGL get pixel formats on N1X, and from which ICD?** Here it is 0/320 under FEX and 320/320 under Box64. This is the id Tech 4 precondition and it takes seconds to answer |
| `tools/probes/cpuid/cpuidprobe.c` | Portable C, build as both i686 and x86-64 PE | Shows the 32-vs-64-bit CPUID difference that NVIDIA documents, with numbers |
| `tools/probes/namedobj/namedobj32.c` | 32-bit PE | Control only: it should be clean, like FEX. If it is not, our Box64 write-up is wrong about where the fault lives |
| `tools/fex-inject-tests.sh` sources (`hook*.c`, `load-reshade.c`, `load-forwarder.c`) | PEs, native | **Genuinely open:** can x64 code inline-patch **ARM64X** system DLLs (`d3d11`, `dxgi`, …) under Prism? NVIDIA says "do not patch operating-system libraries" or assume a specific x86 instruction sequence. That is what ReShade and OptiScaler do. The answer decides whether the injection chain exists on Windows at all |
| `tools/probes/dinput/mousefeel32.c` | PE, but its control is `xinput test-xi2`, an X-server tool | The control has to be replaced, for example by a Raw Input (`WM_INPUT`) listener. The method transfers; the script does not |
| `tools/probes/launcher-shim/`, `tools/make-launcher-shim.sh` | Portable PE | Useful only if a launcher fails there too |

### 3b. RTX Spark as the reference for the DGX findings

The repo's rule 2 says that when two implementations fail identically, suspect the test. The laptop adds a **third implementation, and it is the one NVIDIA supports**. Each open DGX failure becomes a falsifiable prediction:

| Title / finding on DGX Spark | Prediction for RTX Spark | Third-party evidence so far |
|---|---|---|
| Red Dead Redemption 2, `FLT_INVALID_OPERATION` on world load | Works, so the DGX failure is on the translator or Wine side | XDA: "launcher clean", runs |
| Elden Ring (undiagnosed here) | Works, so the cause is not the GPU or driver family | XDA: runs, including online with EAC |
| Ubisoft Connect launcher crash | Works | XDA ran Far Cry 3 from a Ubisoft library; needed .NET 3.5 |
| Cyberpunk 2077 | Works; a performance reference | XDA: ~35 fps gameplay, RT Low, 2880x1800, DLSS, no frame generation |
| Black Myth: Wukong, Wave64 | **Likely works**, because the rejection is VKD3D's, and native D3D12 on NVIDIA Windows drivers is the path the game ships for | none |
| id Tech 4 (Quake 4, Prey 2006, DOOM 3) | **Unknown, and the most interesting test.** Section 2 suggests Prism's x87 status flags may break `Sys_FPU_StackIsEmpty` independently of FEX's GL failure | no report found |
| RTX Remix dual-process IPC (HL2 RTX) | Real WOW64 32↔64 shared memory, so plausibly works | none |
| DLSS 5 NR | **Supported natively** (it is on NVIDIA's RTX Spark spec table), which gives a ground-truth reference for what NR output and NGX call sequences look like. `tools/fex-tests/ngx-*.c` and the NBA 2K27 NR binaries preserved in `aa8b8f8` can be compared against a run where NR really works | spec table only |
| No Man's Sky, Halo Infinite | Same reasoning as Elden Ring | none |

**Phrasing rule, so this file does not become the next `descriptor_buffer`:** a title working on RTX Spark proves the DGX failure is *not intrinsic to the title on this GPU family*. It does **not** prove which DGX layer is at fault. That still needs the DGX-side bisection.

### 3c. Method and tooling that ports as-is or nearly

- **Runs unchanged:** `tools/appinfo.py` (Steam's `appinfo.vdf` is the same file on Windows, pure Python); `tools/pick-runtime.py` (PE import and string scan, which tells you which titles are 32-bit OpenGL and therefore need the Prism 32-bit settings); the `log-result` skill; `commit-claim-guard.sh` (git hooks run under Git for Windows' bash).
- **Same idea, new mechanism:**
  - `game-run.sh`: a Job Object gives the cgroup-scope teardown.
  - `bench-ab.sh`: use **PresentMon 2.x**, which an RTX Spark owner has already used (AoE IV forum). Whether a native ARM64 build exists is unverified.
  - `watch-run.sh`: per-process CPU delta from performance counters.
  - `config-snapshot.sh`: plain file copies, the easiest to port.
  - `ab-runtime.sh` / `run-both.sh` become **"Prism Default vs Prism Strict / 80-bit x87"**. That is the natural Windows analogue of running both JITs.
- **Platform detection:** `Win32_ComputerSystem.SystemFamily` instead of DMI `product_family`. Record the PCI device ID, the GPU memory split, the power mode and AC/battery with every performance result. These are all constants on DGX Spark and all variables here.

## 4. What does not transfer

FEX, Box64, Proton, DXVK, VKD3D-Proton, pressure-vessel, `binfmt_misc`, the RootFS (`sync-rootfs-nvidia.sh`), `fex-build.sh`, `build-box64-symfix.sh`, `box64-swap.sh`, `setup-mangohud-x86.sh`, `safe-proc.sh`, `wine-mouse-knobs.sh`, `wine-dll-loadtest.sh` (its MSVCP140 finding is a Wine-builtin bug), `capture-hang.sh`, the Proton-log signature lists in `run-report.sh` / `signature-check.sh`, and **every translator bug in `notes/upstream/`**. Those are facts about software that does not run on the laptop. The guard hooks are Linux-specific in what they match: `pgrep -f`, `steam -applaunch`.

## 5. Suggested day-one order (no game installs)

1. Device Manager hardware ID, NVIDIA app GPU memory split, `winver`, driver version. Record them in `docs/SPARK-PLATFORM.md`'s RTX Spark row, replacing the third-party figures.
2. Ported `isa-probe` suite: i686 at Default, then with **Disable floating point optimization**, then with **Show newer emulated CPU features**. Same suite built x86-64 where applicable.
3. `wgl-pixelformat32` / `wgl-formatsweep32`: count the formats and name the ICD that served them.
4. `x87-wine-context32`, `namedobj32`, `cpuidprobe` (32 and 64 bit).
5. Inline-hook tests against `d3d11.dll`/`dxgi.dll`, before any ReShade or OptiScaler attempt.
6. Only then games: Quake 4 first (it prints its whole x87 environment before dying), then RDR2 and Elden Ring as controls for the DGX diagnoses.

## 6. Done the same day: the kit, and two things it turned up here

**`tools/build-rtx-spark-kit.sh`** builds everything in 3a except `mousefeel32` (its control is an
X-server tool) into `~/dgx-gaming-work/rtx-spark-kit/` (+ `.zip`), with `README-KIT.txt` giving the
day-one order and `Check-IsaProbe.ps1` grading the isa-probes on Windows.

- **The port is verified, but only against FEX.** `SMOKE=1` runs the four PE32 isa-probes under
  Proton 11.0 Wine, FEX-hosted: every tag matched the SDM, and matched the ELF build tag for tag.
  The Box64-hosted arm could not run from the agent shell ("Could not open
  '/lib64/ld-linux-x86-64.so.2'", outside pressure-vessel), so it was removed rather than left
  printing an empty column.
- **`Check-IsaProbe.ps1` has never run.** There is no PowerShell on this box. It uses only Windows
  PowerShell 5.1 built-ins, but its first run on the laptop is also its test.
- **Found on the way: `isa-probe.sh` had been silently blind to FEX.** fex-emu **2611.1** (installed
  now) ships only `/usr/bin/FEX`; the `FEXInterpreter` alias is gone. The runner defaulted to the old
  name, so every probe reported FEX as "missing" with no error, and the suite still exited as if it
  had graded something. The same name was hardcoded in `run-both.sh` and
  `probes/cpuid/cpuid-probe.sh`. All three now resolve whichever name exists.
- **With that fixed, packaged FEX 2611.1 passes `a3store.32` and `cpuid.32`.** Both were FEX
  failures when they were written (2607/2608). This is one run on one build, and the `.data` rule
  for probes stays in force. It does mean the CLAUDE.md wording "FEX reports DE/PSE=0" and the `a3`
  signature are **unconfirmed on the installed FEX** until someone re-checks them deliberately. Box64
  in `/usr/local/bin` still fails `x87top.32` (INC1 `0xfffc`, DEC1 `0xcfff`, IN7 `0x000c`), as recorded.

## Sources

- Microsoft Learn: [Adjust emulation settings on Arm](https://learn.microsoft.com/windows/arm/apps-on-arm-program-compat-troubleshooter), [How emulation works on Arm](https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation)
- NVIDIA RTX Spark Porting Guide 0.1.0: [Windows on ARM](https://docs.nvidia.com/rtx-spark/rtx-spark-porting-guide/0.1.0/portingandemulation/windowsarmosn1x.html), [Emulation tips](https://docs.nvidia.com/rtx-spark/rtx-spark-porting-guide/0.1.0/portingandemulation/emulationtips.html), [Vulkan and OpenGL](https://docs.nvidia.com/rtx-spark/rtx-spark-porting-guide/0.1.0/porting/vk-gl.html)
- [Microsoft tech specs: Surface Laptop Ultra](https://learn.microsoft.com/en-us/surface/tech-specs/surface-laptop-ultra-1stedition)
- [StorageReview: Surface Laptop Ultra for Business review](https://www.storagereview.com/review/microsoft-surface-laptop-ultra-for-business-review-rtx-spark-n1x), the source for the 10+10 split, bandwidth, memory split, 26H1, driver and power-off
- [ServeTheHome: Surface Laptop Ultra 128GB review](https://www.servethehome.com/microsoft-surface-laptop-ultra-review-rtx-spark-n1x/)
- [XDA: a game from every year since 2006 on RTX Spark](https://www.xda-developers.com/tested-two-decades-of-windows-gaming-history-on-arm-rtx-spark-nvidia/), [XDA: anti-cheat tests](https://www.xda-developers.com/nvidia-rtx-spark-passed-most-anti-cheat-tests-valorant-and-call-of-duty-still-wont-run/)
- [Age of Empires forum: PresentMon on RTX Spark](https://forums.ageofempires.com/t/rtx-spark-big-problemo/290753) (one user's report)
