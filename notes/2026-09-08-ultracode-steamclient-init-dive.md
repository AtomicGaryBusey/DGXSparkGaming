# Deep dive on "Access violation in steamclient_init" for Steam legacy-DRM titles under Proton on ARM64

> **Machine-generated report from a multi-agent workflow run.** Persisted from
> scratch storage so it can be read, cited and *checked* later. Treat every claim
> in it as untrusted until verified locally — this project has published agent
> findings that were wrong, and the synthesis itself flags which of its own claims
> survived adversarial verification and which were refuted.

| | |
|---|---|
| Run date | 2026-09-08 |
| Agents | 14 |
| Tokens | 1,480,414 |
| Tool calls | 548 |
| verified | 9 |
| survived | 8 |
| refuted | 1 |

---
# steamclient_init access violation — DOOM 3 / Prey under Box64

Verified on this box 2026-09-07/08. Every fact below marked **[D]** was re-derived by me from files or logs on disk; **[I]** is inference from observed facts; **[U]** is unknown.

---

## 1. The mechanism

**A. The executables are SteamStub-wrapped; Quake 4's is not. [D]**
Parsed from the PE headers (all `machine=0x14c`, 32-bit):

| exe | entry point | lands in | `.bind` |
|---|---|---|---|
| `Prey 2006/prey.exe` | `0x29923db` | `.bind` | VA `0x2992000`, VS `0x2000` |
| `Doom 3/Doom3.exe` | `0x27f4000` | `.bind` (its first byte) | VA `0x27f4000`, VS `0x1000` |
| `Quake 4/Quake4.exe` | `0x28846d` | `.text` | none |
| `Prey 2006/PREYDed.exe` | `0x1f463d` | `.text` | none |
| `Quake 4/Quake4Ded.exe` | `0x27360d` | `.text` | none |
| `RAGE/Rage.exe` | `0x16ce2ee` | `.bind` | VA `0x16ce000`, VS `0x87000` |

**B. Proton copies the legacy kit into every prefix unconditionally. [D]**
`Proton - Experimental/proton` lines ~1088-1099 copy `legacycompat/{steamclient.dll, steamclient64.dll, GameOverlayRenderer64.dll, SteamService.exe→steam.exe, Steam.dll}` into `drive_c/Program Files (x86)/Steam/`. Not gated on appid, not gated on legacy-DRM keys. So the per-title split cannot come from Proton.

**C. The `.bind` stub loads `Steam.dll` at runtime. [I — strongly corroborated]**
Neither `prey.exe` nor `Doom3.exe` imports `Steam.dll` statically. In both Box64 logs `Steam.dll` is module ~#44, after all static imports, immediately after `PSAPI.DLL` and immediately before `bcrypt/crypt32/wintrust/imagehlp` — a module-enumerating, signature-checking stub profile. **Nobody has traced the actual call site.**

**D. Proton's Wine hooks any `LoadLibrary` whose basename is `steamclient`. [D]**
ValveSoftware/wine commit `53ba023e0a3638123c1ae64a070b45b76fdedece` ("HACK: steam: ntdll: Setup steamclient trampolines to lsteamclient") matches `steamclient` / `steamclient64` / `gameoverlayrenderer` / `gameoverlayrenderer64`, loads builtin `lsteamclient.dll` and installs exec-fault trampolines. The whole block is gated on `use_lsteamclient()`, false iff `PROTON_DISABLE_LSTEAMCLIENT` is set to anything but `"0"` — that string is present in the shipped `files/lib/wine/i386-windows/ntdll.dll` and is the *only* `PROTON_*` string in it.

**E. For a 32-bit process the unix half is a 32-bit ELF that needs libstdc++. [D]**
`readelf -dW 'Proton - Experimental/files/lib/wine/i386-unix/lsteamclient.so'` → NEEDED `ntdll.so, libstdc++.so.6, libgcc_s.so.1, libc.so.6`. Of **every** `.so` in `i386-unix/`, only `lsteamclient.so` and `vrclient.so` need libstdc++. That is why 32-bit Proton titles generally work under Box64 and this one path does not.

