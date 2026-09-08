export const meta = {
  name: 'steamclient-init-dive',
  description: 'Deep dive on "Access violation in steamclient_init" for Steam legacy-DRM titles under Proton on ARM64',
  phases: [
    { title: 'Recon', detail: 'four angles on the legacycompat/steamclient_init failure' },
    { title: 'Verify', detail: 'adversarially test each claim against this stack' },
    { title: 'Synthesize', detail: 'ranked resolution paths' },
  ],
}

const CONTEXT = `
THE FAILURE, measured on this box today (2026-09-07). Everything below is VERIFIED locally
unless marked otherwise.

RIG: NVIDIA DGX Spark class, GB10 Grace-Blackwell, ARM64 (Cortex-X925/A725, NO 32-bit ARM
support so ALL x86 is translated). Driver 580.173.02, kernel 6.17.0-1032-nvidia.
Translators: FEX-Emu 2607/2608 (PPA) and Box64 v0.4.4. binfmt_misc registers ONLY Box64 for
x86 ELF; FEX runs only via FEXBash/FEXInterpreter or as a child of a FEX process.
Proton - Experimental (experimental-11.0-20260903b-x86_64), SteamLinuxRuntime_4 container,
pressure-vessel 0.20260805.0.

THE ERROR (Prey 2006, appid 3970, runtime_actual=Box64, verified from run.json):
    ...Loaded L"...\\steamapps\\common\\Steam.dll" at 79F50000: native
    ...Loaded L"C:\\Program Files (x86)\\Steam\\steamclient.dll" at 78A70000: native
    trace:seh:handle_syscall_fault code=c0000005 addr=0x4004c5d6 ip=4004c5d6
    warn:seh:handle_syscall_fault backtrace: --- Exception 0xc0000005 at 0x4004c5d6:
        .../files/lib/wine/i386-unix/ntdll.so + 0x465d6
        (__wine_unix_call_dispatcher_prolog_end + 0x36)
    err:steamclient:steamclient_call Access violation in steamclient_init.
The engine never reaches its own config parser; no qconsole.log is written at all.
DOOM 3 (appid 9050) produces the identical signature.

THE MECHANISM as far as we have established it:
- steamapps/common/Steam.dll is a SYMLINK to ~/.local/share/Steam/legacycompat/Steam.dll.
  legacycompat/ is Valve's own legacy-DRM support kit and contains: Steam.dll (385,312 bytes,
  dated 2018-01-23), steamclient.dll (21,377,688 bytes, 2026-09-02), SteamService.exe,
  iscriptevaluator.exe, plus symlinks to steamclient64.dll and GameOverlayRenderer64.dll.
- Steam's appinfo.vdf marks these titles with legacy-DRM keys (read with tools/appinfo.py):
    9050  DOOM 3   legacykeyregistrationmethod=registry,
                   legacykeyregistrylocation=HKEY_CURRENT_USER\\Software\\Valve\\TestApp9050\\SteamKey
    9070  RoE      registry, TestApp9070
    3970  Prey     legacykeyregistrationmethod=disk, legacykeydisklocation=base\\preykey
    2210  Quake 4  legacykeyregistrationmethod=disk, legacykeydisklocation=q4base\\quake4key
    208200 BFG     no legacy keys at all
- ALL of DOOM 3 / RoE / Prey / Quake 4 carry legacy-DRM keys, but QUAKE 4 DOES NOT LOAD
  Steam.dll and runs fine (it loads only Proton's builtin lsteamclient.dll). Prey does load
  it and dies. Both are "disk" method. That contrast is UNEXPLAINED and is a key question.

WHAT ELSE WE KNOW:
- The same titles under FEX instead of Box64 fail DIFFERENTLY and EARLIER-ish: Prey under FEX
  reaches its config (writes qconsole.log) but dies at "SetPixelFormat failed" with no GL
  context. So steamclient_init is a BOX64-path failure; FEX gets past it (or never reaches it).
  Both runtimes were confirmed by reading /proc/<pid>/exe, not inferred.
- STRONG HINT AT A BYPASS, not yet controlled: running Doom3.exe under wine with NO SteamAppId
  / SteamGameId set got all the way to OpenGL initialisation -- i.e. far past steamclient_init.
  We have NOT yet run that as a proper experiment with the runtime container in place.
- Proton normally redirects Steam API calls to its own lsteamclient.dll shim. Something about
  the legacy path loads the NATIVE steamclient.dll instead, and that is what faults.
- The fault is inside Wine's 32-bit unix-call dispatcher (__wine_unix_call_dispatcher), i.e.
  at the 32-bit PE -> unix syscall boundary, not inside game code.

RULES FOR A USEFUL ANSWER (this project has been burned by each):
- A negative from a query is only as good as the name you guessed. Cross-check with
  alternative spellings ("legacycompat", "legacy DRM", "steamclient_init", "CEG",
  "Custom Executable Generation", "TestApp<appid>").
- Secondary reporting of a changelog is NOT evidence. Read the commit, issue or source.
- Never propose a fix whose effect cannot be measured. Every path must come with the exact
  observable that would confirm or refute it on this box.
- Prefer official/upstream sources. No leaked binaries, no Discord-sourced DLLs.
- Distinguish clearly between "documented", "inferred", and "guessed".
- Anything that disables DRM entirely for a game the user OWNS is legitimate to discuss as a
  compatibility workaround, but say plainly what it costs (achievements, overlay, cloud saves,
  online play) and whether it violates the Steam subscriber agreement.
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
          evidence: { type: 'string', description: 'URLs, commit hashes, issue numbers, file:line, source excerpts' },
          confidence: { type: 'string', enum: ['documented', 'inferred', 'guessed'] },
          actionable: { type: 'string', description: 'exact commands/steps for THIS box' },
          observable: { type: 'string', description: 'what result would confirm it, and what would refute it' },
          costs: { type: 'string', description: 'what breaks if this path is taken (achievements, overlay, online, ToS)' },
          kind: { type: 'string', enum: ['mechanism', 'workaround', 'upstream-fix', 'dead-end'] },
        },
        required: ['title', 'claim', 'evidence', 'confidence', 'actionable', 'observable', 'kind'],
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
    effort: { type: 'string', enum: ['trivial', 'minutes', 'hours', 'days', 'infeasible'] },
    probability: { type: 'string', enum: ['high', 'medium', 'low'] },
    firstTest: { type: 'string', description: 'one concrete command sequence runnable on this box' },
  },
  required: ['survives', 'why', 'effort', 'probability', 'firstTest'],
}

const ANGLES = [
  {
    key: 'mechanism',
    verify: 2,
    prompt: `ANGLE 1 — WHAT IS THE LEGACYCOMPAT PATH, EXACTLY, AND WHY DOES QUAKE 4 ESCAPE IT?

