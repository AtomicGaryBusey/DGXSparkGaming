# `notes/upstream/` — bug reports written for someone else's tracker

Each file here is a finished report for an **upstream** project, phrased for a maintainer who
has never seen this repo: version, host, symptom, minimal reproducer, proposed fix, and what was
measured before and after.

**Nothing here has been filed.** Filing is a deliberate, outward-facing act and needs AGB to
decide — these are drafts held ready, not a queue that drains itself.

| file | project | status |
|---|---|---|
| `box64-issue-1-box32-libc-wrappers.md` | ptitSeb/box64 | ready, fix verified (1 → 0 access violations) |
| `box64-issue-2-fsave-tagword.md` | ptitSeb/box64 | ready, fix verified against SDM-derived expectations |
| `box64-issue-3-ntcreatefile-collision.md` | ptitSeb/box64 | ready, 100% reproducible, no fix proposed |
| `fex-issue-1-a3-store-duplicates-preceding-op.md` | FEX-Emu/FEX | ready, minimal repro, regression-gated by `isa-probe.sh` |

Two conventions worth keeping, both learned here the hard way:

- **State the scope honestly, including what the bug does *not* explain.** Report #2 says
  outright that it does not explain the id Tech 4 crash it was found while chasing. A maintainer
  who discovers that themselves stops trusting the rest of the report.
- **The reproducer must not need this machine.** Every one here is a freestanding probe or a
  short C file, so a maintainer can run it without a GB10, a Steam library, or our tooling.
