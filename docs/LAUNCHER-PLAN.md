# Spark Game Launcher — Plan

> Status: **plan, not code.** Nothing here has been built. Everything measured on this box is
> marked MEASURED with the command that produced it; everything inherited from a survey or the
> web is marked INFERRED or UNVERIFIED with the check that would settle it. Written 2026-09-08
> against DGX OS 7.2.3 / kernel 6.17.0-1032-nvidia / driver 580.173.02.

---

## 1. Vision

A launcher for x86-64 PC games on ARM64 Spark hardware that answers the question Steam cannot:
**does this title work, under which translator build, with what evidence, and is that evidence
still true against the stack installed right now.**

It is for one person and one agent, working the same machine at the same time. The human presses
Play and sees his library. The agent runs experiments, records results, and proposes claims the
human approves. Neither has a privilege or a code path the other lacks — that is the literal
implementation of "customer zero, simultaneously," and it is why the contract is a database and a
CLI rather than a GUI with an API bolted on.

The launcher is the front end of this repo's method, not a replacement for it. `README.md` stays
the hand-written log — its CORRECTION blocks are the most valuable content here and no generator
will write those. The launcher makes the *machine-actionable* half of that knowledge queryable,
launchable, and structurally unable to present an unverified claim as a verified one.

---

## 2. Stack decisions

### 2.1 UI toolkit — **Qt 6.11 / Qt Quick (QML) via PySide6-Essentials, pinned to 6.11.2**

The app's core surfaces are a dense sortable/filterable 52-row table, an inline log viewer with
selectable text and per-line highlighting, and a pill-chain diagram. Those are retained-mode
problems. QML gives them, plus property bindings, states and transitions for a dark technical
look built from `Basic` style controls (never `Fusion` or `Material`, which impose their own).

**Strongest argument against:** egui/Rust is a single 11 MB binary against ~241 MB of PySide6 on
disk (MEASURED by the platform red team on the probe venv), and Rust is Tier 1 on
`aarch64-pc-windows-msvc` where CPython is PEP 11 Tier 2. **Why it loses:** every element of the
visual spec below — dashed chip outlines, hairline connectors, hatch fills, struck-through
absent artifacts, selectable log text with inline spans — is hand-painted per frame in an
immediate-mode toolkit, and the same proposal disclosed a 45 s hang on native Wayland it could
not explain. This project needs a maintained dense-data toolkit, not a maintained renderer.

**Unverified, and the red team is right to say so:** "not Electron" holds on the
no-browser-engine reading (Essentials ships no WebEngine binary), and fails on the
lighter-weight reading at 241 MB on disk. AGB should be told that plainly rather than have the
constraint declared satisfied. **Settled by:** `du -sh` on the installed venv — already done,
241 MB. The decision stands anyway, because the alternative that is genuinely small is the one
that cannot draw the app.

**Licence rule, and it is a mechanism, not a convention.** Qt's open-source offering makes a
named module list **GPLv3-only**; linking any of them GPLs this MIT repo. The list, taken from
`doc.qt.io/qt-6/licensing.html` (INFERRED — re-fetch and diff at each Qt minor bump): Canvas
Painter, CoAP, Graphs, GRPC, HTTP Server, Lottie Animation, MQTT, **Network Authorization**,
Qml Compiler, Quick 3D, Quick 3D Physics, Quick Timeline, Virtual Keyboard, Wayland Compositor.

Two corrections to what the surveys carried: **QtCharts is not on that list** and should not be
banned on its say-so; **QtNetworkAuth and QtCanvasPainter are**, and neither survey caught them.
The Canvas Painter miss matters — "hand-draw frametime plots in QML Canvas" is fine (`Canvas` is
a QtQuick element, LGPL) but the name sits one character from a GPL-only module.

Enforcement is `constraints.txt` pinning `PySide6-Essentials==6.11.2` and `shiboken6==6.11.2`
with `PySide6` and `PySide6-Addons` explicitly refused, **plus** a CI import-linter whose ban
list is read from Qt's licensing page. "Install Essentials only" is a convention; one
`pip install PySide6` undoes it. This repo built `.claude/hooks/` because conventions failed.

Allowlist: QtCore, QtGui, QtQml, QtQuick, QtQuickControls2, QtNetwork, QtSql, QtWidgets, QtSvg.

### 2.2 Language — **Python 3.12.3** (MEASURED: `python3 -V`)

`tools/appinfo.py` is a working binary-VDF parser and is already importable; `pick-runtime.py`
is 211 lines carrying two hard-won detection rules. Rewriting them is the whole schedule. The
launch path is I/O-bound. All logic lives in the `sgl/` package; QML holds zero business logic,
so a future forced port of the view layer is a rewrite of the view layer only.

**Strongest argument against:** PEP 11 Tier 2 on Windows/ARM64 (INFERRED from the toolkit
survey). **Why it loses:** see §9 — the Windows target is probably a different machine running a
different emulator, and the fields that make this product distinct are NULL there. Paying a
language tax today for that is the definition of buying portability you cannot test.

### 2.3 Database — **SQLite via stdlib `sqlite3`** (MEASURED: 3.45.1 on this box)

Not QtSql: the CLI and indexer must run with Qt absent. One file,
`~/dgx-gaming-work/sgl.db`, beside the runs on ext4 — never a network mount, because WAL's
`-shm` is an mmap'd lock table.

Pragmas on **every** connection: `journal_mode=WAL`, `busy_timeout=5000`, `foreign_keys=ON`,
`synchronous=FULL`, `journal_size_limit=67108864`, `application_id=0x53474C31`, `user_version=N`.

`synchronous=FULL` not NORMAL: the data survey measured ~1,100 write txn/s at FULL and the red
team reproduced it (800 transactions across 4 writer processes in 0.71 s, zero lost updates).
The workload is tens of writes per minute. The row we cannot afford to lose is the one saying a
human watched a game work.

**One write path.** `BEGIN IMMEDIATE`, on `OperationalError` `ROLLBACK` then retry with jitter.
`BEGIN DEFERRED` and bare autocommit writes are banned and the ban is a test, not a comment: a
DEFERRED read-then-upgrade fails with `database is locked` **instantly** against a 5,000 ms
`busy_timeout`, because SQLite bypasses the busy handler for `SQLITE_BUSY_SNAPSHOT`. MEASURED —
the red team's re-run produced 600 such failures out of 800. That failure reads exactly like
contention and will be "fixed" by raising the timeout, which cannot possibly help.

**No daemon.** The single-writer justification is refuted by the numbers above, and the
mutual-exclusion problem is physical, not database-shaped (§5.3). A daemon would be a single
point of failure between the owner and his own games.

### 2.4 Packaging — **`tools/setup-launcher.sh`, no sudo, directory bundle**

Matches this repo's convention: idempotent, `DRY_RUN=1`, header comment naming the failure it
prevents. Creates `~/.local/share/sgl/venv`, pip-installs from `constraints.txt`, installs
`~/.local/bin/sgl` + `sgl-gui` shims and a `.desktop` file. Never PyInstaller `--onefile` — a
directory bundle satisfies LGPLv3's relink right trivially and `--onefile` does not obviously.
Ship `LICENSE` (MIT), `LICENSE.LGPLv3`, and a written offer for Qt's corresponding source.

**Hard floor, and it has zero headroom.** The wheel tag is `manylinux_2_39_aarch64`; this box is
glibc 2.39 exactly (MEASURED, re-confirmed 2026-09-08 — `ldd --version` reports 2.39, and the
only aarch64 wheel published for 6.11.2 is `manylinux_2_39_aarch64`, so the match is exact with
nothing to spare). The platform red team established that the set of PySide6
versions with a `win_arm64` wheel (≥6.9.0) and the set with a `manylinux_2_31` aarch64 wheel
(≤6.8.0.2) are **disjoint** — so on a DGX OS 6 / Ubuntu 22.04 unit the installer cannot work at
all without sudo or a Qt source build. `setup-launcher.sh` must assert `glibc >= 2.39` up front
and fail naming DGX OS 7 / Ubuntu 24.04, not emit an opaque pip resolution error.
**Unsettled:** which DGX OS release AGB's other Sparks run. One `cat /etc/dgx-release` each.

### 2.5 Windows packaging — **deliberately not built, with a rot alarm**

`docs/SPARK-PLATFORM.md` is explicit: confirm the toolkit and DB *can* run there at selection
time, then stop paying. That check passes, and it is now **VERIFIED, not inferred** (2026-09-08, re-queried against
`https://pypi.org/pypi/PySide6-Essentials/json`). PySide6-Essentials **6.11.2** publishes exactly
five wheel platforms:

```
macosx_13_0_universal2, manylinux_2_34_x86_64, manylinux_2_39_aarch64, win_amd64, win_arm64
```

so both the platform we ship on (`manylinux_2_39_aarch64`) and the platform we may one day port to
(`win_arm64`) are present in the same pinned release. `PySide6` (the full package) has the same five.

**What this does and does not establish.** It establishes that a wheel *exists* and can be
downloaded. It says nothing about whether Qt Quick renders correctly on GB10-under-Windows, which
RHI backend it selects, or whether the NVIDIA Windows driver serves it — none of which can be
known without the hardware. See §9. The distinction matters because "the wheel exists" is exactly
the kind of availability fact that gets quietly upgraded into "it works on Windows."

