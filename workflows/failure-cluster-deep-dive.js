export const meta = {
  name: 'failure-cluster-deep-dive',
  description: 'Deep research into each DGX Spark failure cluster: existing fixes, or concrete paths to modify the blocking component',
  phases: [
    { title: 'Recon', detail: 'one deep dive per failure cluster' },
    { title: 'Verify', detail: 'adversarially test the strongest claims against this stack' },
    { title: 'Synthesize', detail: 'cross-cluster ranked plan' },
  ],
}

const PLATFORM = `
RIG (measured): NVIDIA DGX Spark class, GB10 Grace-Blackwell, ARM64 Cortex-X925/A725 — these cores
have NO 32-bit ARM support, so ALL x86 goes through translation. Driver 580.173.02 (open kernel),
kernel 6.17.0-1032-nvidia, Vulkan 1.4.312. FEX-Emu 2607/2608 (PPA), Box64 v0.4.4, Proton
Experimental / 11.0 x86-64 / 10.0-4b. Steam itself runs under FEX. 20 CPU cores, ~93 GB usable
GPU memory (unified), 334 GB disk free.

STACK: Windows game -> Proton/Wine -> DXVK (DX9/10/11) or VKD3D-Proton (DX12) -> FEX x86-64->ARM64
JIT (GPU calls THUNKED, not emulated) -> native ARM64 NVIDIA Vulkan driver. GPU shaders run
natively; only CPU-side code is translated.

WHAT THIS PROJECT CAN ACTUALLY DO (do not propose things outside this, and do not shy from things
inside it):
- Cross-compile Windows PE binaries on ARM64: clang-20 + xwin (MSVC CRT/SDK) + lld-link. Already
  built a 29 MB DLL (OptiScaler, 199 sources) and Windows EXEs this way, no MSBuild, no sudo.
- Build large C++ projects from source without sudo (cmake 3.28, g++ 13.3, 20 cores, no ninja).
- Build FEX-Emu or Box64 from source into a local prefix.
- Run Windows PEs under Wine/Proton via FEX, and native x86-64 ELF under FEX directly.
- Patch binaries, write LD_PRELOAD / DLL shims, write Vulkan layers.
- sudo requires a human at the keyboard (password) — propose it only when truly needed.

RULES THAT CONSTRAIN A GOOD ANSWER (this log has been burned by each):
- A negative from a query is only as good as the name you guessed. Cross-check negatives by
  searching alternative names. "GB10 is pinned to driver 580" was published twice and was FALSE
  because NVIDIA had renamed the metapackage.
- Secondary reporting of a changelog is NOT evidence. Read the commit/issue.
- Never report a metric you have not verified measures what you think. A headline was published
  from a GENERIC hook counter that measured a different feature entirely.
- Prefer official sources; never leaked or Discord-distributed binaries.
- THE BEST FINDING OF THE LAST DIVE was that the failing component already PRINTS its own
  diagnostic and nobody had ever read it (id Tech 4 prints the x87 tag word one line before it
  dies). Look hard for existing logs, debug env vars, validation layers and verbose modes before
  proposing anything be built.
`

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          claim: { type: 'string' },
          evidence: { type: 'string', description: 'URLs, commit hashes, issue numbers, file:line, version numbers' },
          appliesHere: { type: 'string' },
          actionable: { type: 'string', description: 'concrete command/step sequence for THIS rig' },
          kind: { type: 'string', enum: ['existing-fix', 'config-change', 'source-patch', 'diagnostic', 'dead-end'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['title', 'claim', 'evidence', 'appliesHere', 'actionable', 'kind', 'confidence'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT = {
  type: 'object',
  properties: {
    survives: { type: 'boolean' },
    why: { type: 'string' },
    correction: { type: 'string' },
    effort: { type: 'string', enum: ['trivial', 'hours', 'days', 'weeks', 'infeasible'] },
    probability: { type: 'string', enum: ['high', 'medium', 'low'] },
    falsifiableTest: { type: 'string' },
  },
  required: ['survives', 'why', 'effort', 'probability', 'falsifiableTest'],
}

const CLUSTERS = [
  {
    key: 'vulkan-ext',
    verify: 3,
    prompt: `CLUSTER 1 — VULKAN EXTENSION GAPS IN FEX. This is the biggest single game-killer here.

SYMPTOM: \`vkGetPhysicalDeviceDescriptorSizeEXT\` is unthunked in FEX. Games using
VK_EXT_descriptor_buffer crash at or shortly after launch. Confirmed dead: No Man's Sky (crashes
~16s in, never renders a frame; \`-force d3d11\` does not help because it still probes Vulkan
extensions), Halo Infinite (crashes at launch), Elden Ring. All DX12-via-VKD3D-Proton.
Reproduced on both Proton 10.0 and Experimental.

INVESTIGATE:
- FEX's Vulkan thunking architecture: how the guest/host thunk libs are generated
  (\`/usr/share/fex-emu/GuestThunks\`, \`/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks\`,
  ThunksDB.json). How is the function list produced — hand-written, or generated from vk.xml?
  What EXACTLY has to change to add a missing entry point? Is it a codegen input file?
- Has upstream FEX already fixed descriptor_buffer? Search issues/PRs/commits by BOTH the
  extension name and the function name. Check what shipped after 2607/2608.
- Can VKD3D-Proton be told not to use it? Investigate \`VKD3D_DISABLE_EXTENSIONS\`,
  \`VKD3D_CONFIG\`, \`VKD3D_FEATURE_LEVEL\` and whether descriptor buffer is optional in
  vkd3d-proton or load-bearing for its descriptor heap implementation.
- Would a Vulkan layer that hides VK_EXT_descriptor_buffer from the app work, and where would it
  sit given the thunk boundary?
- Is there a diagnostic already available — FEX thunk logging, VK_LOADER_DEBUG, validation layers,
  \`VKD3D_DEBUG\`, \`PROTON_LOG\` — that names the missing entry point precisely?`,
  },
  {
    key: 'cpu-semantics',
    verify: 2,
    prompt: `CLUSTER 2 — CPU SEMANTICS THE TRANSLATOR GETS SUBTLY WRONG (excluding x87, already covered).

SYMPTOMS, three distinct games asking "what CPU am I on?" and getting an answer FEX did not intend:
- Red Dead Redemption 2 (RAGE engine): reaches the main menu on the Vulkan renderer, then dies with
  \`EXCEPTION_FLT_INVALID_OPERATION\` (0xc0000090) during world load. DX12 mode fails earlier at the
  launcher. Freezes when changing graphics settings. Requires Proton Experimental.
- Burnout Paradise: The Ultimate Box (DX9): refuses to launch, error dialog "This machine does not
  support the SSE2 Command Set." FEX fully supports SSE2 — the game's CPUID probe is getting an
  answer it rejects.
- (context) id Tech 4's x87 assertion is a separate, already-investigated cluster.

INVESTIGATE:
- FEX's CPUID emulation: which leaves/bits are reported, is there a config to change the reported
  CPU, and are there known games broken by the CPUID answer? Look for FEX issues about CPUID,
  vendor string, feature bits, and specifically about Burnout Paradise or EA/Criterion titles.
- x86 floating-point EXCEPTION semantics under FEX: MXCSR exception masks, unmasked FP exceptions,
  denormals-are-zero / flush-to-zero, and how SIGFPE maps to Windows
  EXCEPTION_FLT_INVALID_OPERATION through Wine. Is FEX known to differ from real hardware in which
  FP exceptions are raised or masked? Is there a knob?
- Does Box64 behave differently on either title? Both runtimes are installed here.
- Any existing diagnostic: does RAGE log an FPU/exception reason anywhere; does Burnout name the
  failing CPUID leaf; does Wine log the exception with a faulting instruction?`,
  },
  {
    key: 'launchers',
    verify: 2,
    prompt: `CLUSTER 3 — LAUNCHERS AND MIDDLEWARE, WHERE THE ENGINE IS FINE AND THE WRAPPER IS NOT.

SYMPTOMS:
- Ubisoft Connect crashes with an unrecoverable error, blocking ALL Far Cry titles (FC3, Blood
  Dragon, 4, 5, Primal, New Dawn, 6) on both Proton 10.0 and Experimental, online and offline.
  Crucially the ENGINE IS FINE: launching \`fc3_blooddragon_d3d11.exe\` directly bypasses the
  launcher and the DX11 renderer works — the game runs, but a forced online server check blocks
  progression, resolution defaults wrong, and audio loops during Bink sequences.
- EasyAntiCheat: NBA 2K27 fails with \`Launcher finished with: 210, 'Unexpected error. (#1)'\`.
  Notably Linux EAC IS enabled for that title — the bootstrapper correctly reports
  \`System name: 'linux64'\`, downloads the Linux EAC module from Epic's CDN (HTTP 200, 9,622,837
  bytes), then dies 32 s into \`Starting Wine module mapping, Wine version: 11.0\`.
- Rockstar Launcher cannot start under Proton 10.0 (works on Experimental).
- (solved, as precedent) REDprelauncher for Cyberpunk 2077 is a Qt+CEF app that failed ~10
  consecutive hand-offs; it was replaced with a 10 KB shim EXE that CreateProcessW's the game
  directly and waits on it. That pattern may generalise.

INVESTIGATE:
- Ubisoft Connect: what exactly fails under Wine/Proton on ARM? Is there a known Proton fix,
  a \`-uplay_steam_mode\` style flag, an offline mode, a compatibility tool (Luxtorpeda / Heroic /
  Lutris scripts), or a community patch? Is the "forced online server check" defeatable legitimately
  (the user OWNS these games)?
- EAC: is the Linux EAC module x86-64 ELF, and is the failure at 'Wine module mapping' a known
  incompatibility with translated/JIT environments? Any reports of EAC working under FEX/Box64/
  Rosetta/Prism anywhere at all?
- Does the shim pattern (replace launcher exe with a tiny launcher-of-the-real-exe) generalise to
  Ubisoft Connect titles, and what breaks when it does (achievements, saves, DRM, online)?`,
  },
  {
    key: 'ipc-multiprocess',
    verify: 2,
    prompt: `CLUSTER 4 — MULTI-PROCESS AND IPC ARCHITECTURES, STRUCTURALLY HOSTILE TO TRANSLATION.

SYMPTOMS:
- RTX Remix (Half-Life 2 RTX, any Remix title): 32-bit<->64-bit shared-memory bridge breaks.
  Under FEX: access violation 0xc0000005 in NvRemixBridge.exe during CreateDevice. Under Box64:
  gets FURTHER — device creates, draw calls flow — then deadlocks on a Present semaphore
  (cross-process sync failure between the 32-bit client and 64-bit server). Two independent
  runtimes, two different failure points, same architecture.
- Chromium/CEF: Steam's own UI must run with hardware acceleration DISABLED or the renderer dies on
  first paint of uncached content. The game Properties dialog crashes the client outright. This is
  JIT (V8) inside JIT (FEX), plus sandboxing/seccomp, plus a multi-process browser.
- Dark Souls: Prepare to Die Edition: GStreamer deadlock in Wine's media pipeline during the intro
  video — "Trying to join task from its thread would deadlock".

INVESTIGATE:
- Cross-process shared memory and futex/semaphore semantics under FEX: are there known issues with
  cross-process synchronisation, memory ordering (FEX has TSOEnabled=1 here), or 32<->64-bit
  interop? Is Remix's bridge documented anywhere, and has anyone run it on ARM?
- Chromium under FEX/Rosetta/Prism: what specifically breaks in the GPU process, and are there
  Chromium switches (--disable-gpu-sandbox, --no-zygote, --single-process,
  --disable-features=...) that are known to make CEF survive translation? Does Valve's own
  steamwebhelper accept flags via a config file here?
- The GStreamer deadlock: is it a known Wine bug with a fix, or a Proton media-foundation setting
  (\`PROTON_USE_WINED3D\`, \`WINE_DISABLE_MEDIA\`, removing the video files)?
- Is TSOEnabled / VectorTSOEnabled relevant to any of these, and what is the cost of changing it?`,
  },
  {
    key: 'not-arm',
    verify: 1,
    prompt: `CLUSTER 5 — FAILURES THAT ARE NOT ABOUT ARM AT ALL, but still block the user's games.

SYMPTOMS:
- Black Myth: Wukong (DX12/UE5): crashes ~50s in during level load. Root cause established: the
  game ships AMD-optimised compute shaders that hard-require \`WaveSize(64)\` with no Wave32
  fallback. NVIDIA GPUs are Wave32-only (subgroup size 32), and VKD3D-Proton CORRECTLY rejects the
  pipeline: "Required WaveSize range [64, 64], but supported range is [32, 32]". This would fail
  identically on an x86 RTX 4090 — it is not an ARM or FEX issue.
- Dark Souls III (DX11 via DXVK): launches, renders the intro cutscene, crashes to desktop at the
  cutscene-to-gameplay transition every time. Happens whether skipping or watching, and with movie
  files removed. No crash dump, no Vulkan extension error, silent exit. Surprising because Sekiro
  (same studio, same API) works flawlessly. Cause NOT established.

INVESTIGATE:
- Wave64 on Wave32 hardware: is there ANY path? A vkd3d-proton workaround or config, a DXIL/SPIR-V
  shader-replacement approach, subgroup-size-control extensions
  (VK_EXT_subgroup_size_control / requiredSubgroupSize), a community shader patch for Wukong
  specifically, or an NVIDIA driver capability. Has anyone made Wukong run on NVIDIA under
  Proton at all? Be rigorous — this is widely misunderstood online.
- Dark Souls III: what actually causes the cutscene-to-gameplay crash under Proton? Search
  ProtonDB, Wine bugs, and community fixes. Is it DS3 specifically, or a known
  Bink/Sekiro-vs-DS3 difference? Is there a documented fix (dsfix, launch option, Proton version,
  disabling a specific feature)?`,
  },
]

phase('Recon')
const perCluster = await pipeline(
  CLUSTERS,
  (c) => agent(`${PLATFORM}\n\n${c.prompt}\n\nReturn concrete findings. Mark dead ends as kind="dead-end" — ruling something out is valuable and prevents it being re-tried. Prefer a diagnostic that already exists over anything that must be built.`,
    { label: `recon:${c.key}`, phase: 'Recon', schema: FINDINGS }),
  (res, c) => {
    const items = (res && res.findings) ? res.findings : []
    const top = items.filter((f) => f.kind !== 'dead-end').slice(0, c.verify)
    if (!top.length) return []
    return parallel(top.map((f) => () =>
      agent(
        `${PLATFORM}\n\nAdversarially verify. Default to survives=false if you cannot confirm it.\n\n` +
        `CLUSTER: ${c.key}\nTITLE: ${f.title}\nCLAIM: ${f.claim}\nEVIDENCE OFFERED: ${f.evidence}\n` +
        `RELEVANCE CLAIMED: ${f.appliesHere}\nPROPOSED ACTION: ${f.actionable}\n\n` +
        `Does the cited source actually say this? Is the version current relative to FEX 2607/2608, ` +
        `Proton Experimental, driver 580.173.02, vkd3d-proton 3.0a, DXVK 2.7.1? Does it apply to ` +
        `ARM64 + FEX specifically or only to x86 Linux? If the claim is a NEGATIVE, try hard to ` +
        `falsify it by searching alternative names. Give ONE concrete falsifiable test runnable on ` +
        `this rig.`,
        { label: `verify:${c.key}:${f.title.slice(0, 24)}`, phase: 'Verify', schema: VERDICT }
      ).then((v) => ({ cluster: c.key, finding: f, verdict: v }))
    ))
  }
)

const all = perCluster.flat().filter(Boolean)
const survived = all.filter((x) => x.verdict && x.verdict.survives)
const refuted = all.filter((x) => x.verdict && !x.verdict.survives)
log(`verified ${all.length}: ${survived.length} survived, ${refuted.length} refuted`)

phase('Synthesize')
const plan = await agent(
  `${PLATFORM}

Cross-cluster synthesis for a rigorous engineering log. The x87/id Tech 4 cluster was covered in a
previous dive and is EXCLUDED here.

SURVIVED VERIFICATION:
${JSON.stringify(survived.map((x) => ({ cluster: x.cluster, ...x.finding, verdict: x.verdict })), null, 1)}

REFUTED:
${JSON.stringify(refuted.map((x) => ({ cluster: x.cluster, title: x.finding.title, claim: x.finding.claim, why: x.verdict.why, correction: x.verdict.correction })), null, 1)}

Write:

1. **One ranked table across ALL clusters**, by (games unblocked x probability) / effort. Include the
   cluster, what would change, effort, probability, and the first concrete experiment. The single
   unthunked Vulkan function blocks three AAA titles — weight breadth accordingly, but do not
   inflate a low-probability fix just because its payoff is large.

2. **The three cheapest experiments overall**, each written as a runnable command sequence for this
   rig, each with the result that would KILL the idea. Prefer ones that read an existing diagnostic
   over ones that build something.

3. **Dead ends**, with the reason, so nobody re-treads them. Include anything refuted above.

4. **What is genuinely unknown** — stated as unknown, not glossed.

5. **One paragraph on which cluster is the best use of the next full day of work, and why.**

Be concrete: file paths, config keys, env vars, commit hashes, commands, version numbers. Do not pad.`,
  { label: 'synthesize:cross-cluster', phase: 'Synthesize' }
)

return { verified: all.length, survived: survived.length, refuted: refuted.length, plan }
