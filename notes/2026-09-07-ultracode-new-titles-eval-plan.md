# Classify 21 newly installed games and produce a prioritized evaluation plan for the DGX Spark log

> **Machine-generated report from a multi-agent workflow run.** Persisted from
> scratch storage so it can be read, cited and *checked* later. Treat every claim
> in it as untrusted until verified locally — this project has published agent
> findings that were wrong, and the synthesis itself flags which of its own claims
> survived adversarial verification and which were refuted.

| | |
|---|---|
| Run date | 2026-09-07 |
| Agents | 8 |
| Tokens | 813,704 |
| Tool calls | 255 |
| classified | 22 |
| high | 10 |

---
# DGX Spark — Evaluation Plan for the 21 Newly Installed Titles

All 21 are already on disk, so "effort" below means **session time and attribution difficulty**, not download cost. The only extra downloads proposed are two Windows depots (Retrocycles, Return to Dark Castle ~89 MB) that turn anecdote into measurement.

---

## 1. Ranked test order (information value per unit effort)

| # | Title | appid | Why it ranks here (one line) |
|---|---|---|---|
| 1 | **HROT** | 824600 | 0 SSE opcodes in 10.5 MB — a modern FPS doing *all* FP on the x87 stack with live control-word changes; either confirms or breaks the log's "id Tech 4's own assertion, not x87 generally" claim, at 0.2 GB. |
| 2 | **Retrocycles** | 1306180 | 8 MB, and the only title that deletes Wine/Proton/DXVK from the diagram entirely: ELF → FEX → GL thunk. Also carries its own Windows depot, so it is both arms of the native-vs-Proton experiment. |
| 3 | **Return to Dark Castle** | 4054940 | Same build available as native-Linux-Vulkan *and* Windows-DX11 for 89 MB — prices the standing "force Proton over native ports" rule, which currently rests on one Feral Vulkan port. First native Vulkan straight at the thunk with no D3D layer. |
| 4 | **Heroes of Hammerwatch II** | 619820 | 0.3 GB buys GL 3.2 core / GLSL 430 with a dedicated bgfx render thread — the first modern-feature-level GL here (everything prior is pre-GL3 fixed function), and ProtonDB Platinum on x86 means any failure is attributable to FEX alone. |
| 5 | **Sentience: The Android's Tale** | 635850 | The cheapest attack on the log's oldest unresolved wound (Chromium GPU process under FEX); fails or passes inside 30 s, and adds V8 JIT-inside-FEX-JIT, which nothing here has ever tested. |
| 6 | **Overlooting** | 3410180 | 0.3 GB adds a whole missing engine family (Godot 4) *and* gives GL 3.3 / native Vulkan / ANGLE→D3D11 on one binary with the adapter string printed to stdout. |
| 7 | **Hawthorn Playtest** | 3763710 | Highest ceiling, highest cost: the only UE5.6-class DX12/SM6 binary with genuinely cooked SM5 shaders, so a fail-on-`-dx12` / pass-on-`-d3d11` is a clean VKD3D isolation. 5.1 GB of shader compilation and an unreleased build are the tax. |
| 8 | **Farm RPG** | 2287550 | The 64-bit Chromium 116 control for #5 — needed because Valve's CEF is also 64-bit, so Sentience alone confounds "Chromium" with "32-bit". Discounted for needing a live server and an account. |
| 9 | **Horse Magnifier** | 4585340 | Second Godot 4 sample on the *other* backend (D3D12→VKD3D), 215 MB, and its markers disagree on disk — which makes reading the startup driver line, not inferring it, the whole exercise. |
| 10 | **LivingBattle** | 3353830 | Only Mono-backend title that is also CPU-bound, so it is the only place a JIT-under-JIT tax can appear as a frametime number instead of a shrug. Game quality muddies attribution. |
| 11 | **Buddy Simulator 1984** | 1269950 | 32-bit Mono JIT under FEX — the log's "Unity OK" row is entirely IL2CPP (AOT) evidence generalised to a backend it never tested. |
| 12 | **Pile Up!** | 2094910 | Worth a slot **only** if the four-way `-force-d3d11/d3d12/vulkan/glcore` harness is actually run; that is the one measurement that prices DXVK vs VKD3D vs raw Vulkan with CPU work held constant. Otherwise it is a duplicate DX11 pass. |
| 13 | **Sledding Game** | 3438850 | The demo's DX11 pass is already logged; the retail build's added D3D12 Agility SDK is the only delta, plus a novel question (app-local `D3D12Core.dll` vs vkd3d-proton's own d3d12). |
| 14 | **King in the Mountain Playtest** | 4962780 | Clean winevulkan probe with a developer-supplied OpenGL control arm, but Godot's Mobile renderer is deliberately conservative, so a pass proves little — and the playtest license may already be dead. |
| 15 | **Narvas** | 640700 | Not for its own sake: it is the 32-bit DX11/DXVK **health check** for batch A, and it fills the GameMaker gap while doing so. |
| 16–21 | Dicefolk, Mini Settlers, YAZD HD, Dokimon, Just Move Fall, Big Walk | — | Controls and fillers. See §5. |

---

## 2. Batching

**Batch A — 32-bit x86 through FEX (one sitting).** Narvas → **HROT** → Buddy Simulator 1984 → Sentience.
Daikatana is currently the *only* 32-bit sample in the log. Run Narvas first as the 32-bit DX11/DXVK health check; if it fails, the batch's problem is the 32-bit path itself and every later result in the sitting is uninterpretable. Then HROT (x87), Buddy Sim (32-bit Mono JIT), Sentience (32-bit Chromium/V8). Check `X87ReducedPrecision` in `~/.fex-emu/Config.json` **before** the first launch — Delphi's `Extended` is genuinely 80-bit, and reduced precision would present as drifting physics, not a crash.

**Batch B — OpenGL without DXVK (one sitting).** Retrocycles → Hammerwatch II → Overlooting (`--rendering-driver opengl3`).
DXVK_HUD is inert for all three; verify **once** at the start of the sitting that MangoHud's GL hook actually attached, or every FPS number in the batch is worthless. Read the adapter/renderer string in each (Retrocycles' in-game System Information, bgfx's GL init, Godot's `--verbose`) — a smooth 2D framerate on llvmpipe is exactly the false pass this log has published before.