What we add is one CI job that is honest about what it proves:

```
pip download --platform win_arm64 --only-binary=:all: --no-deps \
    PySide6-Essentials==6.11.2 shiboken6==6.11.2
```

plus the import-linter and the full `sgl/` test suite with Qt absent. **This is a packaging
availability check. It is not evidence the app runs on Windows and must never be described as
if it were.** It turns a one-off September 2026 check into something that goes red.

---

## 3. Architecture

Four layers. One of them already exists and is not touched.

```
tools/*.sh, tools/*.py        <- 35 scripts, unchanged. Zero supervision code in the launcher.
sgl/                          <- plain Python package. No daemon, no socket, no service.
sgl.db (SQLite)               <- derived tables rebuildable; authored tables exported to git.
sgl-gui (QML)  +  sgl (CLI)   <- two thin front ends over the same package.
```

### 3.1 Three commitments

**No daemon.** `tools/game-run.sh:65` sets `SCOPE="game-$APPID"` and `:314` runs
`systemd-run --user --scope --unit="$SCOPE"` (MEASURED), so "is a supervised game running" is
answerable by any process at any time. That is ground truth on the machine, not a belief inside
a process that can be SIGKILLed. See §5.3 for the limit of that claim, which is real.

**The database is rebuildable, and that property is engineered rather than assumed.** Tables
split into two sets:

- **DERIVED** (`game`, `binary`, `steam_fact`, `run`, `artifact`, `signature_hit`) — reproduced
  exactly by `sgl index --rebuild` from `~/dgx-gaming-work/runs/`, `evidence/runs/`, Steam's
  appmanifests and `appinfo.vdf`. `--rebuild` drops and recreates only these.
- **AUTHORED** (`profile`, `claim`, `claim_evidence`, `preference`, `signature`, `diagnosis`,
  `refuted_hypothesis`, `contradiction`, `journal`, `lease`, `actor`) — written by humans and
  agents, exported to reviewable text in git on every write (§4.6).

So "delete the DB and rebuild" = re-index the derived half + re-import the exported text. A
schema mistake in week 2 costs one command. **Two attached files are rejected**: SQLite foreign
keys cannot span attached databases, and the export gives the same property plus PR review.

**All shell-outs live in one file.** `sgl/tools.py`, ~15 lines per function. That file is also
the entire Windows port surface, and the entire port cost — roughly 600 lines of bash that does
not port. Stating the number is the point.

### 3.2 Modules

| Module | Job |
|---|---|
| `sgl/db.py` | DDL, migrations keyed on `user_version`, the five pragmas, `write()` context manager. |
| `sgl/index.py` | The scanner. Imports `tools/appinfo.py` as a library so the 17 MB VDF is parsed once per process, not once per query. |
| `sgl/tools.py` | Typed adapters. Subprocess only. The only module that shells out. |
| `sgl/instrument.py` | The instrument contract (§3.4). ~60 lines of functions, not a framework. |
| `sgl/claims.py` | Claim construction, verifier-class sufficiency, the composer's six questions. |
| `sgl/cli.py` | argparse. `--json` on every read, `--plan` on every write. |
| `sgl/ui/` | `QApplication` + `QQmlApplicationEngine` + QObject bridges exposing DB rows as list models. Business logic in QML: zero. |

### 3.3 Tool reuse — call as-is, absorb almost nothing

`tools/game-run.sh` is 536 lines whose header documents five separately numbered bugs: the
`timeout` orphan, the wait-on-cgroup-scope bug that killed Daikatana twice, `game_pids()`
matching Steam's own shadercache work, the unbound `USED` on first runs, and the `-applaunch`
IPC handoff that silently dropped every environment variable for the tool's entire life. None of
that is visible from outside the function. **v1 contains zero process-supervision code.**

Called as-is via `sgl/tools.py`: `game-run.sh` (QProcess, stdout streamed), `pick-runtime.py`
(parse the single `VERDICT=` line on stdout; rationale on stderr shown verbatim),
`signature-check.sh` (exit code *is* the contract: 0 plausible / 1 refuted by a working title /
2 not found — "nothing to conclude, never a silent pass"), `run-report.sh`, `find-logs.sh`,
`check-stack.sh` (all verbatim in v1), `safe-proc.sh` (the only way the launcher ever looks for
a process by name — never bare `pgrep -f`).

Imported as a library, one case: `tools/appinfo.py`.

**Not wrapped in v1 — exposed as copy-the-exact-command buttons** with appid and paths filled
in: `watch-run.sh`, `capture-hang.sh`, `experiment.sh`, `bench-ab.sh`, `ab-runtime.sh`,
`idtech4-prep.sh`, `config-snapshot.sh`, `wine-dll-loadtest.sh`, `isa-probe.sh`,
`box64-swap.sh`, `make-launcher-shim.sh`. Exposing a tool costs one string instead of an
adapter plus a JSON contract plus a parser that drifts.

Every script stays independently runnable from a shell. A result reproducible only through the
GUI is a regression in this repo's terms.

### 3.4 The instrument contract

Every instrument declares: applicability (per profile, with a reason when N/A), the artifact it
expects, and an acceptance test that checks **shape and time**, not existence. A frametime CSV
must carry MangoHud's header and its timestamps must fall inside the run window. A `gpu.csv`
whose last sample postdates the run's end is **rejected**, not accepted.

That last rule is not hypothetical. MEASURED today: 14 of 47 directories under
`~/dgx-gaming-work/runs/` contain nothing but a `gpu.csv`, and 19 orphaned
`nvidia-smi --query-gpu` processes are still appending to some of them
(`ps -eo pid,lstart,args | grep 'nvidia-smi --query-gpu'`). A naive "any sample with
`utilization.gpu > 0`" test passes all fourteen and manufactures "the game rendered" out of
desktop idle. That is `bench-ab.sh`'s gpu.csv-as-frametimes bug reproduced one layer up.

Per-run the manifest gains an `instruments` block with exactly one of PASS / FAIL / N-A + reason
per instrument. A run cannot be labelled "benchmarked" without a PASSing frametime instrument.

MEASURED: across the whole corpus there are 45 `gpu.csv` files and **zero** MangoHud CSVs, ever
(`find ~/dgx-gaming-work -name '*.csv' | grep -v gpu.csv` returns one unrelated stb test
fixture). So FAIL and N-A are currently the only reachable outcomes and the PASS path has never
been demonstrated. The contract must ship before the benchmarking UI, not after.

---

## 4. Game profile data model

Three epistemic tiers, because every published correction in this repo came from one shading
into another. **`game` has no status column.** A title's verdict is a view over claims.

### 4.1 Tier A — facts (machine-derived, never typed)

```sql
CREATE TABLE extractor (
  id            TEXT PRIMARY KEY,          -- 'pick-runtime.py', 'pe-scan', 'appinfo.py'
  git_sha       TEXT NOT NULL,
  registered_at TEXT NOT NULL
) STRICT;

CREATE TABLE binary_fact (
  id            INTEGER PRIMARY KEY,
  binary_id     INTEGER NOT NULL REFERENCES binary(id) ON DELETE CASCADE,
  key           TEXT NOT NULL,             -- bits | has_bind_section | ep_in_bind |
                                           -- imports:<dll> | renderer_candidates | moddir |
                                           -- pb_dir_present | eac_present | x87_op_count ...
  value         TEXT NOT NULL,
  linkage       TEXT CHECK (linkage IN ('static','delay','string_only')),
  derived_by    TEXT NOT NULL REFERENCES extractor(id),
  source_path   TEXT NOT NULL,
  source_sha256 TEXT NOT NULL,
  derived_at    TEXT NOT NULL,
  exit_code     INTEGER NOT NULL,
  UNIQUE (binary_id, key)
) STRICT;

-- FK enforcement is per-connection and OFF by default in the sqlite3 CLI. Every invariant that
-- matters is therefore ALSO a trigger. This one refuses a hand-typed fact.
CREATE TRIGGER binary_fact_derived_only BEFORE INSERT ON binary_fact
BEGIN
  SELECT RAISE(ABORT, 'SGL: binary_fact.derived_by must name a registered extractor')
  WHERE NOT EXISTS (SELECT 1 FROM extractor WHERE id = NEW.derived_by);
END;
```

`linkage = 'string_only'` exists because the Quake lineage `LoadLibrary("opengl32.dll")` from
inside `ref_gl.dll`, so an import-table scan calls Daikatana "no OpenGL" — exactly backwards.
`source_sha256` is why "DOOM 3 BFG is 64-bit" cannot survive a game update: the hash changes,
the fact goes stale, and staleness is visible rather than silently authoritative.

`steam_fact` is the same shape over `appmanifest_<appid>.acf` and `appinfo.vdf`: `installdir`,
`StateFlags`, every launch entry (index, type, executable, arguments, workingdir, description),
`legacykeyregistrationmethod`, `legacykeydisklocation`, and `depot_kind` (windows |
native_linux) so a native depot is never used for a Windows-side test.

### 4.2 Runtime identity and runs