**F. It dlopens a 49 MB i386 Steam library, chosen by bitness. [D]**
`strings` on the shipped `i386-unix/lsteamclient.so` contains literally `%s/.steam/sdk32/steamclient.so` and `steamclient_init`; the `x86_64-unix` twin contains `.../sdk64/...`. `/home/aharmon/.steam/sdk32/steamclient.so` = 49,104,528 bytes, ELF 32-bit i386.

**G. Box64's box32 libc wrapper table is missing four symbols that the container's i386 libstdc++ imports. [D]**
`/home/aharmon/box64` @ `2f130fab1` (tag v0.4.4 — the installed build). `src/wrapped32/wrappedlibc_private.h`: `strtold` **commented out** at lines 1754 and 1759; `arc4random`, `strfromf128`, `strtof128` absent from the entire `src/wrapped32/` tree. All four are present and active in the 64-bit table: `src/wrapped/wrappedlibc_private.h:2738 GO(arc4random, uFv)`, `:2001 GOD(strfromf128,…)`, `:2047 GOD(strtof128,…)`, `:2076 GOD(strtold, DFpp, strtod)`.

`readelf -sW --dyn-syms` on `SteamLinuxRuntime_4/steamrt4_platform_4.0.20260805.254769/files/lib/i386-linux-gnu/libstdc++.so.6.0.33` UND set contains exactly `arc4random, strfromf128, strtof128, strtold` (plus `strtold_l`, which *is* wrapped — which is why only four errors fire).

Wine dlopens unix halves `RTLD_NOW`; `src/wrapped/wrappedlibdl.c:231` maps `flag&0x2` → `bindnow`; `src/elfs/elfloader32.c:588` makes a missing non-weak `R_386_JMP_SLOT` fatal under bindnow; `src/librarian/library.c:603` turns that into `Error: relocating Plt symbols in elf %s` and `FinalizeLibrary` returns 1 → `dlopen` returns NULL.

Observed, `/home/aharmon/dgx-gaming-work/runs/3970-20260907-231525/proton.log` lines 2198-2213 and again 2384-2439 (two distinct box64 `library_t` instances), identically in `9050-20260907-232102`.

**H. The fault instruction is decoded, not guessed — the unixlib handle is NULL. [D]**
`nm files/lib/wine/i386-unix/ntdll.so`: `00046590 t __wine_unix_call_dispatcher`, `000465a0 t __wine_unix_call_dispatcher_prolog_end`. Raw bytes (exec `LOAD` has `off == vaddr`):

```
0x465cc  8b 04 24        mov  eax,[esp]        ; unixlib handle, low dword
0x465cf  8b 54 24 08     mov  edx,[esp+8]      ; unixlib function index
0x465d3  8d 61 f0        lea  esp,[ecx-0x10]
0x465d6  ff 14 90        call dword ptr [eax+edx*4]   <-- faults
```

Fault dump: `eax=00000000 … edx=00000000`, `info[1]=00000000`. So `__wine_unixlib_handle == 0` and the index is 0 (the first unixlib entry). **This closes the step that was previously inferred.** The unix half was never loaded.

**I. Then lsteamclient reports it and deliberately dies. [D]**
Wine returns to `ip=785ccfcd` = inside `lsteamclient.dll` @`785C0000` +0xcfcd; `err:steamclient:steamclient_call Access violation in steamclient_init.`; then `dispatch_exception addr=785CCFF1 info[1]=0000BEEF`, `wine: Unhandled page fault on read access to 0000BEEF`. Under Box64, `qconsole.log` is never written at all.

**Timing. [D]** Box64: `steamclient.dll` loaded and faulted in the same millisecond bucket (`189584.600`), immediately after the second `relocating Plt symbols in elf libstdc++.so.6` at log line 2439. FEX: 182 ms (Prey) / 157 ms (DOOM 3) *inside* `steamclient.dll`, then a clean `free_modref` of both modules.

