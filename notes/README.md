# notes/

Raw research artefacts, kept for provenance. **These are working notes, not curated findings** —
the distilled, fact-checked conclusions live in the main `README.md`. Where the two disagree, the
main README wins: it incorporates corrections these files do not.

- `2026-09-05-dlss5-research-synthesis.md` — output of a 102-agent adversarial research run on
  "can DLSS 5 run on GB10". **Contains at least one known error** (it reports
  NapXDD/addon-dlssnr-linux issue #3 as a success; it is a failure report — see the critique).
- `2026-09-05-dlss5-research-critique.md` — completeness critic over the above. Catches the issue-#3
  misread, adds NVIDIA Research's own DLSS 5 page, and flags Reddit as the one unsearched channel.
- `2026-09-07-ultracode-idtech4-x87-paths.md` — 25 agents, 2.36M tokens. Existing solutions and
  modification paths for the id Tech 4 x87 cluster. **Its headline claim about HROT was refuted
  locally by disassembly** (it said "zero scalar SSE"; measurement showed 24,234 x87 vs 1,818 SSE).
  The conclusion survived, the evidence did not.
- `2026-09-07-ultracode-failure-cluster-dive.md` — 16 agents, 1.46M tokens, across all five failure
  clusters. Its premise correction turned out to be **right and important**: the
  `vkGetPhysicalDeviceDescriptorSizeEXT` signature this log had cited for months is emitted by games
  that WORK. Verified independently before acting on it, and the README now carries the retraction.
- `2026-09-08-ultracode-steamclient-init-dive.md` — 14 agents, 1.48M tokens. **The strongest run so
  far, and it holds up:** it decoded the faulting instruction rather than inferring it, and every
  load-bearing claim was re-verified locally afterwards (PE `.bind` sections, the four missing
  box64 symbols, the i386 libstdc++ UND set, and the failure chain in our own logs). 8 of 9
  findings survived adversarial verification.
- `2026-09-07-ultracode-new-titles-eval-plan.md` — 8 agents. Classification and evaluation ordering
  for 21 newly installed titles.

## Reading these

Every report carries a provenance header (agents, tokens, tool calls) because a synthesis is
only as trustworthy as the scrutiny behind it, and the counts say how much there was.

**Treat every claim as untrusted until verified locally.** That is not boilerplate: of the three
2026-09-07 reports, one had its headline finding refuted by a five-minute local check and another
overturned a root cause this log had carried for months. Both outcomes are why the reports are
worth keeping — and why they are kept *separately* from the README rather than merged into it.

New reports are persisted with `tools/save-workflow-report.sh <task-output.json> [slug]`.