```sql
CREATE TABLE runtime_build (
  id           INTEGER PRIMARY KEY,
  kind         TEXT NOT NULL,   -- OPEN enum: fex | box64 | native | prism | unknown
  identity     TEXT NOT NULL,   -- install path on Linux; image path + OS build on Windows
  digest       TEXT NOT NULL,   -- sha256 of the binary that will actually exec
  version_str  TEXT,
  provenance   TEXT NOT NULL CHECK (provenance IN ('distro','ppa','built','patched','unknown')),
  patches      TEXT,            -- JSON list of named patches
  binfmt_registered INTEGER NOT NULL DEFAULT 0,
  UNIQUE (kind, digest)
) STRICT;

CREATE TABLE run (
  id            TEXT PRIMARY KEY,          -- the run directory basename
  appid         INTEGER NOT NULL,
  machine_id    INTEGER NOT NULL REFERENCES machine(id),
  profile_snapshot TEXT NOT NULL,          -- JSON, denormalised: a later profile edit must not
                                           -- rewrite history
  rundir        TEXT NOT NULL,
  started_at    TEXT NOT NULL,
  ended_at      TEXT,
  supervision   TEXT NOT NULL CHECK (supervision IN ('supervised','adopted')),
  instrumented  INTEGER NOT NULL DEFAULT 0,
  runtime_requested TEXT,
  runtime_actual    TEXT NOT NULL DEFAULT 'unknown',
  runtime_build_id  INTEGER REFERENCES runtime_build(id),
  runtime_source    TEXT NOT NULL DEFAULT 'unknown'
                    CHECK (runtime_source IN ('proc_exe','banner','assumed','unknown')),
  render_verdict TEXT,
  proton        TEXT,
  container     TEXT,
  launch_via    TEXT,
  cwd           TEXT,
  env_set       TEXT,                      -- JSON: what we set
  env_seen      TEXT,                      -- JSON: what /proc/<pid>/environ actually held
  load_at_start REAL,
  cache_warm    INTEGER,
  stack_snapshot_id INTEGER REFERENCES stack_snapshot(id),
  manifest_schema  INTEGER,
  attributable  INTEGER GENERATED ALWAYS AS
                (runtime_actual <> 'unknown' AND runtime_build_id IS NOT NULL) VIRTUAL
) STRICT;
```

`runtime_actual` is stored as `{kind, identity, digest}` — a `runtime_build` row — not a string.
MEASURED today: `sha256sum /usr/local/bin/box64` is
`07f692e04fd99942f6fafb7ffd945b26c2f19492c1bf0cb8c86de81fef2e7203`, byte-identical to
`~/dgx-gaming-work/box64-symfix/bin/box64` — the **patched** build — while
`docs/OPEN-QUESTIONS.md` §3 says it was reverted to stock (`52de9d78…`). The patched binary's
`--version` omits the git hash the stock one prints, so only a content hash separates them. Prey
(2006) is playable only under the patched build. A launcher storing the string `box64` would run
Prey against stock, watch it fail, and record a false negative that reads like a real result.

`env_set` / `env_seen` is the direct structural fix for five instrumented runs producing zero
MangoHud CSVs: read `/proc/<gamepid>/environ` back and diff it against what was set. That
catches the drop at the moment it happens rather than inferring it from a missing artifact.

```sql
CREATE TABLE artifact (
  id          INTEGER PRIMARY KEY,
  run_id      TEXT NOT NULL REFERENCES run(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL,   -- run_json | proton_log | launch_log | engine_log | gpu_csv |
                               -- mangohud_csv | screenshot | wchan | probe_output
  rel_path    TEXT NOT NULL,
  present     INTEGER NOT NULL DEFAULT 1,
  bytes       INTEGER,
  sha256      TEXT,
  accept_status TEXT NOT NULL DEFAULT 'unchecked'
                CHECK (accept_status IN ('unchecked','pass','fail','n_a')),
  accept_detail TEXT
) STRICT;
```

Rows with `present = 0` are kept, never omitted. `find-logs.sh`'s principle: absence is
evidence. No engine log means the game never reached its own config parser.

### 4.3 Tier B — claims, with verifier class as a first-class dimension

This is the correction the red team forced and it is the most important change to the whole
design. MEASURED: 52 titles are installed; **8 distinct appids have any run directory at all**;
`README.md`'s "Tested by AGB" table has **64 rows**, Known Issues 23, Community-Reported 24.
A schema in which only machine artifacts count imports 64 human-confirmed results as grey
"unverified" while the 14 phantom `gpu.csv`-only directories import as runs with accepted
evidence. That is an inversion, and it encodes the opposite of this project's best catch — a
human toggling DLSS-NR and seeing the image was identical, beating every counter being read.

So evidence has a *class*, and each class has its own sufficiency rule.

```sql
CREATE TABLE claim (
  id             INTEGER PRIMARY KEY,
  appid          INTEGER NOT NULL,
  kind           TEXT NOT NULL,   -- launches | renders | playable | crashes | hangs |
                                  -- perf | root_cause | workaround_required
  statement      TEXT NOT NULL,   -- one sentence, no interpretation
  verifier_class TEXT NOT NULL CHECK (verifier_class IN
                   ('human_observed','instrumented','derived','community','speculation')),
  status         TEXT NOT NULL DEFAULT 'unverified' CHECK (status IN
                   ('unverified','reported','supported','contradicted','retracted',
                    'superseded','needs_rediagnosis')),
  names_runtime  INTEGER NOT NULL DEFAULT 0,   -- does the sentence name FEX/Box64/Prism?
  changes_pixels INTEGER NOT NULL DEFAULT 0,   -- is it a claim about what is on screen?
  evidence_run_id TEXT REFERENCES run(id),
  observed_by    INTEGER REFERENCES actor(id),
  observed_at    TEXT,
  visual_confirmation_id INTEGER REFERENCES artifact(id),
  control_state  TEXT NOT NULL DEFAULT 'unchecked' CHECK (control_state IN
                   ('unchecked','refuted_by_working_title','only_failing_titles','not_found')),
  stack_snapshot_id INTEGER REFERENCES stack_snapshot(id),
  source_url     TEXT,
  supersedes_id  INTEGER REFERENCES claim(id),
  retraction_reason TEXT,
  override_reason TEXT,
  import_row     TEXT,                        -- the original README cell, verbatim
  created_by     INTEGER NOT NULL REFERENCES actor(id),
  created_at     TEXT NOT NULL
) STRICT;
```

The sufficiency rule, written once and applied by **two** triggers, because an INSERT-only guard
is one `UPDATE` wide. MEASURED by the red team on the losing proposal's own proof database:
`INSERT … 'unverified'; UPDATE … 'supported'` wrote a fabricated, runtime-naming, evidence-free
claim with exit 0.

```sql
CREATE TRIGGER claim_guard_ins BEFORE INSERT ON claim
WHEN NEW.status = 'supported'
BEGIN
  -- community and speculation can never reach 'supported'
  SELECT RAISE(ABORT, 'SGL: verifier_class caps this claim below supported')
  WHERE NEW.verifier_class IN ('community','speculation');

  -- instrumented claims need a run with at least one PRESENT artifact
  SELECT RAISE(ABORT, 'SGL: instrumented claim needs a run with a surviving artifact')
  WHERE NEW.verifier_class = 'instrumented'
    AND (NEW.evidence_run_id IS NULL
         OR NOT EXISTS (SELECT 1 FROM artifact
                        WHERE run_id = NEW.evidence_run_id AND present = 1));

  -- human observation is evidence, and needs an attributable observer
  SELECT RAISE(ABORT, 'SGL: human_observed claim needs observed_by and observed_at')
  WHERE NEW.verifier_class = 'human_observed'
    AND (NEW.observed_by IS NULL OR NEW.observed_at IS NULL);

  -- NOBODY can see which JIT ran. Naming a runtime requires an attributable run,
  -- regardless of class. This is correction #3 in docs/OPEN-QUESTIONS.md, made unrepresentable.
  SELECT RAISE(ABORT, 'SGL: claim names a runtime but no attributable run supports it')
  WHERE NEW.names_runtime = 1
    AND (NEW.evidence_run_id IS NULL
         OR NOT EXISTS (SELECT 1 FROM run
                        WHERE id = NEW.evidence_run_id AND attributable = 1));

  -- a claim about pixels needs someone to have looked at the pixels
  SELECT RAISE(ABORT, 'SGL: pixel claim has no visual confirmation')
  WHERE NEW.changes_pixels = 1 AND NEW.visual_confirmation_id IS NULL;

  -- a log line offered as a cause must have been controlled against a working title
  SELECT RAISE(ABORT, 'SGL: root_cause claim has not been controlled (signature-check.sh)')
  WHERE NEW.kind = 'root_cause' AND NEW.control_state <> 'only_failing_titles';
END;

CREATE TRIGGER claim_guard_upd BEFORE UPDATE OF status ON claim
WHEN NEW.status = 'supported'
BEGIN
  -- byte-identical body to claim_guard_ins. Generated from one source; tested as one unit.
  SELECT RAISE(ABORT, 'SGL: verifier_class caps this claim below supported')
  WHERE NEW.verifier_class IN ('community','speculation');
  SELECT RAISE(ABORT, 'SGL: instrumented claim needs a run with a surviving artifact')
  WHERE NEW.verifier_class = 'instrumented'
    AND (NEW.evidence_run_id IS NULL
         OR NOT EXISTS (SELECT 1 FROM artifact
                        WHERE run_id = NEW.evidence_run_id AND present = 1));
  SELECT RAISE(ABORT, 'SGL: human_observed claim needs observed_by and observed_at')
  WHERE NEW.verifier_class = 'human_observed'
    AND (NEW.observed_by IS NULL OR NEW.observed_at IS NULL);
  SELECT RAISE(ABORT, 'SGL: claim names a runtime but no attributable run supports it')
  WHERE NEW.names_runtime = 1
    AND (NEW.evidence_run_id IS NULL
         OR NOT EXISTS (SELECT 1 FROM run WHERE id = NEW.evidence_run_id AND attributable = 1));
  SELECT RAISE(ABORT, 'SGL: pixel claim has no visual confirmation')
  WHERE NEW.changes_pixels = 1 AND NEW.visual_confirmation_id IS NULL;
  SELECT RAISE(ABORT, 'SGL: root_cause claim has not been controlled')
  WHERE NEW.kind = 'root_cause' AND NEW.control_state <> 'only_failing_titles';
END;
```

