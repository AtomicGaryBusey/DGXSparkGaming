export const meta = {
  name: 'idtech4-x87-unblock',
  description: 'Find existing solutions or concrete modification paths to run id Tech 4 (x87) games on DGX Spark ARM64/FEX',
  phases: [
    { title: 'Recon', detail: 'six independent angles on the x87 blocker' },
    { title: 'Verify', detail: 'adversarially test each candidate against THIS stack' },
    { title: 'Synthesize', detail: 'ranked, falsifiable action plan' },
  ],
}

const CONTEXT = `
PLATFORM (measured, not assumed):
- NVIDIA DGX Spark / HP ZGX Nano G1n, GB10 Grace-Blackwell, ARM64 (Cortex-X925/A725).
  These cores have NO 32-bit ARM support at all, so all x86 goes through translation.
- FEX-Emu 2607/2608 (PPA). Live FEX Config.json includes "X87ReducedPrecision":"0".
- Box64 v0.4.4 (Dynarec, armv9.2-a). Proton Experimental / 11.0 x86-64. Steam under FEX.
- NVIDIA driver 580.173.02, kernel 6.17.0-1032-nvidia.

THE BLOCKER (recorded in this project's log):
- DOOM 3 (32-bit x86 OpenGL, runs via BOX32 mode): launches, initialises OpenGL ARB2
  renderer, loads to menu, then CRASHES ON MAP LOAD. Engine's own FPU state check fails:
  "the FPU stack is not empty at the end of the frame".
- DOOM 3 BFG Edition (64-bit OpenGL, id Tech 4 remaster): same FPU stack check crash.
  Notably the FPU values were observed CLEAN (all zeros) and the engine still bails.
- Prey (2006) (id Tech 4 variant, Human Head): same x87 FPU stack crash.
- Engine matrix on this rig: id Tech 2 OK (Daikatana, 32-bit x86 OpenGL, excellent),
  id Tech 3 OK, id Tech 4 BROKEN, id Tech 6+ OK (DOOM 2016, Eternal, Q2 RTX all fine).
  So this is id Tech 4's own per-frame x87 assertion, NOT general x87 breakage under FEX.
- id Tech 4 was GPL-released by id Software in 2011. DOOM 3 BFG source also released.

PROJECT RULES THAT CONSTRAIN ANY ANSWER:
- Claims must be verifiable. A negative from a query is only as good as the name guessed;
  cross-check. Secondary reporting of a changelog is NOT evidence.
- Prefer official sources; never leaked/Discord-distributed binaries.
- The user owns the games on Steam and wants them PLAYABLE, ideally with Steam assets.
- Custom software, patches and source builds are explicitly in scope (this repo already
  cross-compiles Windows PE binaries on ARM64 with clang-20 + xwin + lld, and builds
  large C++ projects from source without sudo).
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
          claim: { type: 'string', description: 'the specific factual claim, one sentence' },
          evidence: { type: 'string', description: 'URLs, repo paths, file/function names, version numbers, issue numbers' },
          appliesHere: { type: 'string', description: 'why this does or does not apply to GB10 + FEX + Proton + Steam assets' },
          actionable: { type: 'string', description: 'the concrete next step a person could run' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['title', 'claim', 'evidence', 'appliesHere', 'actionable', 'confidence'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT = {
  type: 'object',
  properties: {
    survives: { type: 'boolean', description: 'true if the claim withstands adversarial checking' },
    why: { type: 'string' },
    correction: { type: 'string', description: 'what is actually true, if the claim was wrong or overstated' },
    effort: { type: 'string', enum: ['trivial', 'hours', 'days', 'weeks', 'infeasible'] },
    falsifiableTest: { type: 'string', description: 'a single concrete experiment that would confirm or kill this' },
  },
  required: ['survives', 'why', 'effort', 'falsifiableTest'],
}

const DIMENSIONS = [
  {
    key: 'fex-x87',
    prompt: `${CONTEXT}