Establish the mechanism from primary sources (Proton source, Steam client behaviour, Wine's
steamclient built-in), not from forum lore.

- What does Steam's \`legacycompat/\` kit do, when is it injected, and which appinfo fields
  trigger it? \`legacykeyregistrationmethod\` (registry vs disk), \`legacykeydisklocation\`,
  \`legacykeyregistrylocation\` — what consumes these, the Steam client or the game?
- Proton ships \`lsteamclient.dll\` to redirect Steam API calls to the host Steam. Read
  Proton's source for how it decides between lsteamclient and a native steamclient.dll.
  Which code path ends up loading \`C:\\Program Files (x86)\\Steam\\steamclient.dll\` natively
  inside the prefix, and what puts that file there?
- Wine has an \`err:steamclient:\` channel — find the source that emits
  "Access violation in steamclient_init" (likely Wine's or Proton's steamclient built-in).
  What exactly is it wrapping, and what does the AV imply about the callee?
- THE KEY QUESTION: Prey and Quake 4 both have legacykeyregistrationmethod=disk, yet Quake 4
  loads only lsteamclient and runs, while Prey loads Steam.dll + native steamclient and dies.
  Find the discriminator. Is it CEG (Custom Executable Generation)? Is Quake 4's copy
  already CEG-stripped? Does the disk key file's presence/absence change the path?`,
  },
  {
    key: 'upstream',
    verify: 2,
    prompt: `ANGLE 2 — IS THIS KNOWN UPSTREAM, AND IS IT FIXED?

- Search ValveSoftware/Proton and the Wine bug tracker for "steamclient_init",
  "Access violation in steamclient_init", "legacycompat", "legacy DRM", plus the affected
  titles (DOOM 3 appid 9050, Prey 3970, Resurrection of Evil 9070). Report issue numbers,
  status, and whether any fix actually landed — read the commit, not a summary.
- The fault is at \`ntdll.so + 0x465d6 (__wine_unix_call_dispatcher_prolog_end + 0x36)\`, i.e.
  inside Wine's 32-bit PE->unix call dispatcher. Are there known issues with 32-bit
  unix-call dispatch, WoW64, or the new wow64 mode interacting with a native (non-builtin)
  32-bit DLL that itself makes unix calls? steamclient.dll is 21 MB and does a lot.
- Does this reproduce on x86-64 Linux (no translation)? If it is ALSO broken there, it is a
  Proton/Wine bug and ARM64 is irrelevant — that would be the single most useful thing to
  establish, because it changes who can fix it. Look for reports from non-ARM users.
- Is there a Proton version, branch, or \`PROTON_*\` setting where this works? Check Proton
  release notes and the proton script's own options for anything touching steamclient.`,
  },
  {
    key: 'workarounds',
    verify: 3,
    prompt: `ANGLE 3 — WHAT ACTUALLY MAKES THESE GAMES RUN, TODAY?

Concrete, testable routes. For each, say exactly what it costs the user.

- The strongest local hint: launching the game WITHOUT SteamAppId/SteamGameId in the
  environment got DOOM 3 far past steamclient_init (to OpenGL init). Why would that skip the
  legacy path? What breaks without it (overlay, achievements, cloud saves, playtime)? Is
  there a middle ground — e.g. SteamAppId set but the legacy shim suppressed?
- Wine DLL overrides: can \`WINEDLLOVERRIDES\` force \`steamclient\`/\`steamclient64\` to
  builtin so Proton's lsteamclient handles it instead of the native 21 MB DLL? Give the exact
  override string and say whether Proton respects it for this path.
- Does deleting/renaming the prefix's \`C:\\Program Files (x86)\\Steam\\steamclient.dll\`, or
  the \`steamapps/common/Steam.dll\` symlink, change the path taken? What re-creates them?
- \`PROTON_NO_ESYNC\`/\`NO_FSYNC\`, \`PROTON_USE_WINED3D\`, \`WINEDLLOVERRIDES\`,
  \`STEAM_COMPAT_*\` — enumerate what the proton script actually reads and which could
  plausibly affect this. Do not invent variable names; read the script.
- Community routes for old Steam DRM titles under Proton generally (Lutris/Heroic install
  scripts, ProtonDB entries for DOOM 3 / Prey specifically). Note that ProtonDB is Deck/AMD
  skewed and says nothing about ARM64 — use it for the DRM path only.`,
  },
  {
    key: 'translation',
    verify: 2,
    prompt: `ANGLE 4 — IS THIS ABOUT TRANSLATION AT ALL?

The failure was observed under Box64. Under FEX the same titles get further (they reach the
engine's config parser and die later at SetPixelFormat instead). That asymmetry needs an
explanation, and it decides who can fix this.

- Box64 v0.4.4 / Box32: are there known issues with a large native 32-bit Windows DLL making
  unix calls through Wine's dispatcher? Search box64's issue tracker for steamclient, Wine
  unix call, __wine_unix_call_dispatcher, 32-bit thunk faults.
- Is \`__wine_unix_call_dispatcher\` a known trouble spot for either translator? It is the
  PE->unix boundary, so it involves a callback out of translated code into native code and
  back — historically fragile in JITs.
- Does FEX simply never REACH steamclient_init (different load order), or does it get past it
  successfully? Determining this from the evidence matters: "FEX handles it" and "FEX never
  tries" have completely different implications. Say what log evidence would distinguish them.
- If this is a JIT bug, what is the minimal reproducer that does NOT need a game? We can
  build 32-bit Windows PEs here (mingw i686 in a local prefix) and run them under Proton's
  wine under either JIT — that is how the x87 question was settled today.`,
  },
]

