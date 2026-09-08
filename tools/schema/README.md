# `tools/schema/` — the Spark Game Launcher database

| file | what it is |
|---|---|
| `sgl-schema.sql` | the whole schema: identity, clusters, runs, claims, guards, views |
| `test-guards.py` | 15 adversarial tests. **Run it after any trigger change.** |

## The one thing this schema is for

An unverified claim must be **impossible** to render as verified. Not discouraged by a UI
convention — a convention is one careless `INSERT` away from being false — but refused by the
database.

Six guards, `G1`–`G6`, each firing on **INSERT and UPDATE**, each doing explicit `SELECT`s rather
than trusting a foreign key. Both properties are deliberate:

- **UPDATE too**, because `INSERT … 'unverified'; UPDATE … 'supported'` launders any
  insert-only guard.
- **No reliance on foreign keys**, because `PRAGMA foreign_keys` defaults to **OFF** in the
  sqlite3 CLI — precisely the writer a no-daemon design invites.

## Guards

| | refuses |
|---|---|
| **G1** | a claim naming a runtime, without an **attributable** run. Verifier class is irrelevant: nobody can *see* which translator ran |
| **G2** | `supported` without evidence appropriate to its verifier class. `human_observed` **is** sufficient evidence; `community_reported` can never be supported |
| **G3** | `community_reported` without a `source_url` |
| **G4** | a retraction with no reason — the reason is the valuable part |
| **G5** | an artifact marked present with no path |
| **G6** | an instrumented claim citing a **phantom run** — a run directory with no `run.json` |

G6 is not hypothetical. On 2026-09-08 this machine had **14** run directories containing
`gpu.csv` and nothing else, some with 57,000 lines of idle-desktop GPU samples, produced by a
leaked telemetry sampler in `game-run.sh`. Without G6 they import as runs *with evidence*, and
"the game rendered for 57,518 samples" becomes a fact.

## A note on how the tests are written

Two tests once passed for the wrong reason: they were labelled G1 but were *also*
`supported`-without-evidence, so **G2** caught them first. The suite reported 15/15 green while
G1 was untested.

They are now built from a status/verifier combination G2 explicitly allows, so only G1 can refuse
them — and the runner prints **which guard actually fired**, flagging any mismatch. A test that
passes because a different mechanism caught it has not tested the guard it names.