ANGLE: FEX-Emu's x87 implementation.
Investigate how FEX emulates the x87 FPU stack: the register file, tag word, FSW/FCW handling,
FXSAVE/FXRSTOR, and precision. What EXACTLY does "X87ReducedPrecision" change, and would setting
it to 1 (or 0) affect an engine that inspects the x87 tag word / stack-empty state? Find FEX
GitHub issues, PRs, commits and docs mentioning DOOM 3, id Tech 4, "FPU stack", x87 tag word,
fnstenv/fnsave, or games that check FPU state. Note FEX's own known-issue lists. Be specific
about version numbers and whether fixes landed after FEX-2607/2608.`,
  },
  {
    key: 'box64-x87',
    prompt: `${CONTEXT}
ANGLE: Box64 (and BOX32) x87 emulation, as an ALTERNATIVE runtime to FEX for these titles.
How does Box64 implement x87 (including its tag word and stack-empty semantics)? Are there
Box64 env knobs (BOX64_X87_NO80BITS, BOX64_DYNAREC_X87DOUBLE, BOX64_DYNAREC_FASTROUND etc.)
that change FPU-state fidelity? Search Box64's issue tracker, wiki and commit log for DOOM 3,
Prey, id Tech 4, "FPU stack is not empty". Has anyone run DOOM 3 or Prey under Box64 on ARM64
(Raspberry Pi, Asahi, Snapdragon X, Android) successfully, and with what settings?`,
  },
  {
    key: 'idtech4-source',
    prompt: `${CONTEXT}
ANGLE: the id Tech 4 GPL source itself — find the exact assertion and how to defeat it.
id Tech 4 (DOOM 3) and DOOM 3 BFG are GPL. Locate the precise function and file that produces
"FPU stack is not empty" (look for Sys_FPU_StackIsEmpty, Sys_FPU_GetState, idMath, win_shared.cpp,
sys_public.h, and the equivalent in the Linux/POSIX backend). Quote the actual assertion code and
say what it inspects (tag word bits? FSW top? inline asm fnstenv?). Then enumerate every way to
neutralise it: a compile-time change in a source port, a runtime binary patch to the retail exe,
an LD_PRELOAD / DLL shim, or a config/cvar. Note whether the check differs between the 32-bit
DOOM 3 and 64-bit BFG codebases.`,
  },
  {
    key: 'source-ports',
    prompt: `${CONTEXT}
ANGLE: native ARM64 source ports as the pragmatic path.
Evaluate dhewm3, RBDOOM-3-BFG, fhDOOM, DOOM 3 Quest, and any other maintained id Tech 4 ports.
For each: does it build NATIVELY on ARM64/aarch64 Linux? Does it still contain the x87 FPU
assertion (or was it removed/ifdef'd for non-x86)? Can it consume the retail Steam game assets
(base/pak*.pk4) the user already owns? What is the build story on Ubuntu-based aarch64 — CMake,
SDL2, OpenAL, dependencies? Does Prey (2006) have an equivalent port, and does anything cover
BFG's renderer? Give concrete repo URLs, build commands and known aarch64 caveats.`,
  },
  {
    key: 'community-arm',
    prompt: `${CONTEXT}
ANGLE: has anyone actually run these games on ARM64 translation, anywhere?
Search hard for real reports of DOOM 3 / DOOM 3 BFG / Prey (2006) running under x86-on-ARM64
translation: Asahi Linux (FEX + muvm), Apple Silicon (Rosetta 2 / CrossOver / Whisky),
Snapdragon X Elite Windows-on-Arm (Prism), Android (Winlator/Box64), Steam Deck is x86 so
exclude it. What worked, what settings, which translator, and did the FPU assertion appear?
Distinguish first-hand reports with logs from repetition. Note explicitly where you find NOTHING —
an absence of reports is itself a finding, but only if you searched the right names.`,
  },
  {
    key: 'wine-fpu',
    prompt: `${CONTEXT}
ANGLE: the Wine/Proton layer and the x87 control/status word.
Under Proton the game is a Windows PE running under Wine under FEX. Investigate whether Wine
itself perturbs x87 state: FPU control word initialisation, per-thread FPU context, signal
handler save/restore, NtSetContextThread / CONTEXT_FLOATING_POINT, and any Wine bugs about x87
tag word or FPU stack corruption. Are there Wine registry/env settings, or Proton options, that
change FPU handling? Also consider whether running DOOM 3's NATIVE LINUX build (id shipped one)
under FEX — bypassing Wine entirely — would avoid the problem, and whether Steam still ships it.`,
  },
]