phase('Recon')
const perAngle = await pipeline(
  ANGLES,
  (a) => agent(`${CONTEXT}\n\n${a.prompt}\n\nMark anything you could not confirm as confidence="guessed" and say so plainly. A ruled-out path recorded as kind="dead-end" is valuable — it stops it being re-tried.`,
    { label: `recon:${a.key}`, phase: 'Recon', schema: FINDINGS }),
  (res, a) => {
    const items = (res && res.findings) ? res.findings : []
    const top = items.filter((f) => f.kind !== 'dead-end').slice(0, a.verify)
    if (!top.length) return []
    return parallel(top.map((f) => () =>
      agent(
        `${CONTEXT}\n\nAdversarially verify this claim. Default to survives=false unless you can confirm it.\n\n` +
        `ANGLE: ${a.key}\nTITLE: ${f.title}\nCLAIM: ${f.claim}\nEVIDENCE OFFERED: ${f.evidence}\n` +
        `SELF-RATED CONFIDENCE: ${f.confidence}\nPROPOSED ACTION: ${f.actionable}\n` +
        `CLAIMED OBSERVABLE: ${f.observable}\n\n` +
        `Does the cited source actually say this? Is it current for Proton Experimental ` +
        `(experimental-11.0-20260903b), SteamLinuxRuntime_4, Box64 0.4.4 / FEX 2607? Does it ` +
        `apply to a 32-bit PE specifically? If the claim is a NEGATIVE ("X is not possible"), ` +
        `try hard to falsify it under alternative names. Give ONE concrete first test runnable ` +
        `here, and say what result would REFUTE the claim, not just confirm it.`,
        { label: `verify:${a.key}:${f.title.slice(0, 22)}`, phase: 'Verify', schema: VERDICT }
      ).then((v) => ({ angle: a.key, finding: f, verdict: v }))
    ))
  }
)

