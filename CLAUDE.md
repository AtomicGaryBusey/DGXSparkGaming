# CLAUDE.md

Guidance for working on this repo. Read this first when continuing DGX Spark gaming testing.

## What this project is

A **living compatibility log** for running Steam / x86-64 PC games on an **NVIDIA DGX Spark
(GB10 Grace-Blackwell, ARM64)**. The entire deliverable is a single file: **`README.md`**.
There is no code — every commit is a documentation edit recording a new test result, a
diagnosis, or a system change. Author/tester identity is **AGB** (AtomicGaryBusey).

Public repo: `https://github.com/AtomicGaryBusey/DGXSparkGaming` (remote `origin`, branch `main`).

## The translation stack (why games pass or fail)

```
Windows game (x86-64 .exe)
  → Proton 10.0 / Wine            (Win32 + DirectX → Linux + Vulkan)
    → DXVK (DX9/10/11) or VKD3D-Proton (DX12)
      → FEX-Emu (or Box64) Vulkan thunk   (x86-64 → ARM64 JIT; GPU calls thunked, not emulated)
        → native ARM64 NVIDIA Vulkan driver → GB10 GPU
```

GPU shaders run **natively**; only CPU-side code is translated. Failures almost always come
from the CPU-translation layer or from Vulkan extensions FEX doesn't thunk — not the GPU.

**The single most useful predictor:** DX9/10/11 games (via DXVK) are the reliable sweet
spot. Native-Vulkan and DX12 (via VKD3D) are hit-or-miss depending on which Vulkan
extensions they touch. Use **Proton 10.0 stable**, not Experimental.

## Recurring failure signatures (cite these when diagnosing)

- **`vkGetPhysicalDeviceDescriptorSizeEXT` unthunked** — `VK_EXT_descriptor_buffer` gap in
  FEX. Crashes at/just after launch. Seen in No Man's Sky, Halo Infinite, Elden Ring.
- **id Tech 4 x87 FPU stack validation** — DOOM 3, BFG, Prey (2006) crash on map load
  ("FPU stack is not empty"). All id Tech 4 broken under FEX. id Tech 3 and 6+ are fine.
- **Rockstar/FPU float exceptions** — RDR2 hits `EXCEPTION_FLT_INVALID_OPERATION` on world
  load. Watch whether other Rockstar/RAGE titles share it.
- **Ubisoft Connect launcher** — crashes outright; blocks all Far Cry titles even though the
  Dunia engine itself runs when the .exe is launched directly.
- **RTX Remix dual-process IPC** — HL2 RTX, any Remix title: 32-bit↔64-bit shared-memory
  bridge breaks under translation.
- **Wave64-only AMD shaders** — Black Myth: Wukong requires `WaveSize(64)`; NVIDIA is
  Wave32-only, VKD3D correctly rejects. Not an ARM issue.
- **Native Linux Vulkan ports** — often far slower than going through Proton (Shadow of the
  Tomb Raider: ~1 FPS native vs. great via VKD3D). Force Proton over native ports.

Harmless noise: pressure-vessel `nvidia_layers.json` warnings; Steam UI showing `llvmpipe`
(the UI runs under FEX; games see the real GPU via DXVK+NVAPI).

## How to add a test result (conventions)

`README.md` section order, roughly: Status → System Info → Architecture → Setup Steps →
Compatibility Guidelines → **Tested by AGB** → Community-Reported → Likely to Work → Known
Issues → Compatibility Test Plan → Installed-Not-Yet-Tested (grouped by API) → Downloading →
Known Not to Launch → other-clients / native-ARM64 / display / resources.

When a game is tested, **move it** from its "Installed — Not Yet Tested" / "Likely to Work"
list into the right destination:

- **Works** → add a row to the **Tested by AGB** table (keep it alphabetical by game name):
  `| **Game** | API | Performance | Notes |`
  - *API*: the actual render path used (DX11, DX12, Vulkan, DX9, OpenGL, KEX, DOS…).
  - *Performance*: terse verdict — e.g. "Smooth, maxed, 5120x1440" or "Playable, 25-30 FPS".
  - *Notes*: engine + translation path (e.g. "Source 2 via DXVK"), launch options, caveats.
    Prefix unresolved follow-ups with **`TODO:`** so they're greppable.
- **Fails** → add a row to **Known Issues** with the root-cause diagnosis, not just "crashes".
  Tie it to one of the failure signatures above when it matches.

Keep the prose terse and factual, matching existing rows. Record *why*, not just *what* —
the diagnostic narrative (which Vulkan call, which engine subsystem) is the point of this log.

## Common requests & how to handle them

- **"Add a result for <game>"** — ask the user for the observed behavior (FPS, settings,
  resolution, launch options, crash point) unless they supplied it; identify engine + render
  path; place the row in the correct table; match an existing failure signature if it crashed.
- **"What should I test next?"** — the `:star:` entries in Installed-Not-Yet-Tested are
  high-priority (they probe a specific engine/API hypothesis). The id Tech family and
  Rockstar-FPU questions are the most scientifically interesting open threads.
- **System changed** — keep the **Status** table and **System Info** block current. Kernel
  (`uname -r`) and driver (`/proc/driver/nvidia/version`) are host-accurate even from a
  sandboxed shell; Steam-library/box64/FEX paths may not be visible from the agent sandbox —
  ask the user to run probes with the `! <command>` prefix if you need live host state.

## Git / committing

Commit only when asked. Match the existing terse, result-oriented message style, e.g.:
`Add <Game> — <one-line outcome>` or `Add <N> games, <what changed>`. Already on `main`;
this is a personal log, so committing directly to `main` is the established pattern. Push is
to a **public** GitHub repo — confirm before pushing.