Evidence that vanishes demotes the claim. Two triggers again, because DELETE is the other hole
the red team walked through:

```sql
CREATE TRIGGER artifact_lost AFTER UPDATE OF present ON artifact
WHEN NEW.present = 0
BEGIN
  UPDATE claim SET status = 'unverified'
  WHERE evidence_run_id = NEW.run_id AND status = 'supported'
    AND NOT EXISTS (SELECT 1 FROM artifact WHERE run_id = NEW.run_id AND present = 1);
END;

CREATE TRIGGER artifact_deleted AFTER DELETE ON artifact
BEGIN
  UPDATE claim SET status = 'unverified'
  WHERE evidence_run_id = OLD.run_id AND status = 'supported'
    AND verifier_class = 'instrumented'
    AND NOT EXISTS (SELECT 1 FROM artifact WHERE run_id = OLD.run_id AND present = 1);
END;
```

A background sweep re-stats every artifact and flips `present`. That is the lost-Proton-log
incident encoded: an artifact that gets overwritten stops supporting the claim rather than
silently continuing to.

**MEASURED, 2026-09-08.** Every `sql` block in this section was extracted from this file and
executed against SQLite 3.45.1 on this box. It creates clean; `PRAGMA integrity_check` = ok;
`PRAGMA foreign_key_check` = empty. With **`PRAGMA foreign_keys=OFF`** — the sqlite3 CLI's
default, and the worst case — the guards then refused, in order: a `human_observed` claim naming
a runtime against an unattributable run; a `community` row promoted to `supported`; an
`instrumented` claim with no run; a pixel claim with no visual confirmation; an uncontrolled
`root_cause` claim; the INSERT-unverified-then-UPDATE-to-supported laundering path; and a
hand-typed `binary_fact`. The same claim without the runtime named was **allowed**, and so was
the runtime claim against an attributable run. Deleting the only artifact demoted its claim to
`unverified`. Setting `control_working_hits = 16` on one signature retracted it and flipped three
diagnoses to `needs_rediagnosis` with `root_cause` NULL. Reproduce by extracting the `sql`
blocks; do not take this paragraph's word for it, which is the whole point.

### 4.4 Signatures and the retraction cascade

```sql
CREATE TABLE signature (
  id        INTEGER PRIMARY KEY,
  pattern   TEXT NOT NULL,
  match_mode TEXT NOT NULL CHECK (match_mode IN ('fixed','ere')),
  layer     TEXT NOT NULL,   -- engine_log | proton_log | launch_log | stderr | dmesg
  meaning   TEXT,
  status    TEXT NOT NULL DEFAULT 'diagnostic'
            CHECK (status IN ('diagnostic','benign','retracted')),
  control_working_hits INTEGER NOT NULL DEFAULT 0,
  control_titles TEXT,
  control_checked_at TEXT
) STRICT;

CREATE TABLE diagnosis (
  id          INTEGER PRIMARY KEY,
  appid       INTEGER NOT NULL,
  signature_id INTEGER REFERENCES signature(id),
  root_cause  TEXT,
  status      TEXT NOT NULL CHECK (status IN
                ('root_caused','undiagnosed','retracted','needs_rediagnosis')),
  upstream_ref TEXT,
  reproducer_path TEXT
) STRICT;

CREATE TRIGGER sig_control_refutes AFTER UPDATE OF control_working_hits ON signature
WHEN NEW.control_working_hits > 0 AND NEW.status = 'diagnostic'
BEGIN
  UPDATE signature SET status = 'retracted' WHERE id = NEW.id;
END;

CREATE TRIGGER sig_retracted AFTER UPDATE OF status ON signature
WHEN NEW.status = 'retracted'
BEGIN
  UPDATE diagnosis SET status = 'needs_rediagnosis', root_cause = NULL
  WHERE signature_id = NEW.id AND status = 'root_caused';
  UPDATE claim SET status = 'needs_rediagnosis'
  WHERE kind = 'root_cause' AND status = 'supported'
    AND id IN (SELECT c.id FROM claim c JOIN diagnosis d ON d.appid = c.appid
               WHERE d.signature_id = NEW.id);
END;
```

`root_cause` is set to **NULL**, deliberately: there is nowhere to put a replacement guess.
That is `README.md`'s "do not substitute a fresh guess" enforced by the absence of a field.

A standing query runs on every app start and is shown as a banner:

```sql
SELECT * FROM signature WHERE status = 'diagnostic' AND control_working_hits > 0;
```

That is the `descriptor_buffer` retraction, mechanised. It would have fired months earlier with
nobody noticing anything.

### 4.5 Tier C — preferences

```sql
CREATE TABLE preference (
  id      INTEGER PRIMARY KEY,
  scope   TEXT NOT NULL CHECK (scope IN ('global','game','profile')),
  scope_id TEXT,
  key     TEXT NOT NULL,
  value   TEXT NOT NULL,
  set_by  INTEGER NOT NULL REFERENCES actor(id),
  set_at  TEXT NOT NULL,
  UNIQUE (scope, scope_id, key)
) STRICT;
```

No `status`, no `evidence`, no `verifier` column. **The absence of those columns is the
enforcement.** The CLI refuses `--cite` on a preference row, and the GUI renders preference text
in a visually distinct treatment.

### 4.6 Profile — the reproducible unit, and the thing exported to git

```sql
CREATE TABLE profile (
  id         INTEGER PRIMARY KEY,
  appid      INTEGER NOT NULL,
  host_class TEXT NOT NULL,        -- 'dgx-spark-linux' | 'rtx-spark-windows' | ...
  name       TEXT NOT NULL,
  runtime_build_id INTEGER REFERENCES runtime_build(id),
  required_runtime_digest TEXT,    -- checked against the live binary before launch
  proton     TEXT,
  container_appid INTEGER,
  thunk_config TEXT,               -- JSON snapshot of relevant ~/.fex-emu/Config.json keys
  launch_entry_key TEXT,
  exe_path   TEXT,
  args       TEXT,
  cwd        TEXT,
  env        TEXT,                 -- JSON
  env_placement TEXT NOT NULL DEFAULT 'direct_proton_env' CHECK (env_placement IN
                ('steam_launch_options','direct_proton_env','prefix_registry','user_settings_py')),
  resolution TEXT,
  prereqs    TEXT,                 -- JSON: ['launch once via Steam UI to write the CD key', ...]
  workarounds TEXT,                -- JSON: shim / file drops / registry overrides / symlinks
  summary    TEXT NOT NULL,        -- the owner's requirement: runtimes, thunk paths, config reqs
  rev        INTEGER NOT NULL DEFAULT 1,
  updated_by INTEGER NOT NULL REFERENCES actor(id),
  updated_at TEXT NOT NULL,
  UNIQUE (appid, host_class, name)
) STRICT;
```

`env_placement` is not decoration: where you set a variable decides whether it reaches the game
at all. `steam -applaunch` is an IPC request to the Steam daemon, which spawns the game with
*its* environment — the literal cause of five instrumented runs producing nothing.

`host_class` is the one-column portability seam `docs/SPARK-PLATFORM.md` asks for. Identity,
binary facts and most workarounds are shared; the runtime/thunk section is keyed by host class.

Every profile write also emits `profiles/<appid>-<host_class>.toml` into the repo and a line
into `journal.ndjson`. Those files are the authored half of the rebuild path, the PR-reviewable
artifact, and the thing that outlives this hardware.

### 4.7 How an unverified claim is made structurally visible

Six mechanisms, each tied to a specific published error:

1. `game` has no status column. The displayed verdict is `v_game_status`, a view over claims
   with surviving evidence. No prose edit and no UI action can promote a title.
2. `claim.status` is guarded on INSERT **and** UPDATE by identical triggers, so 'unverified'
   cannot be typed away and cannot be laundered through a second statement.
3. `run.attributable` is a generated column; a claim naming a runtime cannot cite an
   unattributable run, whoever wrote it and however confident they are.
