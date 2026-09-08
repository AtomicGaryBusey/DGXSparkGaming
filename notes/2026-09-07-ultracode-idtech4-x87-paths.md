# Find existing solutions or concrete modification paths to run id Tech 4 (x87) games on DGX Spark ARM64/FEX

> **Machine-generated report from a multi-agent workflow run.** Persisted from
> scratch storage so it can be read, cited and *checked* later. Treat every claim
> in it as untrusted until verified locally — this project has published agent
> findings that were wrong, and the synthesis itself flags which of its own claims
> survived adversarial verification and which were refuted.

| | |
|---|---|
| Run date | 2026-09-07 |
| Agents | 25 |
| Tokens | 2,364,898 |
| Tool calls | 998 |
| checked | 18 |
| survived | 11 |
| refuted | 7 |

---
## 1. Verdict

**There is no existing turnkey solution, and the answer differs per title.** For DOOM 3 + Resurrection of Evil an *existing artifact* solves it today: dhewm3 1.5.5 ships an official `dhewm3-1.5.5_Linux_arm64.tar.gz`, it is a native aarch64 ELF, it already boots to filesystem init on this GB10 box, and the per-frame assertion is *deleted from the source* (only surviving copy is `neo/sys/aros/aros_main.cpp:293`, gated behind `if(AROS)` in `neo/CMakeLists.txt:1186`). For everything else something must be modified: BFG needs an RBDOOM-3-BFG build (which only *stubs* the check, `neo/sys/sdl/sdl_cpu.cpp:346`), Prey (2006) and Quake 4 are closed-source licensee id Tech 4 with no port at all, and the translator route requires building FEX from source because the three relevant upstream fixes (`21b8f8e2` #5900 generalize ST(0) tag invalidation on pop, `e4e45bcc` #5909 FXCH tag word, `7236c2bf` #5919 FST ST(0) self-store) landed 2026-09-03/04 and are in **neither** FEX-2607 (installed: `fex-emu-armv8.4 2607-1~n`) nor FEX-2608 — `compare/FEX-2608...21b8f8e2` is ahead 185 / behind 0. **And the causal chain is not established.** The x87 stale-tag bug reproduces on this machine (FTW `0xCFFF` after a branch-split block containing `fpatan`/`fyl2x`, where `0xFFFF` is required), and `(0xCFFF ^ 0xFFFFFFFF) & 0xFFFF = 0x3000 ≠ 0` is exactly `Sys_FPU_StackIsEmpty()` returning false — but three ordinary `fld/fstp` pairs scrub the stale tag back to `0xFFFF`, so it has never been shown to survive to the end-of-frame `fnstenv`, and *nobody has ever read the `TAGS` value the engine already prints on every one of these crashes*. Get that number before building anything.

## 2. Ranked paths

Ranked by (probability × playability) / effort. Row 0 yields information, not playability, and is ranked first because it is free and it re-scopes every row below it.

| # | Path | What it changes | Effort | P(works) | First experiment |
|---|---|---|---|---|---|
| 0 | **Quake 4 diagnostic launch (2210)** — already installed, 2.7 GB on disk, `StateFlags 4`, `Quake4.exe` = `PE32 executable (GUI) Intel 80386` | Nothing. Reads the `TAGS = %08x` + `num values on stack` dump the engine prints one line before its own FatalError | ~20 min, zero download | n/a — it is a measurement | See §3 |
| 1 | **dhewm3 1.5.5 arm64 official binary + retail Steam assets** (DOOM 3 9050, RoE 9070 only) | Replaces the engine with native aarch64; removes FEX/Proton/Wine from the process entirely; assertion does not exist in the binary (`strings` finds no "FPU stack is not empty" in `dhewm3` or `base.so`) | ~1 h (1.6 GB install + copy pk4s; runtime libs already staged at `/tmp/dhewm3bin/dhewm3/libs/`) | **~0.9** | Install 9050, `cp base/pak00{0..8}.pk4 /tmp/dhewm3bin/dhewm3/base/`, then `cd /tmp/dhewm3bin/dhewm3 && LD_LIBRARY_PATH=$PWD/libs DISPLAY=:0 ./dhewm3 +set com_showFPS 1 +map game/mars_city1`. Kill condition: `~/.local/share/dhewm3/dhewm3log.txt` reports `GL_RENDERER` = llvmpipe rather than the GB10 |
| 2 | **Build FEX from `main` into a local prefix** (has #5900/#5909/#5919) | The translator. Would fix *all four* titles at once if the tag bug is causal, and is the only route that keeps this a translated-stack result | hours (cmake 3.28.3, g++ 13.3, 20 cores, 334 GB free; **no ninja installed** → `-G "Unix Makefiles"`) | **~0.3** — right bug class, right file, but the stale tag is scrubbed by ~3 subsequent x87 ops and has never been shown to reach end-of-frame | Check first whether FEX-2609 has shipped (monthly cadence, 2608 was 2026-08-05). Then build and run the existing probe: `~/dgx-gaming-work/fex-main/bin/FEXInterpreter /tmp/vfy/v2 \| od -An -tx4 -w4 -v` must read `0000ffff ×4, 00000001, 0000ffff` (2607 gives `0000cfff ×4, 00000000, 0000ffff`). Only then relaunch Quake 4 |
| 3 | **RBDOOM-3-BFG source build, aarch64** (BFG 208200 only — confirmed owned) | Replaces the BFG engine; `neo/sys/sdl/sdl_cpu.cpp:346` is `// TODO / return true;` so the assert is neutered. Also native, not translated | ~1 day (Vulkan/GL deps, no sudo) + 7.4 GB install | ~0.5 for a working ARM64 build; ~0.95 that the assert is gone if it builds | Install 208200; run `file "…/DOOM 3 BFG Edition/Doom3BFG.exe"` **first** — it settles the README's unverified "64-bit" claim for free before any build |
| 4 | **Binary-patch the assertion** (2-byte `Sys_FPU_StackIsEmpty` → `return true`) in Quake4.exe / Prey / Doom3.exe | The owned game binary. **The only route that exists for Prey (2006) at all** | hours | **Unknown, and row 0 decides it.** If `num values on stack` is stable → patch is free. If it grows per frame → real x87 leak, patch buys frames then yields NaN geometry or stack overflow | Do not attempt before row 0 returns a `TAGS` value |
| 5 | Report the verified box64 arm64 EMMS bug upstream (`dynarec_arm64_0f.c` case 0x77 passes `next=1` to `x87_purgecache`; upstream `0b9b6322d` fixed la64/rv64 with `next=0`) | Nothing on this rig's game path | ~1 h | 0 playability — file it as a byproduct, not as a fix | `git format-patch` the one-character change; all 6 emms64 cases pass after it |

**Honest read: row 1 is the pragmatic winner and it is the least interesting one.** It makes DOOM 3 and RoE fully playable with the user's Steam assets, today, and it teaches this log nothing about FEX — it removes the translation stack rather than measuring it. It must therefore go in a *separate* README section (native-ARM64 source ports), **not** the Tested-by-AGB table, or it misrepresents itself as a Proton/FEX result.

## 3. Cheapest falsifiable experiment — run this FIRST

Quake 4 is the free reproducer nobody used. It is **already installed** (no 1.6 GB DOOM 3 download), it is id Tech 4, its `Quake4.exe` is `PE32 … Intel 80386`, and `strings` confirms it carries the whole diagnostic chain: `FPU stack is not empty` ×1, `TAGS = %08x` ×1, `num values on stack` ×1, `logFileName` ×1, `qconsole.log` ×2. `q4base/gamex86.dll` additionally carries `FPU stack not empty` (the `idGameLocal::CalcFov` variant).

```bash
cd /home/aharmon/DGXSparkGaming
tools/config-snapshot.sh save
tools/game-run.sh 2210 -- +set logFile 2 +set logFileName qconsole.log +set com_showFPS 1
# in a second shell, do NOT hand-roll a watcher:
tools/watch-run.sh --count 'FPU stack is not empty'
```

Load a map (new game past the intro). After it crashes or plays:

```bash
Q4="/home/aharmon/.local/share/Steam/steamapps/common/Quake 4"
grep -n -B14 -A2 'TAGS = ' "$Q4/q4base/qconsole.log"
grep -n 'FPU stack' "$Q4/q4base/qconsole.log"
# fallback if id Tech 4 routed the log into the prefix instead of the install dir:
find /home/aharmon/.local/share/Steam/steamapps/compatdata/2210 -name 'qconsole.log' 2>/dev/null
```

Record the **low 16 bits of `TAGS` and the `num values on stack` integer together** — either alone is ambiguous.

Outcomes, mutually exclusive:

- **Quake 4 loads a map and plays.** Kills the framing. "All id Tech 4 is broken under FEX" is false; the README matrix must be narrowed to DOOM 3 / BFG / Prey specifically, and the tag-word theory loses its generality (Quake 4 has 41 `fpatan`, 19 `fyl2x`, 4 `fnstenv` in `.text` and would be expected to trip it). Rows 2 and 4 drop sharply in value.
- **Crashes, `TAGS & 0xFFFF != 0xFFFF`, `num values on stack > 0`.** The x87 stack is *genuinely* non-empty; `fnstenv` is reporting truth. Tag-word *synthesis* is exonerated, the hunt becomes a real unbalanced push, and a binary patch (row 4) becomes risky rather than free. The set bits name the physical slots.
- **Crashes, `TAGS & 0xFFFF == 0xFFFF`.** The check-time and dump-time `fnstenv` disagree — a non-deterministic/ordering bug in the translator's `fnstenv`, which is a bigger and more reportable finding than the leak, and makes row 4 free.
- **No `qconsole.log`, or it exists with no `TAGS` line, or the game dies without the FatalError string.** The diagnosis in README.md:2049-2051 is misattributed at the root and the whole thread reopens.

Cost: one launch, no download, no build, no patch.

## 4. Dead ends — do not re-tread

- **`X87ReducedPrecision`.** Measured and source-confirmed dead. `Frontend.cpp:74-79` shows the option's *only* decode-time effect is `X87Table = &X87F64Ops` vs `&X87F80Ops`; diffing the two tables (`X87Tables.cpp:20-292` vs `294-566`) shows 140 identical opcode keys with `X87FNSTENV`, `X87FNSAVE`, `X87FRSTOR`, `X87FFREE`, `FNINIT`, `X87FNSTSW` being the *same handler* in both. FEX's FTW is derived from an 8-bit `AbridgedFTW` by push/pop bookkeeping and never reads register data; the FTW mask construction in `x87StackOptimizationPass.cpp:640-676` has no precision branch. Toggling it leaves every tag word bit-identical (only the *value* slot changes: `0x3C30000000000000` → `0x0`). It cannot move a tag between Empty and non-Empty.
- **"FEX's `fnstenv` writes zeros into the tag word."** Falsified by direct measurement, 32- and 64-bit: empty stack → `0xFFFF`, one value → `0x3FFF`. Also self-contradictory — that check runs at the end of *every* `idCommonLocal::Frame`, including menu frames, so a systematic failure would kill the game on frame 1, not at map load.
- **Box64's ST-relative tag word as the explanation.** Real (`x87emu_private.h:58/74` is a shift register; `x64emu_private.h:83` even says "stacked"; FLD1 → `0xfffc` vs hardware `0x3fff`), but symmetric for the all-empty test on the 32-bit path, and box64 is very likely not in the game path at all (Steam launches via `FEXBash`; an x86 ELF exec'd from inside a FEX process stays under FEX — measured).
- **The box64 arm64 EMMS bug as the explanation.** Genuine, current, and correctly patched (`dynarec_arm64_0f.c` case 0x77 → `x87_purgecache(..., next=0, ...)`; still unfixed in `origin/main` @ `4e5f1806d`). Not the cause: BFG's GPL source contains **zero** `emms`; none of DOOM 3's seven EMMS sites (`Simd_MMX.cpp:87,131,215,359`, `Simd_SSE.cpp:17932,18069`, `Simd_3DNow.cpp:290`) has an `fld`/`fstp`/`fild`/`fistp` in the same `_asm` block; MMX-memcpy-then-EMMS passes unpatched; and `fld1; call <fn containing emms>` passes unpatched (the delta is block-local). File it upstream on its own merits.
- **"BFG doesn't contain the assertion."** False, and a textbook rule-#1 error: BFG *moved* the frame loop into `neo/framework/common_frame.cpp`, where lines 690-694 carry the identical `FatalError("idCommon::Frame: the FPU stack is not empty at the end of the frame\n")`. Grepping only `Common.cpp` returns a false negative.
- **"The FPU values were clean (all zeros), so the check is lying."** Not evidence either way. `Sys_FPU_StackIsEmpty` reads only `[statePtr+8]`, the tag word — it never inspects a float. And `Sys_FPU_GetState`'s `double fpuStack[8] = {0.0,…}` is zero-initialized and (DOOM 3) printed unconditionally / (BFG) filled by a top-down walk that `jz done`s on the first Empty slot. All-zeros is the initializer, not a reading. The load-bearing fields are `TAGS` and `num values on stack`.
- **Waiting for the PPA to deliver the FEX fix.** `fex-emu-armv8.4` candidate is `2607-1~n`; the three tag fixes are in no release. Build from source or wait for 2609+.
- **`FEXInterpreter`-as-a-fallback-interpreter.** FEX has no IR interpreter; `/usr/bin/FEXInterpreter` is the binfmt loader. The nearest knob is `FEX_O0=1` (`PassManager.cpp:70-76` gates `CreateX87StackOptimizationPass` on it) — but that disables *every* pass, so it is a confounded bisect, not a clean one.
- **Two README lines that are wrong and should be corrected in the same edit** (both came from reasoning, not measurement): README.md:2049 "32-bit binary goes through BOX32 mode" (BOX32 is box64's mode; under Proton this ran on FEX), and README.md:2050 "64-bit OpenGL" for BFG (`neo/doomexe.vcxproj` declares only `Debug|Win32`, `Release|Win32`, `Retail|Win32`; `grep -rl x64 --include=*.vcxproj --include=*.sln --include=*.props` over the whole tree returns nothing; `idlib/sys/sys_defines.h:93` hard-defines `CPUSTRING "x86"`; and MSVC rejects `__asm` on x64 outright). Note the EGS build of BFG is reportedly 64-bit — that is secondary reporting, so scope the correction to the Steam build and settle it with `file` when installed.

## 5. Genuinely unknown

- **Which translator actually executed DOOM 3, BFG and Prey when those results were recorded.** Never logged. `binfmt_misc` here registers only box32/box64 (both → `/usr/local/bin/box64`) with no FEX entry, but Steam launches through `steam-fex`/`FEXBash`, so everything under Proton should be FEX. This is inference on both sides. All three titles are currently uninstalled, so the original observations cannot be re-checked.
- **The `TAGS` value at any of these crashes.** Never captured, not once, on any of the three titles — despite the engine printing it one line before dying. This is the single largest hole and §3 closes it for free.
- **Whether the x87 stack is genuinely non-empty (real leak) or spuriously tagged.** Determines whether row 4's binary patch is free or fatal, and whether the FEX fix in row 2 can possibly help.
- **Whether the `0xCFFF` stale tag can survive a real frame.** Measured: `+3 fld1/fstp` pairs, or one `fld/faddp/fstp`-to-memory, restore `0xFFFF`. A real id Tech 4 frame runs thousands of x87 ops between any `atan2` and the end-of-frame `fnstenv`. The mechanism is reproducible; its reach is not demonstrated.
- **Whether any of this reproduces on the path a game actually uses.** Every probe so far is a Linux ELF under `FEXInterpreter`. No Windows PE under Wine/Proton has been probed, and `fex-emu-wine 2608`'s `libwow64fex.dll` has never been tested (though for an x86-64 Proton it should not be in the path at all).
- **Retail `Doom3BFG.exe` bitness.** Never `file`d — BFG is not installed. The GPL evidence is strong but indirect.
- **Whether retail `Quake4.exe` / `Doom3.exe` implement the assertion identically to the GPL drop.** The message strings are present in `Quake4.exe` (confirmed above), and 19 `fyl2x` / 41 `fpatan` / 4 `fnstenv` appear in `.text`, but the exact `Sys_FPU_StackIsEmpty` body was not disassembled.
- **Whether dhewm3 gets a real GB10 GL context.** It has only ever reached SDL2/X11 + filesystem init on this box (`dhewm3 1.5.5.1305 linux-arm64`, `SDL video driver: x11`, then `Sys_Error: Couldn't load default.cfg`). No `GL_RENDERER` line has ever been observed. Native rendering is currently inference.
- **Ownership of DOOM 3 (9050) and Prey (3970).** `~/dgx-gaming-work/owned_sizes.txt` lists 208200 (BFG) but not 9050, 3970 or 2210 — and Quake 4 is installed on disk, so that file is incomplete and its silence proves nothing. Confirm with `tools/appinfo.py` before planning around row 1.
- **Why id Tech 2/3/6+ pass.** Partly, possibly entirely, because they carry no equivalent per-frame x87 tag-word assertion. The matrix line "2 ✅ / 3 ✅ / 4 ❌ / 6+ ✅" may be measuring *which engines check*, not which engines are correctly translated. Worth a sentence in the README.
