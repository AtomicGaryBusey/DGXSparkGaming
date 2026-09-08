export const meta = {
  name: 'prep-new-games',
  description: 'Classify 21 newly installed games and produce a prioritized evaluation plan for the DGX Spark log',
  phases: [
    { title: 'Classify', detail: 'engine, render API, and which stack hypothesis each probes' },
    { title: 'Plan', detail: 'ranked test order + ready-to-paste README entries' },
  ],
}

const CONTEXT = `
RIG: NVIDIA DGX Spark / GB10 Grace-Blackwell, ARM64 (Cortex-X925/A725 — NO 32-bit ARM support,
so ALL x86 goes through translation). FEX-Emu 2607/2608, Box64 v0.4.4, Proton Experimental /
11.0 x86-64, driver 580.173.02. Steam itself runs under FEX.

TRANSLATION STACK: Windows game -> Proton/Wine -> DXVK (DX9/10/11) or VKD3D-Proton (DX12)
-> FEX-Emu x86-64->ARM64 JIT (GPU calls thunked, not emulated) -> native ARM64 NVIDIA Vulkan.
GPU shaders run natively; only CPU-side code is translated.

WHAT THIS LOG ALREADY KNOWS (do not re-derive, use it):
- DX9/10/11 via DXVK is the reliable sweet spot. Native-Vulkan and DX12 via VKD3D are
  hit-or-miss depending on which Vulkan extensions are touched.
- KNOWN FAILURE SIGNATURES: vkGetPhysicalDeviceDescriptorSizeEXT unthunked in FEX
  (VK_EXT_descriptor_buffer gap — killed No Man's Sky, Halo Infinite, Elden Ring);
  id Tech 4's per-frame x87 FPU assertion (DOOM 3, BFG, Prey); Rockstar/RAGE
  EXCEPTION_FLT_INVALID_OPERATION; Ubisoft Connect launcher; RTX Remix dual-process IPC;
  Wave64-only AMD shaders; EasyAntiCheat fails at Wine module mapping.
- Engine matrix: id Tech 2 OK, 3 OK, 4 BROKEN, 6+ OK. Source/Source 2 OK. Unity (incl. IL2CPP)
  OK. UE5 varies with the Vulkan extensions used.
- 32-bit x86 titles run through FEX's 32-bit path and DO work: Daikatana (id Tech 2, OpenGL)
  was excellent. That path is under-tested here and worth probing.
- Old GameMaker/LOVE2D/Godot 2D titles are usually trivial passes and are LOW information value
  unless they break — say so honestly rather than inflating their priority.

LOCAL FINGERPRINTS (measured on disk just now — treat as ground truth):
`

const BATCHES = [
  { key: 'b1', games: `
3763710 Hawthorn Playtest — Unreal, x86-64, 5.1GB
1478500 Big Walk — Unity, x86-64, 3.5GB
2521630 Mini Settlers — Unity, x86-64, 0.9GB` },
  { key: 'b2', games: `
3438850 Sledding Game — Unity, x86-64, 0.9GB
619820 Heroes of Hammerwatch II — custom engine (+FMOD), x86-64, 0.3GB
674750 Yet Another Zombie Defense HD — Unity, x86-64, 0.3GB` },
  { key: 'b3', games: `
3410180 Overlooting — engine UNIDENTIFIED, x86-64, 0.3GB
1996430 Dicefolk — Unity, x86-64, 0.4GB
3353830 LivingBattle — Unity, x86-64, 0.7GB` },
  { key: 'b4', games: `
2287550 Farm RPG — engine UNIDENTIFIED, x86-64, 0.2GB
4585340 Horse Magnifier — engine UNIDENTIFIED, x86-64, 0.2GB
4962780 King in the Mountain Playtest — engine UNIDENTIFIED, x86-64, 0.1GB` },
  { key: 'b5', games: `
2019300 Dokimon — GameMaker, x86-64, 0.1GB
1306180 Retrocycles — engine UNIDENTIFIED, arch UNIDENTIFIED, 0.05GB
3856040 Just Move Fall Dungeon Endless Abyss — Unity, x86-64, 0.6GB` },
  { key: 'b6', games: `
635850 Sentience: The Android's Tale — engine UNIDENTIFIED, **32-bit x86**, 0.5GB
1269950 Buddy Simulator 1984 — Unity, **32-bit x86**, 0.3GB
640700 Narvas — GameMaker, **32-bit x86**, 0.4GB` },
  { key: 'b7', games: `
4054940 Return to Dark Castle — Unity, arch UNIDENTIFIED, 0.3GB
824600 HROT — engine UNIDENTIFIED, **32-bit x86**, 0.2GB
2094910 Pile Up! — Unity, x86-64, 0.8GB` },
]

