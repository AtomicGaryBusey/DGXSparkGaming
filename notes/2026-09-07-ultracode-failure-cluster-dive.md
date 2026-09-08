# Deep research into each DGX Spark failure cluster: existing fixes, or concrete paths to modify the blocking component

> **Machine-generated report from a multi-agent workflow run.** Persisted from
> scratch storage so it can be read, cited and *checked* later. Treat every claim
> in it as untrusted until verified locally — this project has published agent
> findings that were wrong, and the synthesis itself flags which of its own claims
> survived adversarial verification and which were refuted.

| | |
|---|---|
| Run date | 2026-09-07 |
| Agents | 16 |
| Tokens | 1,463,545 |
| Tool calls | 581 |
| verified | 10 |
| survived | 6 |
| refuted | 4 |

---
# Cross-cluster synthesis — 2026-09-07

**Premise correction up front.** The brief says "the single unthunked Vulkan function blocks three AAA titles." That premise is dead. `vkGetPhysicalDeviceDescriptorSizeEXT` belongs to **`VK_EXT_descriptor_heap`**, which driver 580.173.02 does not expose at all, so no game calls it. It appears 16 times in `/home/aharmon/steam-1091500.log` — Cyberpunk 2077, a game that **works** here — because the Vulkan loader probes every name it knows and `nullptr` is the correct answer. Every command of every extension this driver *does* expose is thunked in FEX 2607, `VK_EXT_descriptor_buffer` included. No Man's Sky, Halo Infinite and Elden Ring therefore have **no diagnosis at all** right now. Breadth is weighted below against that, not against the old premise.

---

## 1. Ranked table (all clusters)

Score = (games unblocked × P(unblock)) / effort, with a separate column for diagnostic yield, because three of the top rows buy knowledge rather than a working game and pretending otherwise is how this log got burned.