**Batch C — Godot 4 family.** Overlooting → Horse Magnifier → King in the Mountain.
Same engine family, three different backends (GL / D3D12→VKD3D / Vulkan→winevulkan). Godot silently auto-falls-back D3D12→Vulkan→GL, so the startup driver line is the result; the framerate is not.

**Batch D — VKD3D vs DXVK on one binary.** Hawthorn (`-dx12` / `-d3d11`) → Sledding Game (`-force-d3d12` / `-force-d3d11`) → Pile Up! four-way.
One sitting because they share a mitigation ladder: read the DXVK/VKD3D banner from the Proton log, and try `VKD3D_DISABLE_EXTENSIONS=VK_EXT_descriptor_buffer` before calling any DX12 death a descriptor-buffer hit. Second run of each arm — an API switch empties the DXVK state cache the same way a Proton switch does.

**Batch E — native ELF under FEX.** Retrocycles + Return to Dark Castle, each against its own Windows depot.
Same session so the native/Proton A/B uses one machine state. `game-run.sh`'s "no compatdata prefix — running natively" warning is *expected and correct* on the native arms.

**Batch F — Mono vs IL2CPP, controlled.** LivingBattle then Dicefolk, back to back, same Proton, second run of each.
Dicefolk's only justification is being the IL2CPP baseline for LivingBattle's Mono frametimes. Run them together or skip Dicefolk.

**Batch G — Chromium under FEX.** Sentience (32-bit) + Farm RPG (64-bit), same sitting.
Neither alone separates "Chromium is broken under FEX" from "Valve's 64-bit CEF build is broken"; the pair does. Launch both only via `game-run.sh` — Chromium spawns a browser/renderer/GPU/crashpad tree and a partial kill orphans children.

---

## 3. Explicit predictions