const GAMES = {
  type: 'object',
  properties: {
    games: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          appid: { type: 'string' },
          name: { type: 'string' },
          engine: { type: 'string', description: 'specific: Unity 6 IL2CPP, UE5.4, GameMaker, custom, etc.' },
          renderApi: { type: 'string', description: 'DX11 / DX12 / Vulkan / OpenGL / DX9 — and how you know' },
          bitness: { type: 'string' },
          protonStatus: { type: 'string', description: 'ProtonDB/Linux status if known, or "unknown"' },
          probes: { type: 'string', description: 'which stack hypothesis this title tests, or "none - routine pass expected"' },
          risk: { type: 'string', description: 'which known failure signature it might hit, if any' },
          priority: { type: 'string', enum: ['high', 'medium', 'low'] },
          priorityWhy: { type: 'string' },
          launchNotes: { type: 'string', description: 'launch options, renderer flags, or setup this title is known to need' },
        },
        required: ['appid', 'name', 'engine', 'renderApi', 'bitness', 'probes', 'risk', 'priority', 'priorityWhy'],
      },
    },
  },
  required: ['games'],
}

phase('Classify')
const results = await parallel(BATCHES.map((b) => () =>
  agent(
    `${CONTEXT}${b.games}

For EACH of the three titles above, determine: the specific engine and version, the render API it
actually uses on Windows (and whether it offers a Vulkan/OpenGL/DX11 switch), bitness, its known
Linux/Proton status, and — the important part — WHICH HYPOTHESIS ABOUT THIS TRANSLATION STACK IT
PROBES. A game that is simply expected to work is low priority and you should say so plainly;
this log values titles that discriminate between failure modes.

Flag specifically if a title is likely to hit a KNOWN failure signature listed above, or if it
exercises something under-tested here: the 32-bit FEX path, native Vulkan, DX12/VKD3D, an
unusual launcher, anti-cheat, or an engine family not yet in the matrix.

Where the engine is UNIDENTIFIED above, work it out from public sources. Where you cannot,
say "unknown" rather than guessing — a wrong engine attribution would poison the log.`,
    { label: `classify:${b.key}`, phase: 'Classify', schema: GAMES }
  )
))

const all = results.filter(Boolean).flatMap((r) => r.games || [])
log(`classified ${all.length} titles`)
const high = all.filter((g) => g.priority === 'high')
log(`${high.length} high-priority, ${all.filter((g) => g.priority === 'medium').length} medium, ${all.filter((g) => g.priority === 'low').length} low`)

phase('Plan')
const plan = await agent(
  `${CONTEXT}

All 21 newly installed titles, classified:
${JSON.stringify(all, null, 1)}

Write the evaluation plan for this project's log. Produce, in order:

1. **A ranked test order.** Rank by INFORMATION VALUE per unit of effort, not by how fun the game
   is. A title that discriminates between two failure hypotheses beats five that are expected to
   pass. State the ranking rationale in one line each.

2. **Batching.** Group titles that can be tested in one sitting because they probe the same thing
   (e.g. all the 32-bit ones together, since the 32-bit FEX path was only just validated by
   Daikatana and one more data point either confirms or breaks that).

3. **Explicit predictions.** For each high and medium priority title, state what you EXPECT to
   happen and what result would be surprising. A prediction that cannot fail is not a prediction.

4. **Ready-to-paste README rows** for the "Installed — Not Yet Tested" section, grouped by render
   API, matching this repo's existing style: terse, factual, engine + render path, with a
   :star: prefix on the entries that probe a specific hypothesis.

5. **Anything you would NOT bother testing**, and why. Be willing to say a title is low value.

Be concise and concrete. Do not pad the list to look thorough.`,
  { label: 'plan:evaluation-order', phase: 'Plan' }
)

return { classified: all.length, high: high.length, plan }