4. A pixel claim with no `visual_confirmation_id` cannot reach `supported` — the DLSS-5 error.
5. A `root_cause` claim whose `control_state` is not `only_failing_titles` cannot reach
   `supported`. `signature-check.sh` exit 2 maps to `not_found`, never to a pass.
6. `--override-reason` records the claim at `status = 'unverified'` **plus** the override text.
   It never promotes. There is no path to `supported` that skips the evidence.

---

## 5. Agent interface and concurrency

### 5.1 The contract is the CLI

`sgl` with `--json` on every read and `--plan` on every write. Not MCP as the primary surface,
for two reasons that survive scrutiny: a human can paste and reproduce any agent action, which
is this repo's culture; and it works over SSH.

**One argument the proposals made that must be withdrawn.** "A CLI keeps `guard-bash.sh` armed"
is false. That hook is a text matcher over the Bash command string — `sgl run 2210` contains no
`timeout`, no `pgrep -f`, no `-applaunch`, so the hook fires and matches nothing. Routing agent
actions through a CLI makes the dangerous constructs *unrepresentable*, which is better, but it
does not keep the existing guards armed. Say the true thing.

An `sgl-mcp` stdio shim over the same package is fine later and should stay thin.

### 5.2 Verbs

**Read:** `index`, `ls`, `show <appid>`, `profile show`, `runs`, `report <rundir>`,
`logs <appid>`, `stack`, `advise <appid>` (pick-runtime), `signature check '<line>'`,
`events --since <seq>`.

**Write:** `lease acquire|release`, `run <appid> [--runtime] [--proton] [--seconds]`,
`profile set --key value --reason`, `claim propose`, `claim record`, `review`.

Every write accepts `--plan`, which returns the exact argv, env, systemd unit properties and the
rows that would change, and does none of it. Roughly thirty lines on top of code that already
builds the command, and it is the affordance that makes agent-to-human handoff real.

**Proposal mode is the agent's default tier.** An agent has read + propose unless it holds the
lease. A proposal is a journal row with `state='proposed'` carrying the diff, the rationale and
the evidence; the Activity screen renders a review queue; approving replays the mutation as
`actor=human, on_behalf_of=agent:<session>`. This is the only surface in the design where the
single most valuable action in this project's history — a person looking at the pixels — is
structurally required.

**Calibration:** WARN on runs and experiments, REFUSE on records and published claims.
Reproducing a known failure on purpose (32-bit OpenGL under FEX) is legitimate work, and a tool
that blocks it just gets bypassed. Every expensive error in this log was a claim, not a launch.

**Refusals name the incident they descend from.** Not "constraint violation" — "this run's
`runtime_actual` is unknown; a play session was once published as FEX when binfmt had handed it
to Box64 throughout." The existing hooks are obeyed because they explain themselves.

### 5.3 Concurrency — three classes, three rules

**Database: concurrent and mergeable.** WAL, readers never blocked, writers serialised by
`BEGIN IMMEDIATE` + `busy_timeout`. Optimistic concurrency on `profile.rev`: on mismatch return
`CONFLICT` with the current value **and a field-level diff**, never last-write-wins. The error
text says, in words, *you may not write from a stale view* — `guard-foreign-files.sh`
generalised from files to rows.

**The machine: strictly exclusive, and the primitive is weaker than it looks.** MEASURED:
`systemctl --user list-units 'game-*.scope'` answers authoritatively for `game-run.sh` launches
only. A `steam://rungameid/` launch — which the PLAY button uses — lands in Steam's own scope
and is invisible to that query; MEASURED, Steam here sits inside a terminal's `vte-spawn` scope,
so the launcher must never signal it. So:

- `run.supervision` is `'supervised'` or `'adopted'`, stored, and rendered.
- The pre-flight states **which mechanism answered**: systemd scope (authoritative, supervised
  launches only) or `safe-proc.sh` cmdline scan with a thread-count gate (advisory, may notice a
  Steam launch late). "No `game-*.scope`" must never render as "the machine is idle."
- A `lease` row (holder, purpose, TTL) carries intent; the scope query carries reality. Both
  are checked. TTL so a crashed agent cannot wedge the box.
- Adopted runs are observe-only: per-pid sampling, `instrumented=0`, teardown limited to an
  explicit pid list plus `wineserver -k`. They are structurally refused as the basis of any
  telemetry-derived claim, and they are visibly second-class in both UI and CLI.

**Foreign config: not lockable.** `OptiScaler.ini`, `UserSettings.json`, prefix `user.reg`,
`localconfig.vdf`, `ReShade.ini` are owned by programs that are not clients. Content hash
captured at read, re-checked at write; mtime is second-granular and collides. v1 does not write
them at all — it shows their hash, last-snapshot state and a copy-the-command button for
`config-snapshot.sh save`. The launcher must also never write launch options into
`localconfig.vdf` while Steam is running, because Steam rewrites it on exit.

### 5.4 Mutual visibility

One append-only table:

```sql
CREATE TABLE journal (
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,
  ts         TEXT NOT NULL,
  actor_id   INTEGER NOT NULL REFERENCES actor(id),
  on_behalf_of INTEGER REFERENCES actor(id),
  verb       TEXT NOT NULL,
  target     TEXT NOT NULL,
  before_json TEXT,
  after_json  TEXT,
  rationale  TEXT,
  override_reason TEXT,
  state      TEXT NOT NULL DEFAULT 'applied'
             CHECK (state IN ('applied','proposed','approved','rejected'))
) STRICT;
```

`profile.rev` is the `seq` of its last mutation, so the audit trail and the change feed are the
same table. Do not build two systems. The GUI uses `QFileSystemWatcher` on the DB file plus a
journal tail — **not** a 500 ms poll, which is the wrong shape for the mechanism the whole
"simultaneous" requirement rests on. The agent calls `sgl events --since <seq>`.

**No ephemeral toasts for anything an agent does.** A toast that vanishes is invisible to a human
who stepped away and useless to an agent reading state. Agent actions land in a persistent
Activity feed with unread marks.

Every RPC carries `actor {kind, id, session_url?}`. Record the Claude session URL when supplied —
this repo already stamps `Claude-Session:` into commits; this is the same discipline one layer
down.

---

## 6. Visual design

### 6.1 Foundation, and what is inferred

Build on **NVIDIA Elements** (`github.com/NVIDIA/elements`), NVIDIA's own Apache-2.0 product-UI
design system, taking values and vocabulary — **not** the Web Components, which are a browser
runtime this app deliberately does not have.

**INFERRED, not re-verified in this session:** that the repo exists, is Apache-2.0, is owned by
the NVIDIA GitHub org, and bundles Inter under OFL 1.1. The visual survey verified all of that
via the GitHub API. **Settled by:** one API call against `/repos/NVIDIA/elements` plus reading
`projects/themes/src/fonts/LICENSE.md`. Do that before committing the token file.

**Also inferred, and it is the one everyone gets wrong:** `#76B900` as "official NVIDIA green"
comes from third-party brand-colour aggregators, not NVIDIA's brand portal. The values below
were resolved from Elements' own OKLCH tokens by the visual survey; they are close to `#76B900`
but they are not a quotation of an official brand spec, and this document does not claim to be
one. Design-aggregator sites are demonstrably unreliable here — one claimed NVIDIA's radius
scale "tops out at 2px" when the source file shows 0/4/6/8/14/24/48/999.

**The tension, stated rather than resolved.** The brief says match the NVIDIA aesthetic. NVIDIA's
brand-usage page says verbatim *"Do not mimic or imitate NVIDIA branding and visual style in your
communication, even if you're a partner or sponsored by NVIDIA."* Building on Elements — which
NVIDIA published for third parties — and using no marks is the defensible reading, but adopting
NVIDIA's actual design system for an app aimed at NVIDIA hardware owners is the trade-dress half
of implied endorsement, and a non-affiliation line in About addresses the name only. That is a
lawyer's question, not a designer's. **Name: ship as "Spark Game Launcher." DECIDED by AGB, 2026-09-08.** The reasoning, recorded
because it is the defence if it is ever needed: the name is crisp and accurate, and contains **no**
NVIDIA trademark — no "DGX", "RTX", "NVIDIA", "CUDA", "GeForce", "Grace" or "Blackwell". "Spark"
is used descriptively of the class of machine targeted.

**And the visual identity was changed to match the argument rather than merely assert it
(AGB, 2026-09-08).** Trade dress is the harder half of this question, so the app now leads with
the **DGX Spark chassis gold** and adds **arcade neon** — blue, purple, pink — to read squarely as
a *gamer app*, not an NVIDIA app. **NVIDIA green is removed entirely: zero occurrences.** That is
the single highest-leverage change available and it costs nothing functionally, because green was
only ever the action colour and gold now carries that role.

Discipline preserved through the change: an arcade palette is loud, and this UI's entire purpose is
that an unverified claim must not look exciting. So **every hue has exactly one job** — gold =
action and identity; neon blue = navigation and focus; neon purple = agent authorship (provenance,
never status); neon pink = REGRESSED; red = BROKEN; and verified / unverified / retracted stay
**neutral, carried by shape**. No status can borrow the energy of the action colour.