phase('Recon')
const perDimension = await pipeline(
  DIMENSIONS,
  (d) => agent(d.prompt, { label: `recon:${d.key}`, phase: 'Recon', schema: FINDINGS }),
  (res, d) => {
    const items = (res && res.findings) ? res.findings : []
    if (!items.length) return []
    // verify at most the 3 strongest per dimension, adversarially
    const top = items.slice(0, 3)
    return parallel(top.map((f) => () =>
      agent(
        `${CONTEXT}\nAdversarially verify this claim. Default to survives=false if you cannot confirm it.\n\n` +
        `TITLE: ${f.title}\nCLAIM: ${f.claim}\nEVIDENCE OFFERED: ${f.evidence}\n` +
        `CLAIMED RELEVANCE: ${f.appliesHere}\nPROPOSED ACTION: ${f.actionable}\n\n` +
        `Check: does the cited source actually say this? Does it apply to ARM64 + FEX + Proton + ` +
        `retail Steam assets specifically, or only to a superficially similar case? Is the version ` +
        `current? If the claim is a NEGATIVE ("X does not exist"), try hard to falsify it by ` +
        `searching alternative names — this project has published a wrong negative before by ` +
        `guessing a package name. Give one concrete falsifiable test.`,
        { label: `verify:${d.key}:${f.title.slice(0, 28)}`, phase: 'Verify', schema: VERDICT }
      ).then((v) => ({ dimension: d.key, finding: f, verdict: v }))
    ))
  }
)

const all = perDimension.flat().filter(Boolean)
const survived = all.filter((x) => x.verdict && x.verdict.survives)
const killed = all.filter((x) => x.verdict && !x.verdict.survives)
log(`recon+verify done: ${all.length} checked, ${survived.length} survived, ${killed.length} refuted`)

phase('Synthesize')
const plan = await agent(
  `${CONTEXT}

You are writing the actionable conclusion of a research review for a rigorous engineering log.

SURVIVED ADVERSARIAL VERIFICATION:
${JSON.stringify(survived.map((x) => ({ dim: x.dimension, ...x.finding, verdict: x.verdict })), null, 1)}

REFUTED (say so explicitly where a plausible-sounding path was killed, and why):
${JSON.stringify(killed.map((x) => ({ dim: x.dimension, title: x.finding.title, claim: x.finding.claim, why: x.verdict.why, correction: x.verdict.correction })), null, 1)}

Produce:
1. A one-paragraph verdict: is there an EXISTING solution, or must something be modified?
2. A ranked table of viable paths: path | what it changes | effort | probability it works | first experiment.
   Rank by (probability x playability) / effort. Be honest that a source port may be the
   pragmatic winner even though it is less interesting than fixing the translator.
3. The single cheapest falsifiable experiment to run FIRST, written as a concrete command or
   step sequence for this rig, including what result would kill the idea.
4. Explicit dead ends with reasons, so nobody re-treads them.
5. Anything that remains genuinely UNKNOWN, stated as unknown rather than glossed.

Be concrete: file names, function names, config keys, repo URLs, build commands, version numbers.
Do not pad. If evidence is thin somewhere, say so.`,
  { label: 'synthesize:plan', phase: 'Synthesize' }
)

return { checked: all.length, survived: survived.length, refuted: killed.length, plan }