**HROT** — Expect a clean run through a full level: Daikatana already showed x87 works, and this should make that conclusion strong rather than suggestive. **Surprising:** NaN/INF geometry, an FPU-stack fault, or projectiles/collision that drift over minutes. Drift specifically implicates `X87ReducedPrecision`, not id Tech 4's signature — check the config before writing either up. Separately: expect a **performance** shortfall, and expect `bench-ab.sh` proton_10 vs proton_11 to reproduce the shape of Valve bug #5654; if 11 is much worse than 10, that is an x86-side regression and must not be logged as an ARM cost.

**Retrocycles** — Expect it to launch and the in-game GL renderer string to read `NVIDIA GB10/PCIe` (I take the glxinfo-under-FEX result as the proven base case). **Surprising, and the more valuable outcome:** `llvmpipe`/Mesa in that string, meaning pressure-vessel's lib tree bind-mounted over the thunk's `libGL.so.1` overlay — note `ThunksDB.json` has a hand-added special case for the runtime's pinned `libvulkan` and **none** for libGL. Second prediction: native will be *comparable or better* than the Proton arm here (GL 1.x immediate mode is trivial), which would be the first counterexample to "force Proton over native ports."

**Return to Dark Castle** — Expect the native Vulkan build to launch (no `descriptor_buffer` / `DescriptorSizeEXT` symbols in `UnityPlayer.so`). Falsifiable part: **expect the native build to lose to the Windows/Proton build of the same version**, per the standing rule. **Surprising:** native wins — which would mean the rule is about Feral-style ports specifically, not native Linux builds generally, and CLAUDE.md's guidance needs narrowing. Expect Burst's 484 AVX2 variants to execute correctly; a SIGILL or visibly wrong physics would be the log's first AVX2-under-FEX defect.

**Heroes of Hammerwatch II** — Expect a pass; a black screen on the first attempt is reported on x86 too and is GL context creation, not an ARM finding. **Surprising:** a wedge with threads parked at the bgfx render thread — that is the FEX GL thunk failing on multithreaded submission, a nameable new signature. Do not chase `LoadLibrary("renderdoc.dll")` or `shimloader64.dll` failures; neither file ships and both failures are normal.

**Sentience** — Expect the baseline run to black-screen or lose the GPU process, matching *both* the x86 Silver/SteamOS-Unsupported record and the FEX CEF signature, and expect exactly one of `--single-process`, `--disable-gpu`, `WINEDLLOVERRIDES="libglesv2.dll=d"` to flip it. **Surprising:** a clean hardware-accelerated baseline — that narrows the Steam CEF bug to Valve's build or to 64-bit. Run it under Box64 as well; an identical failure across both JITs means the test is wrong.

**Overlooting** — Expect a pass on the default `gl_compatibility` arm with GB10 in the `--verbose` adapter line. **Surprising:** the line names llvmpipe or an ANGLE/D3D11 device (silent `fallback_to_angle`), or the `--rendering-driver vulkan` arm failing where GL passes. A smooth framerate is *not* evidence here — this is 2D pixel art and would look fine on software GL.

**Hawthorn** — Expect `-d3d11`/SM5 to pass (DXVK sweet spot, visibly degraded — Nanite needs SM6). `-dx12` is genuinely 50/50; expect a brutal first run of shader compilation regardless. **Surprising either way:** a DX12 pass with Nanite+Lumen+MegaLights would be the first UE5.6-class DX12 result in this log; a DX11 failure would contradict its most reliable rule and should be suspected as a playtest-build bug first. `-vulkan` failing is not a stack result — no SPIR-V is cooked.

**Farm RPG** — Expect the GPU process to die in the same class as Steam's own CEF (`exit_code=8704`), recovered by `--disable-gpu`. **Surprising:** clean hardware-accelerated Chromium, which would justify re-testing the `hardware_acceleration_mode.enabled = false` workaround on evidence. FPS is meaningless — log it as pass/fail under the CEF/FEX thread, not in the performance table.

**Horse Magnifier** — Expect the startup line to say `d3d12` and the game to run through VKD3D (720p 2D capped at 60, so no GPU load). **Surprising:** an auto-fallback to Vulkan or OpenGL, i.e. VKD3D refused a device — invisible unless the line is read, and the whole reason to run it.

