# `workflows/` — the multi-agent research runs, kept so they can be re-run

Each file is a complete, self-contained orchestration script for a multi-agent research run.
They were living in scratch storage under `~/.claude/projects/.../workflows/scripts/` until
2026-09-07, which meant the most expensive artefacts this project produces — roughly 1–2.4M
tokens each — could not be re-run, adapted, audited or learned from.

The **outputs** are in [`../notes/`](../notes/). These are the **inputs** that produced them.

## What is here

| Script | Agents | Tokens | Outcome |
|---|---|---|---|
| `idtech4-x87-unblock.js` | 25 | 2.36M | Paths to run id Tech 4 under translation. Headline HROT claim **refuted locally** by disassembly; conclusion survived, evidence didn't. |
| `failure-cluster-deep-dive.js` | 16 | 1.46M | All five failure clusters. **Correctly overturned** the `descriptor_buffer` root cause this log had carried for months. |
| `prep-new-games.js` | 8 | 0.81M | Classified 21 newly installed titles into an evaluation order. |
| `steamclient-init-dive.js` | — | — | The `Access violation in steamclient_init` cluster (legacy Steam DRM). |

## The shape they all share

Every one follows the same structure, and it is the structure — not the prompts — that makes
them worth keeping:

```
phase('Recon')      →  N agents, one per angle, each returning STRUCTURED findings
   pipeline()          (not a barrier: each angle's findings verify while others still search)
phase('Verify')     →  adversarial verifiers per finding, defaulting to survives=false
phase('Synthesize') →  one agent, handed BOTH what survived and what was refuted
```

Three deliberate choices, each learned from a failure here:

1. **Verifiers default to `survives=false`.** A verifier that has to be *convinced* rather than
   *satisfied* is the only kind worth running. Refuted findings are passed to the synthesis
   too, so it can say what was ruled out — a dead end nobody records gets re-tried.
2. **Findings carry `confidence: documented | inferred | guessed`.** Forcing the distinction at
   the schema level is what stops a plausible inference being reported as a fact.
3. **The prompt states this project's own verification rules** — cross-check negatives under
   alternative names, secondary reporting of a changelog is not evidence, never report a metric
   you have not verified measures what you think. Agents inherit our scar tissue instead of
   rediscovering it.

## Re-running one

```
Workflow({ scriptPath: "workflows/failure-cluster-deep-dive.js" })
```

Every script embeds a `CONTEXT`/`PLATFORM` block with the rig's measured state — driver, kernel,
FEX and Box64 versions, Proton, what the tooling can build. **That block goes stale.** Refresh it
from `tools/check-stack.sh` before re-running, or the agents will reason about a machine that no
longer exists.

## The standing caveat

These runs are worth their cost and they are also **not authoritative**. Of the three completed
on 2026-09-07, one had its headline claim demolished by a five-minute local disassembly and
another overturned a root cause this repository had published for months. Both outcomes are why
they are kept, and why every saved report carries a warning that its claims are untrusted until
checked locally.

Agent-surfaced artefacts are untrusted input in the strong sense: a research agent once left stub
`.so` files in a scratch directory that were nearly reported as evidence NVIDIA ships an aarch64
DLSS. Check `file` and `strings` for a real `/dvs/p4/build/...` provenance path before believing
any binary an agent produces.