Backed by disclaimers in **both** places, because one nobody opens is not a disclaimer: an About
screen in the app, and `NOTICE` plus a README banner in the repository, each stating the project is
unofficial, not-for-profit, uses no NVIDIA marks or brand colours, and will address any vendor
concern promptly. Mockup: `docs/mockup/launcher-mockup.html`.

This remains a lawyer's question if the project ever grows a commercial dimension; the steps above
are what a careful non-lawyer can do, and they are substantive rather than cosmetic.

### 6.2 Palette (resolved hex, committed once)

Ship a flat `design-tokens.json` of resolved hex, not OKLCH. Three brand-green stops are outside
sRGB, so two surfaces converting independently will disagree by a shade. Convert **once**,
centrally, commit the result.

| Role | Hex | Use |
|---|---|---|
| shell | `#000000` | window chrome, icon rail |
| canvas | `#0B0C0F` | app background |
| container | `#191A1F` | cards, panels, table bodies |
| container-accent | `#1F2128` | table headers, code blocks |
| overlay | `#24262D` | modals, menus, row hover |
| border-muted | `#292B32` | hairline separators |
| border | `#2F333C` | panel edges |
| border-emphasis | `#434753` | focused field, selected row |
| text | `#C6CDE2` | body — 12.32:1 on canvas |
| text-strong | `#E6EEFF` | headings, primary numbers |
| text-muted | `#979EB2` | metadata — 7.31:1 |
| text-disabled | `#5F636F` | **3.26:1 — fails AA. Disabled and non-text only.** |
| accent | `#7EB600` | primary button fill |
| accent-strong | `#89BF28` | accent text/icon, focus ring |
| accent-dim | `#6FA200` | pressed |
| spark-gold | `#C9A973` | app identity chrome only |

Contrast ratios are WCAG 2.x, computed by the visual survey from these hex values. **Black text
on green is mandatory** — 8.58:1; white on green is 2.41:1 and is a hard no.

`spark-gold` is taken from third-party reports of the Spark chassis finish and the specific value
is chosen for contrast, not sampled. It exists so the app has a face of its own rather than being
a GeForce skin. **Settled by:** AGB photographing the unit under neutral light.

**The one load-bearing colour rule.** Green is the ACTION colour and appears at most twice per
screen: the primary button and the focus ring. **Therefore "verified" is not green.** If green
meant both "the thing you click" and "the claim you can trust," an unverified title reads as
verified in peripheral vision — the single failure mode this app must not have. Green is never a
status, never a chart series, never a success tick, never a card border.

### 6.3 Typography

**Inter** (OFL 1.1) for UI, **JetBrains Mono** (OFL 1.1) for every machine value — appids, log
lines, hex, paths, frametimes, run ids. JetBrains Mono over Elements' Roboto Mono: better 0/O
and l/1/I separation for log text, and unambiguous licensing where Roboto Mono's is mid-relicence.

**MEASURED on this box: `fc-list` finds zero Inter and zero JetBrains Mono.** So they must be
vendored into a Qt resource with their OFL texts, not depended on. Specifying fonts absent from
the only machine that exists is the font equivalent of advertising `mangohud: on` and producing
no CSV. Note OFL's Reserved Font Name clause: a modified face may not still be called "Inter".

Enable Inter's `zero` (slashed) and `ss02`/`ss04` disambiguation sets app-wide. **Unverified:**
whether Inter ships `tnum` (tabular figures), on which every FPS and byte-count column depends.
**Settled by:** `fonttools` listing GSUB features on the built file — one command.