| # | Cluster | What would change | Games | P(unblock) | P(useful diagnostic) | Effort | First concrete experiment |
|---|---|---|---|---|---|---|---|
| 1 | vulkan-ext | Strike the `vkGetPhysicalDeviceDescriptorSizeEXT` / `VK_EXT_descriptor_buffer` failure signature from `CLAUDE.md:216` and `README.md:1876, 2039, 2041, 2042, 2058`; mark NMS / Halo Infinite / Elden Ring **undiagnosed** | 0 | — | 1.00 | 15 min, no launch | `grep -h 'Unknown Vulkan function' /home/aharmon/steam-*.log \| sed 's/.*: //' \| sort \| uniq -c` — the working game emits the same set |
| 2 | vulkan-ext | Get a **real** error out of the three DX12/Vulkan crashers with vkd3d-proton's own documented debug recipe | 3 | ~0.15 | 0.80 | 1 launch/title (~10 min each), no build | `VKD3D_CONFIG=vk_debug VKD3D_DEBUG=warn VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` + `PROTON_LOG=1 %command%` in Steam launch options, then `tools/game-run.sh 275850` |
| 3 | launchers | NBA 2K27's publisher-supplied EAC-free entry (`config/launch` `"3"` = `NBA2K27.exe`, `type option1`, *"NBA 2K27 without EAC (offline only)"*) — never tried; 107 GB already on disk | 1 | ~0.15 | 1.00 (moves README:2043 from "EAC fails" to a named stage either way) | 1 launch + a 1-line `game-run.sh` patch | add `LAUNCH_OPTION` passthrough to `/home/aharmon/DGXSparkGaming/tools/game-run.sh`, then `LAUNCH_OPTION=option1 tools/game-run.sh 4356430` |
| 4 | not-arm | Delete the two false clauses in `README.md:2038` (Wukong "no Wave32 fallback", "would fail on any NVIDIA GPU") + matching `CLAUDE.md:248`; mark permutation-selection as `TODO:` | 0 | — | 1.00 | 15 min | none needed — evidence is `ValveSoftware/Proton#8004` (RTX 5080 / Blackwell / 590.48.01 plays it) and the local `FFX_PREFER_WAVE64="[WaveSize(64)]"` in the FidelityFX checkout |
| 5 | cpu-semantics | Build FEX-2607 + cherry-pick `9365e6240b3b87466753cd989d257e5c93092578` into `~/dgx-gaming-work/fex-prefix`, unblocking Burnout Paradise's fake-SSE2 dialog (it reads leaf1.EDX **bit 2, DE**, which 2607/2608 hardcode to 0) | 1 | ~0.5 | 1.00 (README:2048 is false today regardless) | 2–4 h build + 4 GB reinstall | Stage 0 first, costs seconds: `FEXBash -c 'grep -m1 ^flags /proc/cpuinfo' \| tr ' ' '\n' \| grep -cx -e de -e pse` → prints 0 here, must print 2 after |
| 6 | ipc-multiprocess | Per-app FEX profile `{"Config":{"DynamicL1CacheDecreaseCountHeuristic":"0"}}` for `steamwebhelper.json` / `client.json` (upstream PR #5856, merged 2026-08-26, absent from 2608; knob present in installed 2607) | 0 games; Steam-UI stability only | — | low | trivial | Prove the symptom exists first: `grep -c BadDamage`, `grep -c 'GPU process exited'`, `grep -ci fatal` on `~/.steam/steam/logs/cef_log.txt` — all **0** today, so do nothing |

Rows 1 and 4 outrank rows 2–5 despite unblocking zero games: they are the only items with P = 1.0, they cost minutes, and leaving them in place actively misdirects rows 2 and 5. Row 6 is last because the rig shows none of the symptom.

---

## 2. The three cheapest experiments

All three read a diagnostic that already exists or already ships. None builds anything.

### E1 — Does the "unknown Vulkan function" census distinguish a working game from a broken one? (0 launches, ~1 min)

```bash
comm -13 \
  <(grep 'Unknown Vulkan function' /home/aharmon/steam-1091500.log | sed 's/.*: //' | sort -u) \
  <(grep 'Unknown Vulkan function' /home/aharmon/steam-242980.log  | sed 's/.*: //' | sort -u)
# and the volume claim, which is separately falsifiable:
awk '{n++} /Linking address/{f++} END{printf "%d/%d = %.1f%% FEX\n", f, n, 100*f/n}' \
  /home/aharmon/steam-1091500.log
```

Mechanism, verified in source: FEX `ThunkLibs/libvulkan/Guest.cpp` `MakeGuestCallable()` does an unguarded `fprintf(stderr, "%s: Unknown Vulkan function at address %p: %s\n", ...)` on a table miss and `"Linking address %p to host invoker %#zx\n"` on a hit — no env var, no log level, no build. `constexpr bool stub_unknown_functions = false;` means a miss returns `nullptr`, byte-identical to an unsupported extension.

**Kills the idea if:** the two sets differ. That would mean the census *does* carry per-title signal and the "it's just loader probing" reading is wrong. (Measured so far: Cyberpunk 80 unknowns / 2945 links and still runs; the `Linking address` share is 2945/42618 = **6.9%**, so the "3.5 MB log is FEX spam" story is already dead — it is Wine's `+unwind`/`+loaddll` tracing from `PROTON_LOG=1`'s default channels.)

### E2 — Confirm the Burnout CPUID gap on this exact build (0 launches, ~5 s)

```bash
FEXBash -c 'grep -m1 ^flags /proc/cpuinfo' | tr ' ' '\n' | grep -cx -e de -e pse   # expect 0
/usr/bin/FEXInterpreter /home/aharmon/dgx-gaming-work/cpuid/cpuid.elf | awk '$1=="00000001"{print $5}'   # expect 278bfbf3
```

Valid proxy, checked against the **installed tag**, not main: `Source/Tools/LinuxEmulation/LinuxSyscalls/EmulatedFiles/EmulatedFiles.cpp` at FEX-2607 emits `de`/`pse` straight from `RunCPUIDFunction(1,0).edx` bits 2/3, and `sse2` from bit 26.

**Kills the idea if:** `sse2` is *absent* from the flags list, or leaf 1 EDX ≠ `278bfbf3`. Either would mean FEX is not advertising SSE2 after all and `README.md:2048` is right as written. (It is not: `sse2` is present, `de`/`pse` are not — the exact pre-#5807 state, and enough to fix README:2048 today with no build.)

### E3 — Make No Man's Sky say what actually kills it (1 launch, ~10 min)

Set NMS (appid 275850) Steam launch options to `PROTON_LOG=1 %command%` — `game-run.sh:114` uses `steam -applaunch`, an IPC handoff, so exporting `PROTON_LOG` in the calling shell never reaches the game. Also set `VKD3D_CONFIG=vk_debug VKD3D_DEBUG=warn VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` (vkd3d-proton's own hint string, literal in `d3d12core.dll`). Then:

```bash
tools/game-run.sh 275850
grep -iE 'VK_ERROR_EXTENSION_NOT_PRESENT|vkCreateDevice|vkCreateInstance|VUID-|validation' ~/steam-275850.log | head -50
comm -13 <(grep 'Unknown Vulkan function' ~/steam-1091500.log | sed 's/.*: //' | sort -u) \
         <(grep 'Unknown Vulkan function' ~/steam-275850.log  | sed 's/.*: //' | sort -u)
```

**Kills the idea if:** the log contains no validation error, no `VK_ERROR_*`, and no new unknown function — i.e. the crash is not Vulkan-visible at all and the whole vulkan-ext cluster is the wrong place to look for these three titles. That outcome is itself publishable and redirects to CPU-side translation.

---

## 3. Dead ends — do not re-tread

| Dead end | Why |
|---|---|
| **Writing a FEX thunk for `VK_EXT_descriptor_heap`** | Not one line. FEX pins `External/Vulkan-Headers` at `450bd2232225d6c7728a4108055ac2e37cef6475` = `VK_HEADER_VERSION 337`, which has **zero** occurrences of the extension (it landed between Vulkan-Headers v1.4.335 and v1.4.340). Both `ThunkLibs/GuestLibs/CMakeLists.txt:208` and `HostLibs/CMakeLists.txt:151` hard-code that include path, so `fex_gen_config<vkGetPhysicalDeviceDescriptorSizeEXT>` is an undeclared-identifier compile error. A submodule bump forces regeneration across ~1,800 header-shape-dependent `custom_repack` specializations. And the driver does not expose the extension, so nothing would call it. |
| **Proton EasyAntiCheat Runtime, appid 1826330, for NBA 2K27** | Wrong EAC. 2K27 ships `EasyAntiCheat_EOS_Setup.exe` + `eac_installscript.vdf` (EOS, id `f864537fcb7d4ae692ec5b7a286bc32f`). Wine's loadorder hack matches only `easyanticheatW`, `easyanticheat_x86W`, `easyanticheat_x64W`, `eac_launcherW`; `strings` on all three game binaries returns **zero** hits for any of them, so `PROTON_EAC_RUNTIME` and `LO_NATIVE`/`LO_BUILTIN` are not live variables here. The game's own `pfx/.../EasyAntiCheat/f864.../anticheatlauncher.log` already shows EOS detecting `System name: 'linux64'`, pulling its 9,622,837-byte Linux module (HTTP 200), starting *"Wine module mapping, Wine version: 11.0"* and dying 32 s later with `210, 'Unexpected error. (#1)'` — a path that never consults 1826330. Also: that `.so` is x86-64, so it runs under FEX anyway. |
| **`Multiblock=0` for steamwebhelper (FEX #5336)** | The register forensics (12–14 overflows/75 s, `r12=0xaaaa…`) were **retracted by their own author** — a macOS/ARM64EC Wine window-metrics bug, not FEX. The thread moved off multiblock on 2026-08-26; reproduces with it on *or* off; root-caused in merged PR #5856 (L1 index mask growth vs `InvalidateCache`). The very Spark reporter cited now ships `DynamicL1CacheDecreaseCountHeuristic:"0"` **instead**. And the rig shows no symptom: 0 `BadDamage`, 0 `GPU process exited`, 0 FATAL/SIGSEGV in `cef_log.txt`. |
| **`--no-zygote` / the CEF zygote FATAL as a vfork bug** | The FATAL at `cef_log.txt:5` is real (`PCHECK(ReceiveFixedMessage(...))`, `zygote_host_impl_linux.cc:201`, Chrome 126.0.6478.183) but fired **once** across 20 steamwebhelper launches spanning 2026-06-18 → 2026-09-07, and Steam relaunched cleanly 5 s later. The vfork attribution comes from FEX #5453 comment 3 by the *reporter*, which maintainer Sonicadvance1 closed five minutes later with *"I ain't reading an AI's bug report thread."* Its own theory puts Chromium 146 as the trigger and ~120 as fine — 126 is on the working side. Errno differs too (ENOENT here vs EINTR/EINVAL upstream). Steam already passes `--no-sandbox --no-zygote-sandbox`. |
| **`grep -c 'launching child process'` as a webhelper-crash metric** | 1418 hits here (1145 renderer, 209 utility, 40 zygote, 24 gpu-process) — routine CEF churn. This is the generic-counter error verbatim. |
| **The Steam forum thread as documentation for `steam://launch/<appid>/option1`** | Thread 2595630410178179844 says the *opposite*: the OP states there is no documented way to select a launch option and it "will always opt for the default"; the only attested form is `steam://launch/<appid>/dialog`, a chooser needing a human click. Treat `option1` as unverified with `/dialog` as fallback. |
| **Guest `vulkaninfo` under FEX as thunk-gap evidence** | `FEX_SILENTLOG=0 FEXInterpreter ~/.fex-emu/RootFS/Ubuntu_24_04/usr/bin/vulkaninfo` SIGILLs (exit 132) at "Opening host-side X11 display" with 0 bytes of stdout, with and without `DISPLAY`/`WAYLAND_DISPLAY`. It never enumerates a device. Its name census is loader-version-dependent anyway (RootFS loader probes AMDX/CUDA names; the Steam-runtime loader probes descriptor_heap). Cite the game logs. |
| **Binary-patching `/usr/bin/FEXInterpreter`'s CPUID constant** | `0x278BFBF3` appears neither as a literal nor as the expected `MOVZ Wd,#0xfbf3` / `MOVK Wd,#0x278b,lsl 16` pair — the compiler materialised it otherwise. No reliable patch site. |
| **Building FEX with g++** | `CMakeLists.txt:72-73` — `if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU") message(FATAL_ERROR "FEX doesn't support GCC! Use Clang instead.")`. Use the existing `/home/aharmon/dgx-gaming-work/addon-build/clang20/root/usr/bin/clang++-20`. Also pass `-DENABLE_LTO=False` (defaults TRUE; clang-20 + system GNU ld without an LLVMgold plugin fails at link) and `-DBUILD_TESTING=False` (not `-DBUILD_TESTS`). Don't `git clone` — `/home/aharmon/dgx-gaming-work/fexsrc` exists (main @ `310c250`), submodules **not** initialised. |
| **Waiting for the PPA to deliver the CPUID fix** | `fex-emu-armv8.4` candidate is still `2607-1~n`; `fex-emu-wine` is `2608~1-3~n`; FEX-2608 is the newest tag and `gh api compare 9365e62...FEX-2608` → `status=behind, ahead_by=0, behind_by=3`. Upstream skipped 2602 and 2606, so "monthly, 2609 is overdue" is unsupported. Source build is the only route. |
| **ProtonDB tier as evidence about NVIDIA** | Deck/AMD-skewed. The Wukong falsification that matters is `ValveSoftware/Proton#8004` comments: RTX 4090 / 555.58.02 at ~80 FPS, and RTX 5080 (**Blackwell**, same 32/32 subgroup range as GB10) / 590.48.01 reaching the Fuban boss. |
| **Hand-firing `steam://launch/...` for NBA 2K27** | `guard-bash.sh` only matches `-applaunch`, so this slips the hook: no cgroup scope, no atomic teardown, no telemetry — the exact shape of the 501%-CPU orphaned Wine tree the tooling exists to prevent, on an 884 MB protector-wrapped process. Patch `game-run.sh` instead. |
| **Symlinking a locally built guest thunk over the RootFS `libvulkan.so.1`** | This install uses ThunksDB: `~/.fex-emu/Config.json` sets `ThunkGuestLibs`/`ThunkHostLibs` to the distro `/usr` paths and `ThunksDB:{"Vulkan":1}`, and `/usr/share/fex-emu/ThunksDB.json` already overlays `libvulkan-guest.so` onto `@PREFIX_LIB@/libvulkan.so.1` *and* Steam's `pinned_libs_64` copy. Use `FEX_THUNKGUESTLIBS=$BUILD/Guest FEX_THUNKHOSTLIBS=$BUILD/Host` (both strings present in the installed interpreter). |

---

## 4. Genuinely unknown

- **Why No Man's Sky, Halo Infinite and Elden Ring crash.** Zero diagnosis as of now. The recorded cause is provably not it. Do not substitute a new guess.
- **Whether Burnout Paradise launches with DE/PSE set.** Nobody upstream retested after #5807 merged. Sonicadvance1 wrote *"Doesn't add anything new for the FEX side"*; the compat wiki still says Unplayable / *"obfuscated binary breaking FEX somehow"*. The DE-bit root cause is a credible maintainer assertion, not a demonstrated fix.
- **Why a wave64 permutation was selected for Wukong on this rig.** FidelityFX builds wave32 *and* wave64 permutations of the same passes (`-DFFX_PREFER_WAVE64="[WaveSize(64)]"`), so wave64 is preferred, not required. The original run log no longer exists — no `appmanifest_2358720.acf`, no `compatdata/2358720`, and no file on the box contains "Required WaveSize". Re-test costs a 125.46 GB reinstall.
- **What `210, 'Unexpected error. (#1)'` means inside EOS's Wine module mapping.** The stage is now named; the mechanism is not.
- **Whether the correct entry-point set is enough.** The audit proves no missing *symbols*. It says nothing about `pNext`-chain repacking, callback trampolines, or host-pointer semantics — the plausible remaining Vulkan-layer failure modes.
- **32-bit x86 Vulkan is entirely unthunked.** `/usr/share/fex-emu/GuestThunks_32/` ships libGL, libEGL, libcuda, libwayland-client and VDSO guest thunks but **no `libvulkan-guest.so`**. Probably moot under Proton WoW64 (64-bit unix side) — unverified.
- **Two driver extensions unaudited:** `VK_NV_disk_cache_utils`, `VK_NV_internal_nvpresent` — absent from `vk.xml`, so the cross-product cannot see them.
- **Whether a locally built FEX is as stable as the PPA build in a real game.** The 3-bit CPUID change cannot regress anything; the build as a whole is untested. A `FEXServer` is live (pid 2453289) and `Config.json` pins thunk paths to `/usr` — kill the server and put the prefix first on PATH so `FEXBash`/`FEXServer`/`FEXInterpreter` are one build. Do not install thunks over `/usr`.
- **The single CEF zygote FATAL.** Self-recovered, one occurrence in 20 launches, mechanism unknown.
- **Whether `steam://launch/<appid>/option1` selects a launch entry at all**, versus needing `/dialog` + a click.

---

## 5. Where the next full day goes

**vulkan-ext — but spent on demolition and re-diagnosis, not on writing a thunk.** It is the only cluster whose payoff is three AAA titles, and the day's first hour is the highest-certainty work available anywhere in the log: `CLAUDE.md:216` and five README lines assert a root cause for No Man's Sky, Halo Infinite and Elden Ring that is measurably impossible — the function belongs to an extension the driver does not expose, and the *working* Cyberpunk log emits it 16 times. That signature is not merely wrong, it is load-bearing: `README.md`'s Compatibility Test Plan section is explicitly built on it, so every future DX12/Vulkan test on this rig is being planned against a fiction. Strike it, mark the three titles undiagnosed, and the rest of the day goes to E3 repeated across all three — one launch each with `VKD3D_CONFIG=vk_debug VKD3D_DEBUG=warn VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` and `PROTON_LOG=1` in the launch options, which is vkd3d-proton's own documented recipe and costs no build. The competing candidate, cpu-semantics, buys exactly one small DX9 title behind a 2–4 hour clang build whose payoff the upstream maintainer himself declined to predict — and its README correction (SSE2 *is* advertised; the game reads bit 2, DE) can be landed in five minutes from the `/proc/cpuinfo` probe without building anything, so the build can wait for a day with nothing better. The pattern that has produced this project's best findings is reading a diagnostic the failing component already prints; FEX prints one, unconditionally, on every Vulkan thunk miss, and nobody has ever read it against a failing title.