const all = perAngle.flat().filter(Boolean)
const survived = all.filter((x) => x.verdict && x.verdict.survives)
const refuted = all.filter((x) => x.verdict && !x.verdict.survives)
log(`verified ${all.length}: ${survived.length} survived, ${refuted.length} refuted`)

phase('Synthesize')
const plan = await agent(
  `${CONTEXT}

SURVIVED VERIFICATION:
${JSON.stringify(survived.map((x) => ({ angle: x.angle, ...x.finding, verdict: x.verdict })), null, 1)}

REFUTED:
${JSON.stringify(refuted.map((x) => ({ angle: x.angle, title: x.finding.title, claim: x.finding.claim, why: x.verdict.why, correction: x.verdict.correction })), null, 1)}

Write, for an engineering log whose value is that its claims are true:

1. **The mechanism, stated as plainly as the evidence allows** — what loads the native
   steamclient.dll, why, and what faults. Mark each step documented / inferred / unknown. Do
   not paper over the gap: if the Prey-vs-Quake-4 discriminator is still unknown, say so.

2. **Is this an ARM64 problem or a Proton/Wine problem?** This decides who can fix it and is
   the single most valuable output. State the evidence for your answer and what would overturn it.

3. **Ranked resolution paths**, best first, each with: what it does, effort, probability, what
   it COSTS the user (achievements, overlay, cloud saves, online, ToS), and the exact first
   command to run here.

4. **The three cheapest experiments**, as runnable command sequences, each with the result
   that would KILL the idea. Prefer ones that read existing evidence over ones that build
   anything. Note that this box already has: mingw i686 in a local prefix, a working
   tools/game-run.sh with RUNTIME=fex|box64 and run.json provenance, and tools/run-both.sh.

5. **Dead ends**, with reasons, including everything refuted above.

6. **What is genuinely unknown**, stated as unknown.

Be concrete: file paths, env var names read from the actual proton script, issue numbers,
commands. Do not pad.`,
  { label: 'synthesize:steamclient', phase: 'Synthesize' }
)

return { verified: all.length, survived: survived.length, refuted: refuted.length, plan }