**LivingBattle** — Expect it to run, and to be slow and hitchy. Falsifiable part: expect the hitching to be **non-stationary and to decay** across a session as Mono's JIT output settles, rather than a flat frametime cost. **Surprising:** frametimes statistically indistinguishable from Dicefolk's IL2CPP profile after warm-up (Mono costs nothing measurable here), or a hard fault inside `mono-2.0-bdwgc`. General jank is not a finding — this game is jank on native Windows.

**Buddy Simulator 1984** — Expect the default D3D11 arm to pass. One correction to the intake note: DXVK **already** drives the 32-bit Vulkan thunk, so `-force-vulkan` tests the game's *direct* winevulkan use, not the thunk's 32-bit ABI in general — its marginal value is smaller than advertised. Expect both arms to pass. **Surprising:** either arm passing while the other fails, which would localise a fault to winevulkan-vs-DXVK at 32-bit.

**Pile Up!** — Expect DX11/DXVK fastest, D3D12/VKD3D within ~10%, `-force-glcore` far worst. **Surprising:** `-force-vulkan` beating DXVK by a wide margin (DXVK overhead dominating on this stack), or `-force-d3d12` silently falling back to DX11 — verify the created device in `Player.log`, do not report a VKD3D number you did not confirm was VKD3D. Also expect `discord_game_sdk.dll` to stall at init against a socket that does not exist; that is not a graphics hang.

**Sledding Game** — Expect `-force-d3d11` to reproduce the already-logged demo result (this is the control). `-force-d3d12` is the experiment; expect it to reach device creation. **Surprising:** vkd3d-proton confused by the exe's `D3D12SDKPath` pointing at a genuine Microsoft `D3D12Core.dll` that cannot run on ARM — undocumented as far as I can tell, and worth watching the log for. Expect `EOSBootstrapper.exe`'s window to close on **success**; check for a many-threaded `Sledding Game.exe` with `watch-run.sh` before calling anything dead.

**King in the Mountain** — Expect a pass, and expect it to prove little: Godot's Mobile renderer is single-pass and subpass-based and does not touch `VK_EXT_descriptor_buffer`. **Surprising:** Vulkan failing while the developer's own `--rendering-driver opengl3` "Safe Mode" entry works — that would localise a winevulkan/thunk fault on a workload too trivial to blame on the GPU. Most likely actual outcome is administrative: an expired playtest license. Verify it starts before planning around it.