### The Prey-vs-Quake-4 discriminator

**Partly answered, partly still unknown. Say both.**

Answered [D]: **Quake 4 does not survive `steamclient_init` — it never enters the path.** Cross-tab of every attributed run:

```
run                       runtime  BOX32err  libstdc++Plt  Steam.dll  32-bit lsteamclient  AV
3970-20260907-231525      Box64      12          2            1              1             1
3970-20260907-231800      FEX         0          0            2              1             0
9050-20260907-232102      Box64      10          2            1              1             1
9050-20260907-232337      FEX         0          0            2              1             0
2210-20260907-223229      Box64       0          0            0              0             0
2210-20260907-225230      FEX         0          0            0              0             0
```

The `Steam.dll` load is **runtime-independent** and tracks the PE (`EP inside .bind`), not the appinfo key. The AV is **Box64-only**.

Not the key method [D]: Quake 4 and Prey are *both* `legacykeyregistrationmethod=disk` with opposite outcomes (re-read with `tools/appinfo.py`). DOOM 3 (`registry`, `TestApp9050\SteamKey`) has `base/STEAM_doomkey` + `STEAM_xpkey` on disk and fails; Prey's `base/preykey` **does not exist** and it still reaches `steamclient_init`.

Still unknown [U]: whether "EP in `.bind` ⇒ loads `steamapps/common/Steam.dll`" generalizes past this 2004-2009 stub generation. **RAGE (9200) is the live counterexample candidate** — installed, 32-bit, `.bind` with EP inside it, *no* `legacykey*` keys, and the only one of the six that statically imports `steam_api.dll`. Scope the rule to the legacy id titles until §4/E3 is run. Also unknown: which instruction in `.bind` calls `LoadLibrary` and with what path string.

---

## 2. ARM64 problem or Proton/Wine problem?

**ARM64 translation. Specifically Box64 v0.4.4's box32 32-bit libc wrapper table. Not Proton, not Wine, not Steam, not the DRM. The fix belongs to `ptitSeb/box64` and is four `GO()` lines.**

Evidence:

1. **Controlled JIT swap, both titles, same box.** Identical Proton (`experimental-11.0-20260903b-x86_64`), identical prefix, identical module set at identical base addresses (Prey `79F30000` / `785C0000` / `78870000`; DOOM 3 `79F50000` / `787C0000` / `78A70000`), identical order. Box64 → AV in 0 ms. FEX → both modules released, engine proceeds, writes `qconsole.log` (Prey `base/qconsole.log` mtime 23:18, DOOM 3 23:23), reaches OpenGL init, then dies at an unrelated `...SetPixelFormat failed`.
2. **The named defect is in box64's source tree, not Wine's** (§1G). And in the *same* Box64 runs the **64-bit** `lsteamclient.dll` loads fine at `0x6FFFFD790000` — 64-bit wrapper table complete, 32-bit table not. 64-bit-fine / 32-bit-fatal is the single cleanest fact here.
3. **The fault is Box64 failing to execute a correct Wine dispatch**, not Wine dispatching wrongly. The instruction at `0x465d6` is right; the operand is NULL because a Linux `dlopen` that box64 performed returned NULL.
4. **Upstream x86-64 is healthy.** ProtonDB `9050` = tier gold, 83 reports, best-reported platinum; `3970` = platinum, 22 reports. Proton issue **#713** (DOOM 3, open, updated 2026-01-17) is people arguing about a *mouselook regression* on 9.0-4 / Experimental / bleeding-edge — i.e. the game runs, as recently as 2026-01. Proton **#1741** (Prey) has a completed playthrough, but its last activity is 2022 and is **not** current for 11.0. GitHub search of `ValveSoftware/Proton` for `steamclient_init` returns one unrelated hit (#7867).

### What would overturn it

