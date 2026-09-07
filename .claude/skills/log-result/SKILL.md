---
name: log-result
description: Record a game test result or an experiment finding in README.md to this project's conventions, with a verification pass that must be completed before anything is written. Use whenever a game has been tested, an experiment has produced a result, or a claim is about to be added to the log.
---

# Recording a result

This log's value is that its claims are true. On 2026-09-07 a headline result was
written, committed and pushed, and was wrong — `NVSDK_NGX_D3D12_EvaluateFeature`
is the *generic* NGX hook, so 3,483 of the game's own DLSS-SR calls were reported
as DLSS-5 Neural Rendering. The NR-specific counter said **2**. The user caught it
by toggling the feature and seeing an identical image.

**A human A/B beat every counter being read.** That is the failure this skill exists
to prevent, and no hook can catch it — the number was real; the meaning was not.

## Before writing anything, answer these

Write the answers out. If any answer is "I don't know", the claim is not ready.

1. **What was observed, in one sentence, without interpretation?**
   Not "NR is running" — "a counter named X increased by N".
2. **Does the thing measured belong to the feature claimed?**
   Is the counter *specific*, or a generic hook the feature merely rides on?
   Name the specific log line. If only a generic one exists, say so in the entry.
3. **What is the control?** What did the same measurement read with the feature off,
   or with a deliberately bogus input? `CreateFeature(18)` returned Success for
   feature **99** too — a result with no control is a rubber stamp.
4. **If it is supposed to change pixels, did anyone look at the pixels?**
   A screenshot A/B, a debug view, a capture folder. If not, the entry says
   "visual correctness unverified" — in the entry, not just in your head.
5. **What would falsify this?** If nothing would, it is not a finding.
6. **What is the evidence path?** A file under `~/dgx-gaming-work/evidence/` or
   `runs/`. If there is no artifact, there is no claim.

## Then write it

Follow the conventions in CLAUDE.md exactly:

- **Works** → a row in **Tested by AGB**, alphabetical:
  `| **Game** | API | Performance | Notes |`
  API is the real render path (DX11, DX12, Vulkan, OpenGL, KEX, DOS). Performance is
  terse and specific — "Smooth, maxed, 5120x1440", "Playable, 25-30 FPS". Notes carry
  engine + translation path, launch options, caveats. Prefix open questions `TODO:`.
- **Fails** → a row in **Known Issues** with a ROOT CAUSE, not "crashes". Tie it to an
  existing failure signature when it matches; add a new signature if it does not.
- **Move the game** out of "Installed — Not Yet Tested" / "Likely to Work".
- Performance claims need numbers. `tools/game-run.sh` at minimum, `tools/bench-ab.sh`
  for any version comparison. Record which Proton, read from the prefix's
  `config_info`, not from intent.

## Being wrong in public

If a published claim turns out to be wrong, **correct it in place with a visible
callout** — do not quietly edit it away. The wrong version and the reason it was
wrong are the most useful content in this repo. See the `⚠️ CORRECTION` blocks in
README.md for the house style.