*(Demoted from the intake's "medium":)* **Just Move Fall** — expect a pass; its AVX2 probe (46 variants) is strictly weaker than Return to Dark Castle's (484) and LivingBattle's, so it adds nothing unless one of those misbehaves. **Big Walk** — expect a pass; Platinum + Deck Verified, DX11 default, and the co-op-only session requirement makes it expensive for what it returns.

---

## 4. Ready-to-paste README rows

**DX11 — Expected to Work (DXVK sweet spot):**

```markdown
| :star: Buddy Simulator 1984 | DX11 | Unity 2018.2, **Mono**, **32-bit x86** via DXVK. Tests the Mono JIT (runtime codegen, SMC invalidation) on FEX's 32-bit path — prior Unity passes are all IL2CPP/AOT. `-force-vulkan` available. Valve flags it as not exiting cleanly. |
| :star: LivingBattle | DX11 | Unity 2022.3, **Mono**, BiRP + Terrain, native gfx jobs. Only CPU-bound Mono title installed — the one place a JIT-under-JIT tax could show as frametime. Game is poor quality; attribute carefully. |
| :star: Pile Up! | DX11 | Unity 2021.3, Mono. Four-way render-API harness on constant CPU work: `-force-d3d11` / `-force-d3d12` / `-force-vulkan` / `-force-glcore`. Confirm the created device in Player.log. |
| Big Walk | DX11/DX12 | Unity 6.3 IL2CPP, Burst AVX2, EOS + Dissonance voice. DX11 default, DX12 in the API list. Online co-op only — may need a second player. |
| Dicefolk | DX11 | Unity 2022.3 IL2CPP via DXVK. Control run only — the IL2CPP baseline for LivingBattle's Mono frametimes. |
| Dokimon | DX11 | GameMaker Studio 2 C++ VC Runner, x86-64, via DXVK. Watch the intro for the Media Foundation video path. |
| Just Move Fall Dungeon Endless Abyss | DX11 | Unity 2022.3 IL2CPP, Burst AVX2 (46 variants). DX12/Vulkan/GL switches available on the same content. |
| Mini Settlers | DX11 | Unity 2020.3, Mono, DX11-only — no renderer switch. Cheap known-good control run. |
| Narvas | DX11 | GameMaker **VM** runner (interpreted bytecode, not YYC), **32-bit x86** via DXVK. Use as the 32-bit health check before HROT. `options.ini` is engine-owned — snapshot it. |
| Yet Another Zombie Defense HD | DX11 | Unity 2019.4, Mono, via DXVK. UNET matchmaking is dead upstream — an online failure is not a Spark result. |
```

**DX12 — May Work (VKD3D-Proton, mixed results):**

```markdown
| :star: Hawthorn Playtest | DX12/DX11 | UE5.6-class, Nanite/Lumen/MegaLights/VSM. Ships **both** SM6 and SM5 shader archives, so `-dx12` (VKD3D) vs `-d3d11` (DXVK) is a controlled A/B on one binary. Try `VKD3D_DISABLE_EXTENSIONS=VK_EXT_descriptor_buffer` before diagnosing a DX12 death. No Vulkan shaders cooked — `-vulkan` failing is not a stack result. |
| :star: Horse Magnifier | DX12 | Godot 4.7, `rendering_device/driver = d3d12` → VKD3D. Godot silently falls back D3D12→Vulkan→GL; read the startup driver line, do not infer the API. |
| :star: Sledding Game | DX12/DX11 | Unity 6.3 IL2CPP; retail build adds a D3D12 Agility SDK the already-tested demo lacks. `-force-d3d11` is the control, `-force-d3d12` the experiment. Also tests whether an app-local `D3D12Core.dll` confuses vkd3d-proton. EOSBootstrapper closing = success. |
```

**OpenGL / HPL Engine — Uncertain (FEX GL thunks enabled):**

```markdown
| :star: HROT | OpenGL 2.1 | Custom Object Pascal/Delphi engine, **32-bit x86**. Byte-scan found **zero** scalar-SSE opcodes in 10.5 MB — all FP is x87, with live FPU control-word changes (Delphi 80-bit Extended). Sharpest available test of the id Tech 4 x87 boundary. Also first 32-bit Steamworks under FEX. Confounded by Proton bug #5654 — A/B proton_10 vs 11 before quoting FPS. |
| :star: Heroes of Hammerwatch II | OpenGL 3.2 core | bgfx + SDL2; GLSL 430, compute/SSBO, dedicated bgfx render thread. First **modern-feature-level** GL here (all prior GL passes are pre-GL3). Platinum on x86 Linux, so any failure is FEX's. `renderdoc.dll`/`shimloader64.dll` load failures are normal. |
| :star: Overlooting | OpenGL 3.3 core | Godot 4.4, `gl_compatibility`. Adds the Godot 4 family to the matrix. `--verbose` names the adapter — confirm GB10, not llvmpipe or an ANGLE/D3D11 fallback. Also runs `--rendering-driver vulkan` and `opengl3_angle` on identical content. |
```

**Native Vulkan (winevulkan → FEX Vulkan thunk) — new group:**

```markdown
| :star: King in the Mountain Playtest | Vulkan | Godot 4.5 `mobile` renderer → winevulkan, no DXVK/VKD3D anywhere in the path. Dev ships a "Safe Mode" launch entry (`--rendering-driver opengl3`) as a free control arm. Mobile renderer is conservative and does not touch VK_EXT_descriptor_buffer, so a pass is weak evidence. Playtest closed 2026-08-25 — verify the license still works. |
```

**Native Linux x86-64 (no Wine — FEX only) — new group:**

```markdown
| :star: Retrocycles | OpenGL 1.x (SDL 1.2) | Armagetron Advanced 0.2.9.3.0, **native Linux ELF**. Only route here with zero Wine/Proton/DXVK: ELF → FEX → libGL thunk → native ARM64 GL. Tests whether pressure-vessel's lib tree displaces the thunk's libGL overlay — read the in-game System Information renderer string. Windows depot exists, so it is both arms of the native-vs-Proton comparison. 8 MB. |
| :star: Return to Dark Castle | Vulkan (native) | Unity 6.3 IL2CPP, **native Linux ELF**, Vulkan with no D3D layer. Windows depot is 89 MB, so the *same build* can be A/B'd native-under-FEX vs Proton/DXVK — prices the "force Proton over native ports" rule, which currently rests on one Feral port. Burst ships 484 AVX2 job variants. |
```

**Chromium / Electron (CEF-under-FEX thread) — new group; log these under the Steam CEF issue, not the performance table:**

```markdown
| :star: Sentience: The Android's Tale | WebGL→ANGLE→DX11 | RPG Maker MV on NW.js (Chromium 59, **32-bit x86**). Discriminates "Chromium is broken under FEX" from "Valve's CEF build is broken". Also the only V8-JIT-inside-FEX-JIT sample. Bisect one flag at a time: `--single-process`, `--disable-gpu`, `WINEDLLOVERRIDES="libglesv2.dll=d"`, `--in-process-gpu`. ProtonDB Silver / SteamOS Unsupported on x86 — get the x86 control before blaming ARM. |
| :star: Farm RPG | WebGL→ANGLE→DX11 | Electron 26 / Chromium 116, x86-64 — the 64-bit control for Sentience, and architecturally closest to Valve's CEF. Thin shell over farmrpg.com: needs network and an account, and FPS is meaningless. Escalate with `--disable-gpu`, then `--in-process-gpu`, then `--no-sandbox`. |
```

---

## 5. Not worth testing (and why)

- **Dokimon (2019300)** — redundant. Its only claim is filling the GameMaker gap, and **Narvas fills the same gap while also being 32-bit**, which is the axis that actually matters right now. Once Narvas is logged, Dokimon is one more DX11/DXVK green row. Skip unless Narvas fails and you need a second GameMaker sample to tell "GameMaker" from "32-bit".
- **Just Move Fall Dungeon Endless Abyss (3856040)** — its stated probe is Burst AVX2, but Return to Dark Castle carries 484 AVX2 variants and LivingBattle 52; both rank higher on other grounds and will answer the AVX2 question first. 0.6 GB and a session for a third confirmation of Unity IL2CPP on DXVK is not a good trade. Promote it only if RtDC shows an AVX2 anomaly and you need an independent sample.
- **Big Walk (1478500)** — Platinum with 103 reports, Deck Verified, DX11 default. Its interesting half (Burst AVX2, Unity 6.3, EOS, voice capture) is covered better elsewhere, and Steam does not list Single-player, so a meaningful test may need a second human. Highest cost-to-information ratio in the batch.
- **Mini Settlers (2521630) and Yet Another Zombie Defense HD (674750)** — run them only as controls, and log them as one line each. Both are old-Unity DX11-only titles on the log's best-established path; a pass adds nothing and should be written as "routine pass, control run", not as a result. YAZD's `-force-glcore` arm is mildly interesting *only* if run in Batch B alongside Hammerwatch II, as a trivial-workload GL comparison.
- **Dicefolk (1996430)** — no independent value. Engine, version, backend, pipeline, API and dimensionality are all already covered. It is justified **only** as the IL2CPP control run immediately beside LivingBattle's Mono run, on the same Proton with warm caches. If Batch F is not happening, skip it entirely.
- **King in the Mountain (4962780)** — borderline, and I would drop it if time is short: force `--rendering-driver vulkan` on Horse Magnifier instead and get the same winevulkan probe on a title whose license is definitely valid. Its unique asset is the dev's built-in OpenGL "Safe Mode" control arm; that is nice but not worth a session on its own.

**One method note that applies to every row above:** four of these titles (Retrocycles, Hammerwatch II, HROT, Overlooting-GL) have no DXVK anywhere in the path, so `game-run.sh`'s DXVK_HUD is inert by design. A blank HUD there is correct behaviour, not a failed launch — and MangoHud's GL hook is separate from its Vulkan one, so confirm it attached before quoting any number from those runs.