- **(a) Run-order / prefix-state confound — the only real threat.** In *both* pairs Box64 ran first, and Prey's Box64 run *created* the prefix (`Proton: Upgrading prefix from None to 11.0-100` in its `launch.log`; the FEX run inherited it). n=1 per cell. Experiment E2 closes this. If a warm-prefix Box64 run clears the AV, the whole attribution collapses.
- **(b) Stack confound.** `RUNTIME=fex` wraps the chain in `FEXBash` (game-run.sh ~line 218), which also swaps the Linux-side x86 library environment (FEX RootFS); box64 goes via binfmt with container/host libs. The arms are "FEX stack vs Box64 stack", not "same stack, different JIT". The byte-identical Windows-side module set limits how much this can matter, but it is not zero.
- **(c) The kill shot.** Add the four wrappers, rebuild box64, re-run. If the BOX32 relocation errors vanish and the AV persists, the mechanism is wrong even though every static fact in it is true.

---

## 3. Ranked resolution paths

### 1. `RUNTIME=fex` — use the other JIT
FEX has no libc wrapper table (it runs the container's real i386 glibc/libstdc++ under its RootFS), so this failure mode cannot occur.
**Effort:** zero. **Probability of clearing `steamclient_init`:** measured twice, both titles. **Probability of the game actually running: LOW** — Prey and DOOM 3 both then die at `...SetPixelFormat failed` with no GL context, and id Tech 4's x87 FPU-stack assert is still waiting behind that.
**Cost:** none. No achievements to lose (`community_visible_stats` absent for 9050/3970/2210), overlay/cloud/online unaffected, no ToS question.
```
RUNTIME=fex /home/aharmon/DGXSparkGaming/tools/game-run.sh 3970
```

### 2. Patch box64's `wrapped32` libc table and rebuild — the actual fix
Add `arc4random`, `strfromf128`, `strtof128`, `strtold` to `src/wrapped32/wrappedlibc_private.h` mirroring the 64-bit entries.
**Effort:** hours (one build). **Probability the AV goes away:** high. **Probability the *game* runs:** still gated by SetPixelFormat / x87.
**Cost:** none to the user; upstreamable. No existing box64 issue covers this exact case — #1119 (closed) is the same class (`Cannot dlopen("steamui.so")`, mentions `strtof128`/`strfromf128`) on a different consumer.
**Do not just pull upstream:** `origin/main` @`4e5f1806d` (2026-09-07) has `GO(arc4random, uEv)` at `wrapped32/wrappedlibc_private.h:57` but `strtold` is *still* commented out (`:1766`, `:1771`) and `strtof128`/`strfromf128` are *still* absent. Upgrading fixes 1 of 4 and produces a false negative.
```
cd /home/aharmon/box64 && sed -n '2001p;2047p;2076p;2738p' src/wrapped/wrappedlibc_private.h
```

### 3. `PROTON_DISABLE_LSTEAMCLIENT=1` — removes the faulting path, does not fix the game
Valve's own variable; `use_lsteamclient()` returns false, `lsteamclient.dll` is never loaded, no 32-bit unix call, no AV.
**Effort:** minutes. **Probability the AV goes away:** high. **Probability the game runs: LOW, and say why** — the same gate also sets `LDR_DONT_RESOLVE_REFS` for a 32-bit steamclient, so with the var set Wine *will* resolve imports, and I parsed `legacycompat/steamclient.dll`'s import table: it imports **`tier0_s.dll`** and **`vstdlib_s.dll`**, neither of which exists anywhere in the prefix, the Steam root, or the game dirs. Expect `err:module:import_dll Library tier0_s.dll … not found` and a clean failure instead of a fault.
**Cost:** Steam overlay dead for that launch; any in-game Steamworks call fails. For these three titles that is nearly free — no `community_visible_stats` (no achievements) for 9050/3970/2210; DOOM 3's `ufs.savefiles` cloud sync is done by the client around the process, not the in-game API; Prey has no `ufs` block; playtime is client-side. Valve's own variable in Valve's own Wine — **no ToS issue.** (Note this would *not* be free for RAGE, which does have `community_visible_stats`.)
```
PROTON_DISABLE_LSTEAMCLIENT=1 RUNTIME=box64 /home/aharmon/DGXSparkGaming/tools/game-run.sh 3970
```

### 4. `WINEDLLOVERRIDES="steamclient=d"` — narrower, untested
Fails the `steamclient.dll` load itself rather than disabling the redirect globally, so the basename hook never fires. **I have not confirmed the override is consulted before Proton's basename hack.**
**Effort:** minutes. **Probability:** unknown. **Cost:** same class as #3.
```
WINEDLLOVERRIDES="steamclient=d" RUNTIME=box64 /home/aharmon/DGXSparkGaming/tools/game-run.sh 3970
```

### 5. Strip the SteamStub wrapper (Steamless) — removes the trigger
Rewrite `prey.exe` / `Doom3.exe` with the OEP restored so `.bind` never runs, so `Steam.dll` is never loaded.
**Effort:** a day (Steamless is .NET/Windows; would have to run under Wine/FEX here). **Probability of clearing *this* fault:** high. **Probability the game runs:** unchanged by the SetPixelFormat/x87 walls.
**Cost — plainly:** this is DRM removal on a title the user owns. It kills the legacy CD-key check. Overlay and Steamworks are already absent for these two (neither ships `steam_api.dll`); playtime still counts if launched through the client. The Steam Subscriber Agreement prohibits modifying or circumventing content protection; doing it to your own copy for personal compatibility is the usual gray area and is not something to publish binaries from. **Do not reach for this before #2** — it treats a symptom that has a named upstream defect.

### 6. Record it and file the box64 issue
These are id Tech 4 titles; even past `steamclient_init` they hit the documented x87 assert. The highest-value output is the README correction below plus an upstream issue.

**README correction owed either way [D]:** the current Known Issues rows attribute DOOM 3 / Prey to the id Tech 4 x87 FPU assert. **Under Box64 that is wrong — they never reach engine code at all** (no `qconsole.log` is written). Under FEX they *do* reach engine code and die at `SetPixelFormat`, which is also not the x87 assert. Those rows need a runtime qualifier before anything else is published.

---

## 4. The three cheapest experiments

All three are single launches through `tools/game-run.sh` (never by hand, never under `timeout`). Everything in §1 A/B/E/F/G/H is re-derivable from files already on disk in under a minute, with zero launches.

### E1 — close the last inferred link: make Wine print the dlopen failure
`WINEDEBUG` in the archived runs is `+timestamp,+pid,+tid,+seh,+unwind,+threadname,+debugstr,+loaddll,+mscoree` — **no `+module`**, which is exactly why no "failed to load .so lib" line appears. Proton **appends `PROTON_LOG`'s value to `WINEDEBUG` whenever `PROTON_LOG != "1"`** (`proton` lines 1728-1737), so:

```bash
cd /home/aharmon/DGXSparkGaming
NO_PROTON_LOG=1 \
PROTON_LOG='+timestamp,+pid,+tid,+seh,+loaddll,+module' \
BOX64_DLSYM_ERROR=1 RUNTIME=box64 tools/game-run.sh 3970
R=$(ls -dt /home/aharmon/dgx-gaming-work/runs/3970-* | head -1); echo "$R"
grep -nE 'failed to load .so|Cannot dlopen|lsteamclient|relocating Plt symbols|steamclient_init|eax=00000000' \
  "$R/proton.log" | sed 's/\x1b\[[0-9;]*m//g'
```
**Confirms:** a Wine WARN naming `lsteamclient.so` failing to load, and/or box64's `Cannot dlopen(".../i386-unix/lsteamclient.so"…)`, between the libstdc++ Plt error and the `eax=00000000` fault.
**Kills the idea:** `lsteamclient.so` is reported as loading *successfully* and the AV still fires with `eax=0` → the NULL handle has another origin and the libstdc++ failure is a bystander. Equally fatal: the only failing dlopen is `vrclient.so`.
**Do not use `BOX64_LOG=1`** — `printf_dlsym` is gated in `src/include/debug.h` on `BOX64ENV(dlsym_error) || BOX64ENV(dump) || L<=log`, and the `Cannot dlopen` site passes `LOG_DEBUG`(=2) for any path containing `/`. `BOX64_DLSYM_ERROR` is a BOOLEAN at `src/include/env.h:49`; `BOX64_LOG=2` also works and is far noisier.

### E2 — kill the run-order / prefix confound (the only real threat to §2)
DOOM 3's prefix has now had a *successful* FEX run in it. Re-run Box64 in that warm prefix:
```bash
RUNTIME=box64 /home/aharmon/DGXSparkGaming/tools/game-run.sh 9050
R=$(ls -dt /home/aharmon/dgx-gaming-work/runs/9050-* | head -1)
grep -o '"runtime_actual": "[^"]*"' "$R/run.json"
grep -c 'Access violation in steamclient_init' "$R/proton.log"
grep -c 'relocating Plt symbols in elf libstdc' "$R/proton.log"
```
**Confirms:** `runtime_actual` = `Box64` **and** the AV reproduces → the JIT is the variable.
**Kills the idea:** no AV → prefix state / run order was the variable and the Box64 attribution collapses entirely.
**Also kills the run (not the idea):** `runtime_actual` comes back `unknown`. Three 3970 runs and four 2210 runs today are unattributed and prove nothing — abort the reading.

### E3 — test the `.bind` generalization against its best counterexample
RAGE, appid 9200, already installed: 32-bit, `.bind` @`0x16ce000` size `0x87000` with EP `0x16ce2ee` inside it, **no** `legacykey*` in appinfo, and the only one of the six that statically imports `steam_api.dll`.
```bash
RUNTIME=box64 /home/aharmon/DGXSparkGaming/tools/game-run.sh 9200
R=$(ls -dt /home/aharmon/dgx-gaming-work/runs/9200-* | head -1)
grep -nE 'common..Steam\.dll|steam_api|lsteamclient\.dll" at 7|relocating Plt symbols in elf libstdc|steamclient_init' "$R/proton.log"
```
**Kills the universal ".bind ⇒ loads Steam.dll":** RAGE reaches its entry point and loads **no** `steamapps\common\Steam.dll` (only `steam_api` / `lsteamclient`). Then `.bind` and the legacy keys are two co-markers of the same era, not independent predictors, and the README rule must be scoped to the legacy id titles.
**Confirms and broadens:** RAGE loads `Steam.dll` preceded by `PSAPI.DLL` on the same TID — and if it also emits the libstdc++ Plt error and the AV, the failure class is "32-bit legacy-stub titles under Box64", wider than id.
Answer is valid even if RAGE crashes seconds later; only entry-point execution is required.

---

## 5. Dead ends

- **"It's the legacy-DRM key method (registry vs disk)."** Refuted. Quake 4 and Prey are *both* `disk`, opposite outcomes. DOOM 3 has its key files present and fails; Prey's `base\preykey` doesn't exist and it still reaches `steamclient_init`. The keys are the *payload* the legacy `Steam.dll` API fetches, not the discriminator — but do **not** call them "orthogonal / a red herring" either; they co-occur with this stub generation by era.
- **"The `.bind` section predicts the `Steam.dll` load, universally."** Refuted as stated: n=2, overreach, and the citation was wrong. The Steamless README says nothing about `.bind`; the corroborating source is Steamless's `SteamStubHeader` classes (`BindSectionOffset` / `OriginalEntryPoint`), not its README or a PCGamingWiki *user* page. Two further fixes: the predicate must be **"EP inside `.bind`"**, never "has a `.bind`" — `Riddick/DarkAthena.exe` has a `.bind` with `RawSz=0` and its EP relocated into `.init` by a second wrapper (Tages). And the surviving narrow claim is scoped to the legacy id titles.
- **"FEX skips `steamclient_init` / never gets there."** Refuted. FEX loads the identical three modules at the identical bases, spends 157-182 ms inside native `steamclient.dll`, returns with no exception, releases both, and the engine writes `qconsole.log` and reaches OpenGL init. Load order is not the variable.
- **"Quake 4 survives `steamclient_init`, so the key method matters."** Refuted. It never enters the path: zero `Steam.dll` loads, zero 32-bit `lsteamclient` loads, zero BOX32 errors, under **both** JITs. Not entering ≠ surviving.
- **"It's a Proton or Wine bug — file it with Valve."** Dead. Upstream x86-64 is healthy, and the faulting instruction is a *correct* dispatch through a NULL operand that box64 produced.
- **"Upgrade box64 to upstream main."** Dead as a fix: `main` @`4e5f1806d` has `arc4random` in wrapped32 but `strtold` still commented out and `strtof128`/`strfromf128` still absent. 1 of 4.
- **"`BOX64_LOG=1` will show the dlopen failure."** Wrong knob — see E1.
- **"`PROTON_DISABLE_LSTEAMCLIENT=1` will make the game run."** No: it removes the fault and exposes `steamclient.dll`'s unsatisfiable `tier0_s.dll`/`vstdlib_s.dll` imports. Diagnostic, not a fix.
- **"Reproduce on another Spark."** Identical hardware per CLAUDE.md; validates nothing.
- **The `libgpg-error.so.0` / `closefrom` relocation failure at log line 1979** is the *same* box32 bug on a different library and is harmless — nothing dereferences a NULL handle there. Do not fold it into the causal story. It does prove a box32 Plt failure is survivable in general; this one is fatal only because lsteamclient dispatches through the handle without checking it.

---

## 6. Genuinely unknown

1. **Which dlopen box64 aborted.** Everything around it is observed — the four missing symbols, the fatal Plt error in the same millisecond as the load, the NULL handle decoded straight off the instruction, and the fact that `lsteamclient.so` and `vrclient.so` are the *only* i386-unix libs needing libstdc++ — but the dlopen verdict itself is log-suppressed. E1 closes it. `vrclient.so` is the only competing candidate.
2. **Whether run order / prefix state confounds the FEX-vs-Box64 split.** Box64 ran first in both pairs; Prey's Box64 arm created its prefix. n=1 per cell. E2 closes it.
3. **Whether the four wrappers actually fix it.** Nobody has rebuilt box64. Every static fact can be true and the causal step still wrong.
4. **Where in `.bind` the `LoadLibrary` happens, and what string it passes.** CWD at launch is `GAMEDIR` (game-run.sh ~line 254) and `steamapps/common` is not a standard Wine DLL search dir, so the stub is probably passing `..\Steam.dll` or an absolute path. That is the difference between "the stub knows Steam's layout" and "Wine happened to find it".
5. **Whether "EP in `.bind`" generalizes past 2009.** E3.
6. **Why Prey's `base/preykey` was never written on this box** while Quake 4's `q4base/quake4key` exists with a post-install mtime, when appinfo says both are `disk` method. The key hypothesis is dead regardless, but this is an unexamined asymmetry, not a non-fact.
7. **Whether `RUNTIME=fex` also swapping the Linux-side x86 library environment (FEXBash / FEX RootFS)** contaminates the comparison versus box64's binfmt path.
8. **What the FEX-side `SetPixelFormat failed` is.** Independent, downstream of everything here, and it — plus the id Tech 4 x87 assert — is what actually stands between these titles and running.
9. **Why the exception reports `info[0]=00000001` (WRITE)** when `call dword ptr [eax+edx*4]` with `eax=0` is a READ of address 0. The address is right; the access-type bit looks like a box64 fault-synthesis artifact. Minor, unexplained.