Scale (Elements', unchanged): body 14/1.375, label 14/500, heading 18/1.375/600, heading-lg
20, heading-xl 24/600, display 40/1.12, code 14/1.5. 8px spacing grid, 32px controls, 6px radius
on controls and 8px on cards. No all-caps condensed italics, no second display face, no
gradients, no glass, no ambient shadows, no oversized radii — those are the gamer-launcher tells,
and Elements' own "Don't" list forbids them independently.

### 6.4 Screen inventory

1. **Library** — the default, and it opens as a **dense list**, not a cover grid. The primary
   question is not "which box art do I like," it is "does this work, under which translator, with
   what evidence." 40px rows across 52 titles: thumb | title | appid (mono) | size | render API |
   runtime verdict | evidence chip | last run | `runtime_actual` | FPS. Sortable and filterable
   on every column. Filters: Untested · Unattributable · Human-observed only · Stale against
   current stack · Open contradiction · Depends on a translator build not installed. A grid
   toggle exists; an untested card gets a dashed border on the whole card, visible at thumbnail
   size, and no hover glow — unmeasured is not rewarded.
2. **Title** — a page, not a modal. Two first-class buttons (§6.6). Tabs: Profile · Runs ·
   Evidence · Diagnosis · Dead ends.
3. **Run** — one run, one page: phase timeline (preflight → scope started → first pid → first
   game-shaped process → first GPU activity above the idle baseline → first frametime sample →
   exit), the artifact inventory with PASS/FAIL/N-A and reason, absent artifacts greyed and
   struck, `run-report.sh` verbatim, and archived logs inline with signature highlighting.
4. **Claim Composer** — the `log-result` skill as a screen, and the only route to `supported`.
5. **Signatures** — one row per signature with `control_working_hits`, plus the standing banner.
6. **Contradictions** — open conflicts with their literal resolving command. Seeded with the
   Daikatana row (recorded "excellent through FEX's 32-bit path" while `wgl-formatsweep32.c`
   measures FEX setting 0 of 320 pixel formats) whose resolver is `tools/ab-runtime.sh 242980`.
7. **Activity** — the journal as a feed, plus the proposal review queue.
8. **Machine** — `check-stack.sh` live, the stack fingerprint with hashes, binfmt registrations
   spelled out, and **whether a display output is even attached**. MEASURED right now:
   `DISPLAY=:0 xrandr --current` reports `current 0 x 0`. An agent could start a "performance
   run" headless today and get a run that looks complete and means nothing.
9. **About** — non-affiliation line, Elements attribution, OFL notices.

The Profile tab is the differentiating surface: a definition list, three groups, every row
`label | value | provenance (human / agent / extractor / imported, and when)`.

- **Translation** — requested runtime, actual runtime, and the runtime **build identity with its
  digest** as its own row, red when the live binary's hash differs from
  `required_runtime_digest`. If actual is unknown the card takes the unknown treatment and says
  outright: *this run cannot be attributed to a translator.*
- **Graphics path** — five pill nodes with hairline connectors: render API → DXVK/VKD3D/native
  GL → thunk state → driver → GPU. Colour a node only when it is the failing one. The one place
  a diagram beats a table, because that chain is this project's entire mental model. On Windows
  the chain has three nodes and the same widget draws it.
- **Config** — Proton (read from the prefix's `config_info`, labelled as such), launch options
  with `%command%` position preserved, `env_placement`, cwd, workarounds, and resolution shown
  **beside the display's actual current mode** with an inline mismatch flag. That flag is not
  cosmetic: a 2560-wide window on a 5120 display broke mouse capture and cost a day as a
  suspected translator bug.

### 6.5 Signalling verified / unverified / broken

Evidence state is a **separate axis** from run state and is encoded **shape-first**, because hue
cannot carry it: under deuteranopia the visual survey measured `#89BF28` and `#EBA002` at 1.10:1
apart — effectively the same colour.

| State | Encoding |
|---|---|
| VERIFIED | solid chip, filled ✓, **mandatory trailing mono evidence path**, plus the verifier class as a word: `human-observed` / `instrumented` |
| UNVERIFIED | no fill, 1px **dashed** outline, hollow ○ — the dash is the signal, colour is decoration |
| REPORTED | dashed outline + link glyph, source URL required; community rows can never be more |
| BROKEN | solid fill + 3px solid left bar + ✕ |
| REGRESSED | amber ▲ — worked before, fails now; derived from run history, and nothing else in this ecosystem knows it |
| RETRACTED | violet ⊘, claim text **struck through but still readable**, retraction reason one line below |
| STALE | any of the above plus a diagonal hatch; the tooltip names which stack layer moved |

**Mechanism, not convention.** `StatusChip`'s VERIFIED variant takes `evidence_ref` as a required
argument and renders UNVERIFIED when it is null or does not resolve on disk. It is not possible
to draw a verified badge with nothing behind it.

A metric tile with no backing artifact renders as an em-dash in `#5F636F` labelled "no artifact"
— never 0, never blank. A launcher showing "0 FPS" would have hidden the zero-MangoHud-CSV bug
for another month.

Agent-authored entries carry a violet `#9A86FC` marker; human entries a neutral one; never green
for either, because green is action, not identity.

Acceptance criterion on the Library milestone, not an aspiration: **screenshot it in greyscale
and under a deuteranopia filter and every evidence state must still be readable.**

Every panel and field carries a stable id shown in the inspector
(`profile.translation.runtime_actual`). An agent addresses it; a human says it out loud.

Ship a `docs/DESIGN.md` in Elements' own format — machine-readable front matter plus prose rules
— so an agent restyling a screen cannot invent a hex value. Same reasoning that produced
`tools/` and `.claude/hooks/`.

---

## 7. Milestones

**Effort is stated in sessions, not weeks.** A session is an evening or a weekend afternoon. For
a part-time solo maintainer who also has to test games on the same machine, M0–M3 is realistically
two to three months of calendar time, and M4–M6 is the same again. Anyone quoting "week 2" for
this is quoting full-time weeks that do not exist.

### M0 — Fix what is provably broken. **This is a gate, not a nice-to-have.** (2 sessions)

No launcher code. Every item below is currently producing wrong data that M1 would ingest.

- Kill the 19 orphaned `nvidia-smi --query-gpu` samplers, enumerated with
  `tools/safe-proc.sh list` — never `pkill -f`. Move `game-run.sh`'s `trap cleanup` above
  `TELE=$!` (MEASURED: lines 492 and 128, with seven `die` sites and the `DRY_RUN` exit between).
- Quarantine the 14 `gpu.csv`-only run directories. They are sampler leak output, not runs.
- Fix `bench-ab.sh:67` — `ls -t "$OUT"/*/*.csv | head -1` matches `gpu.csv`; select by MangoHud
  header, and print "(no frametime artifact)" rather than numbers.
- `PROTON_LOG_DIR=$RUNDIR` in `game-run.sh`, so the Proton log is **born** inside the run
  directory instead of copied at teardown by a trap SIGKILL bypasses. This is the fix for the
  filename collision that permanently destroyed the id Tech 4 x87 crash's attribution.
- `printf 'RUNDIR=%s\n' "$RUNDIR"` immediately after the mkdir.
- `"schema": 2` in `run.json`, plus the interpreter digest. MEASURED: all 20 `runs/` manifests
  carry an identical 13 keys and none carries `render_verdict`, which `game-run.sh:476` now
  emits — a consumer cannot distinguish "old manifest" from "new manifest, field missing."
- Read `/proc/<gamepid>/environ` back and store it beside what was set.
- Reconcile `docs/OPEN-QUESTIONS.md` §3 with the measured fact that `/usr/local/bin/box64` is the
  patched build, and decide which build should be installed.
- Correct `docs/SPARK-PLATFORM.md`'s RTX Spark paragraph (§9).
- Invert `signature-check.sh` to resolve title status from the DB rather than from `README.md`
  (MEASURED: it opens `README.md` at line 47). One function. Leaving the control parsing the
  prose it polices while the DB holds a different status is a contradiction shipped on day one.

**Demo:** `ps -eo args | grep -c 'nvidia-smi --query-gpu'` returns 0. A fresh run writes
`proton.log` inside its own directory, a `run.json` with `schema: 2` and an interpreter digest,
and an env diff showing exactly which variables pressure-vessel rewrote. `bench-ab.sh` on a run
with no MangoHud CSV prints "(no frametime artifact)" instead of 600 FPS.

### M1 — Schema, importer, `sgl index` / `sgl ls`. CLI only, no Qt. (4 sessions)

`sgl/db.py` with the DDL of §4, all six triggers, and a test **per invariant** run against a raw
`sqlite3` connection with no pragmas set — because FK enforcement is per-connection and off by
default in the CLI, which is exactly the writer the whole schema-over-daemon argument is about.
Explicit tests for the two laundering paths the red team walked through: INSERT-then-UPDATE, and
DELETE-the-artifact.

Importer in three passes, each row stamped with the pass that produced it and the original
markdown cell kept verbatim in `import_row`:

- **Pass 1**, zero judgement: 47 `runs/` directories (20 manifests) + 13 `evidence/runs/`
  directories (13 manifests) into `run` + `artifact`. 14 will correctly land unattributable.
- **Pass 2**, mechanical: 52 appmanifests, `appinfo.vdf`, `pick-runtime.py` and a PE/ELF scan
  into `game` / `steam_fact` / `binary_fact`.
- **Pass 3**, human-reviewed: 64 Tested-by-AGB rows as `human_observed` (supported, with AGB as
  `observed_by`, the README cell verbatim, and `names_runtime=1` rows correctly refused); 23
  Known Issues as claims + diagnoses; 24 Community-Reported as `community` (capped at
  `reported`); 7 Likely-to-Work as `speculation`. Seed `signature` from `run-report.sh`'s three
  lists and `docs/DIAGNOSTICS.md`; `refuted_hypothesis` from the dead-ends table;
  `contradiction` with the Daikatana row.

**Demo:** `sgl index --rebuild` is idempotent and reproduces the derived tables exactly.
`sgl ls --filter unattributable --json` prints, in one command, the answer nobody has today.
`sgl claim record --appid 242980 --says 'Daikatana runs excellently under FEX' --class human_observed`
is **refused**, naming the run, because those runs predate `run.json` and carry no
`runtime_actual` — while the same claim without the runtime is accepted.
`sgl signature set-control DescriptorSizeEXT --working-hits 16` flips three AAA diagnoses to
`needs_rediagnosis` with `root_cause` NULLed, in one command.

### M2 — Library window, read-only. (4 sessions)

`tools/setup-launcher.sh`. `Theme.qml` singleton with the committed tokens. `StatusChip.qml`
whose VERIFIED variant demands a resolving `evidence_ref`. The Library list (`ListView` +
delegate — not `TableView`; 52 rows do not need it and `TableView` is where a week goes), sort,
filters, search. Vendored fonts in a `.qrc`.

**Demo:** all 52 installed titles in one dense sorted list with render API, runtime verdict,
evidence chip and last `runtime_actual`. This alone replaces grepping a 2,878-line README.
Acceptance: the greyscale and deuteranopia screenshots.

### M3 — The two launch buttons. (5 sessions)

`sgl/tools.py::game_run` — QProcess around `game-run.sh`, unmodified, stdout streamed. PLAY via
`steam://rungameid/` opening an **adopted** run. The typed pre-flight, each check returning
`{code, status, detail, remedy}` and naming which mechanism answered the busy question. The
lease table. `sgl run` doing the identical thing through the identical code path.
`QFileSystemWatcher` + journal tail.

**Demo:** TEST RUN on Quake 4 (2210) — pre-flight rows, streamed output, a run landing with
`runtime_actual` read from `/proc/<pid>/exe` and hashed. From another terminal `sgl run 2210
--json` is refused with `game-2210.scope is active`. Both actors see the same machine state with
no daemon between them.

### M4 — **Stop and measure the product bet.** (1 week of ordinary use, zero code)

Give AGB M2 + M3 and nothing else, and count how many times he opens the launcher versus Steam.
The two-button split is the central product decision and it is entirely unvalidated; nothing in
the design forces the launcher to be where Play happens. If the answer is "only when doing
science," the correct response is to build the gamer-facing job nobody scoped — disk and download
management against a 259 GB margin on a 916 GB disk with 303 GB of games installed and NBA 2K27
alone at 102 GB (MEASURED: `df -h`) — not three more evidence screens.

### M5 — Run screen, evidence surface, Claim Composer. (5 sessions)

Phase timeline. Artifact inventory with PASS/FAIL/N-A. `run-report.sh` and `find-logs.sh`
verbatim. Inline log viewer with signature highlighting, each highlight rendered UNVERIFIED until
the control has run, with the one-click check that flips it to RETRACTED in place when a working
title emits the same line. Copy-the-exact-command buttons for the eleven unwrapped tools. The
Claim Composer: six required fields, "specific counter or generic hook?" as a **radio**, the
signature control inline with exit 2 shown as a distinct third state, a **required falsifier
note** on every declared counter, and a mandatory screenshot A/B slot for any pixel claim.

### M6 — Profiles, the agent surface, Machine screen. (5 sessions)

Editable Profile tab with per-row provenance and the pill chain. `--plan` on every write.
Proposal mode and the review queue. `sgl export` writing `profiles/*.toml` and `journal.ndjson`.
The staleness sweep and the artifact-presence sweep. Seed profiles for the ~15 titles whose
per-title knowledge is already written down (Cyberpunk's NR file set, Witcher 3's launch string,
NBA 2K27's `option1` entry, HL2's Proton 10 pin, the id Tech 4 family's box64 requirement and
CD-key prerequisite).

**Demo:** an agent runs `sgl profile set 2210 --runtime box64 --reason 'FEX cannot SetPixelFormat
for 32-bit GL, per probes/wgl' --plan`, shows the human the diff, proposes; the human approves in
the GUI and the journal records `human on_behalf_of agent`.

---

## 8. Risk register

| # | Risk | Mitigation or acceptance |
|---|---|---|
| 1 | **The corpus the launcher indexes is ~30% bug output.** 14 of 47 run dirs are sampler leak; a naive acceptance test passes all of them and manufactures "the game rendered." | M0 is a **hard gate** on M1. The indexer rejects any `gpu.csv` whose last sample postdates the run's end and quarantines the 14 as `sampler_leak_artifact`. |
| 2 | **Human observation scoring zero.** 64 human-confirmed results would import as grey while phantom directories import as evidence. | `verifier_class` as a first-class dimension with per-class sufficiency (§4.3). `names_runtime` still requires an attributable run — nobody can see which JIT ran. |
| 3 | **Schema-enforced evidence can be satisfied by a present, real, irrelevant artifact.** This is exactly the "3,983 evaluates" failure, and no constraint prevents it. A green VERIFIED chip makes a wrong claim *more* expensive than prose did. | **Accepted, explicitly.** Partial mitigations only: the Claim Composer's specific-counter radio, the required falsifier note, the mandatory pixel A/B, and proposal mode putting a human's eyes in front of it. The judgement is irreducible. |
| 4 | **The trigger layer is bypassable if written naively.** MEASURED on the source proposal's own database: INSERT-then-UPDATE laundered a fabricated claim, DELETE-the-artifact left it supported, and FK enforcement was silently off. | Guards on INSERT **and** UPDATE with identical bodies generated from one source; `artifact_deleted` mirroring `artifact_lost`; no invariant relies on a foreign key; a test per invariant against a raw CLI connection. |
| 5 | **The mutual-exclusion primitive cannot see the PLAY button.** `game-*.scope` covers supervised launches only; `steam://rungameid/` is invisible to it and to `guard-bash-match.py`. | `run.supervision` stored and rendered; the pre-flight names which mechanism answered; add a `steam://rungameid` rule to `guard-bash-match.py`. Adopted runs are visibly second-class. |
| 6 | **The rebuildable-index property dies the moment anything is authored.** | Derived/authored split with authored state exported to git text on every write (§3.1). Designed in at M1, not retrofitted. |
| 7 | **The launcher gets used for testing and never for playing, and the profiles rot.** | M4 exists for exactly this: a week of ordinary use, measured, before building more evidence screens. Honest fallback: build disk/download management, the one gamer-facing job nobody scoped. |
| 8 | **MangoHud has never produced a CSV on this machine, ever.** Every instrument demo is currently the FAIL path. | The instrument contract ships before the benchmarking UI, and reports N-A with a reason rather than an empty column. Upstream v0.8.4 ships an i386 layer, so the 32-bit Vulkan gap is closable — build it from source inside the FEX RootFS. |
| 9 | **A profile can depend on a translator build that is not installed.** Prey needs the patched box64; the machine's documented state is wrong. | `required_runtime_digest` compared against the live binary before launch; refuse or warn loudly. `box64-swap.sh` remains the mechanism. |
| 10 | **Two sources of truth — DB fields vs README prose — will drift.** | Accepted knowingly. One-directional export plus `sgl lint --readme` comparing exported profiles against the README rows that cite them. A tool, not a hope. |
| 11 | **GPL-only Qt modules import with one line and would GPL an MIT repo.** The surveys' ban list was wrong in both directions. | `constraints.txt` refusing `PySide6` and `PySide6-Addons`, plus a CI import-linter reading the list from Qt's licensing page. Ban list corrected: add NetworkAuth and Canvas Painter, drop Charts. |
| 12 | **Qt classes desktop Linux-on-Arm as a reference platform benchmarked on a Raspberry Pi 5.** A driver-specific RHI bug here may sit unfixed. | Two backends were verified working (GL and Vulkan); `QSG_RHI_BACKEND` is the escape hatch; keep a `software` fallback path. |
| 13 | **glibc 2.39 is an exact floor with no headroom**, and the version sets with a `win_arm64` wheel and with a `manylinux_2_31` wheel are disjoint. | `setup-launcher.sh` asserts glibc ≥ 2.39 and fails naming DGX OS 7; record the OS and glibc version in the `machine` row. Audit the other units. |
| 14 | **Adopted runs cannot be supervised atomically and there is no authoritative "what is Steam running" signal.** | Stated in the UI, stored in the schema, never papered over. Adoption uses `safe-proc.sh` with a thread-count gate and may notice a launch late. |
| 15 | **Community rows carry third-party source URLs — untrusted input by this repo's own rule.** | `verifier_class = 'community'` is a hard ceiling at `reported`, enforced by the trigger, not a label. |
| 16 | **Over-modelling.** ~18 tables and six triggers is a lot for a launcher that must first show a game list. | The load-bearing parts are the tiering, `attributable`, verifier class, and evidence presence. Contradictions, refuted hypotheses and staleness can land later without changing keys — and the derived half is rebuildable. |

---

## 9. Open questions

**The RTX Spark premise — and the brief's own framing is probably wrong.**

The ask says "the RTX Spark is the same GB10 silicon running Windows, so many of the same
CPU-translation and thunk issues are expected to follow." Two claims in one sentence, and both
look wrong.

1. **Different machine, probably different SoC.** RTX Spark is a separate NVIDIA product;
   secondary sources attribute it to an **N1X** SoC in at least two configurations with
   different core counts, CUDA counts and memory, and the consensus on NVIDIA's own developer
   forum is that DGX Spark itself will never officially run Windows. UNVERIFIED — all of that is
   third-party. **Settled by:** NVIDIA's own RTX Spark product/spec page or the CUDA-for-RTX-Spark
   release notes. **This matters now, because the unverified claim is already laundered into
   `docs/SPARK-PLATFORM.md`** — the file whose opening line declares it the single source of
   truth for hardware facts — as "RTX Spark ... same core platform," sourced from vendor
   positioning and never controlled. That is the `descriptor_buffer` pattern with the ink still
   wet, and correcting it is an M0 item.

2. **The issues do not follow — and that guts the port's value, not its cost.** Windows on Arm
   emulates x86 and x64 through Microsoft's **Prism**, in user mode. No Wine, no Proton, no DXVK,
   no VKD3D, no pressure-vessel, no `binfmt_misc`, no FEX, no Box64. The four Box64 bugs, the
   FEX 0-of-320 pixel-format failure and the x87 tag-word work are facts about translators that
   will not be running there. Prism runs 32-bit x86 as a first-class case, so this repo's
   defining 32-bit-OpenGL story has no analogue at all.

   The sharper consequence nobody drew: **on the Windows host class, `runtime`, `thunk_config`,
   `proton` and `container_appid` are all NULL.** Those are the differentiating columns of this
   product. The Windows port is therefore not "a recompile plus a Supervisor implementation" or
   "one column and one file" — it is a *different product* sharing only the evidence discipline,
   the per-title identity and workaround rows, and the method. That decision should be made now,
   on the record, rather than discovered at port time.

   **What transfers, honestly:** the three-tier model, `claim` / `artifact` / `signature` /
   `contradiction` / `refuted_hypothesis`, the verifier-class discipline, the claim guards, the
   profile *structure* (launcher quirks, foreign-owned config, resolution/window traps, DRM and
   shims), and the SQLite file itself. **What does not:** ~600 lines of bash, the entire
   supervision layer, and every translator finding in this log.

**The cheapest experiment that settles whether any translator knowledge transfers:** run
`tools/isa-probe/` under Prism on day one. Its expected answers come from the Intel SDM, not from
whichever runtime ran first, so it is a valid conformance suite for **any** x86 implementation —
no game, no GPU, no install, seconds to run. It would say immediately whether Prism shares the
x87 or CPUID defects found here. Bank it in `docs/OPEN-QUESTIONS.md` now.

**The rest, each with its cheapest settling experiment:**

| Question | Settled by |
|---|---|
| Does the PySide6 `win_arm64` wheel actually run on an RTX Spark, and which RHI backend does Qt Quick pick? | `pip install PySide6-Essentials==6.11.2` on arm64 CPython there, run the survey's `qmlprobe.py` unchanged, read the `Creating QRhi with backend` line. Cannot be settled without the hardware. |
| Does the x86-64 MangoHud Vulkan layer load into an FEX-hosted game and write a CSV? | One run of a 64-bit DXVK/VKD3D title with `PROTON_LOG_DIR` set, then `ls` the run directory. One launch, one `ls`. Layer-path visibility inside FEX is already ruled out as the blocker. |
| Does upstream's i386 MangoHud layer instrument a 32-bit DXVK title (HL2) under FEX? | Build v0.8.4 from source inside the FEX RootFS — the same route the isa-probe tooling uses for x86 binutils — and run HL2. |
| Is `/usr/local/bin/box64` supposed to be the patched build right now? | `tools/box64-swap.sh status` plus a decision, then make the launcher record the digest so the question cannot recur. |
| Which DGX OS release do AGB's other Spark units run? | `cat /etc/dgx-release` on each. Decides whether the no-sudo installer works there at all. |
| Does Inter ship `tnum`? | `fonttools` GSUB listing on the built face. One command; every numeric column depends on it. |
| Is NVIDIA Elements what the visual survey says it is? | One GitHub API call on `/repos/NVIDIA/elements` + read `projects/themes/src/fonts/LICENSE.md`. Do it before committing `design-tokens.json`. |
| What is the actual sampled colour of the Spark chassis? | AGB photographs the unit under neutral light and samples it. |
| Is "Spark Game Launcher" an acceptable name, given Apache-2.0 grants no trademark rights and the aesthetic requirement is itself trade dress? | Ten minutes of an actual legal opinion. Not a design question, and not the architect's call. Ship the non-affiliation line and the no-wordmark rule regardless. |
| Does the two-button PLAY/TEST split earn daily use? | M4: a week of ordinary use, counted. Cannot be settled by argument. |
| Should README's results tables eventually be generated from the DB? | Generate one section from the seeded DB and see whether the prose survives. AGB's call, not the architect's — the CORRECTION blocks are the point of this repo. |

---

*Not affiliated with or endorsed by NVIDIA Corporation. Colour, spacing and type scales derived
from NVIDIA Elements (Apache-2.0, Copyright 2024-2026 NVIDIA Corporation); no NVIDIA trademarks
are used.*
