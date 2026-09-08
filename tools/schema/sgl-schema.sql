-- sgl-schema.sql — Spark Game Launcher, core schema.
--
-- WHY THIS FILE EXISTS, AND WHY IT IS TESTED
--   The launcher's one job that nothing else does is to make an unverified claim
--   IMPOSSIBLE to render as verified. That cannot be a UI convention, because a
--   UI convention is one careless INSERT away from being false. It has to be a
--   database constraint.
--
--   Two design rules follow, both learned the hard way:
--
--   1. EVERY GUARD FIRES ON INSERT *AND* UPDATE. A guard that only checks INSERT
--      is laundered by `INSERT ... 'unverified'; UPDATE ... 'supported'`.
--   2. NO GUARD MAY DEPEND ON FOREIGN KEYS BEING ENFORCED. `PRAGMA foreign_keys`
--      defaults to OFF in the sqlite3 CLI, which is exactly the writer a
--      "schema-over-daemon" design invites. Guards therefore do explicit
--      SELECTs instead of trusting a reference to exist.
--
--   tools/schema/test-guards.py executes every laundering path against a real
--   database with foreign_keys=OFF and asserts refusal. If you change a trigger,
--   run it.
--
-- SCALE THIS IS BUILT FOR
--   ~5,000 games (Steam 2,999 + GOG 2,039 + itch.io), ~7,000 entities with DLC,
--   of which 1-3% can be installed at once. So: identity is three levels
--   (title -> source -> install), "tested then uninstalled" is the normal state,
--   and CLUSTERS are how one probe legitimately covers thousands of titles.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;   -- advisory: the guards below do NOT rely on this

-- ═══════════════════════════════════════════════════════════════════════════
-- IDENTITY — three levels, because "Quake 4 on Steam" and "Quake 4 on CD" are
-- the same GAME with different DRM, launcher and patch level. Some findings
-- transfer between them and some emphatically do not.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE title (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL,
  sort_name   TEXT,
  engine      TEXT,                 -- 'id Tech 4', 'Unity IL2CPP', ...
  -- Engine is NOT a machine fact today: nobody has written the classifier. It is
  -- marked with how it was set so it can never be displayed as Tier A.
  engine_by   TEXT CHECK (engine_by IN ('human','agent','extractor')),
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX ix_title_name ON title(name);

CREATE TABLE source (
  id           INTEGER PRIMARY KEY,
  title_id     INTEGER NOT NULL REFERENCES title(id) ON DELETE CASCADE,
  platform     TEXT NOT NULL CHECK (platform IN ('steam','gog','itch','disc','other')),
  -- Steam appid, GOG product id, itch game id, or for physical media a
  -- fingerprint of the disc. NOT NULL on purpose: SQLite treats NULLs as
  -- distinct in UNIQUE, so a nullable id would silently permit duplicates.
  platform_id  TEXT NOT NULL,
  edition      TEXT,
  drm          TEXT,                -- 'steamstub','none','securom','denuvo',...
  launcher     TEXT,                -- 'ubisoft-connect','rockstar','none',...
  UNIQUE (platform, platform_id)
);
CREATE INDEX ix_source_title ON source(title_id);

CREATE TABLE host (
  id           INTEGER PRIMARY KEY,
  host_class   TEXT NOT NULL CHECK (host_class IN ('dgx-spark-linux','rtx-spark-windows','other')),
  dmi_family   TEXT,                -- 'DGX Spark' even on an HP-badged box
  cpu          TEXT, mem_bytes INTEGER, driver TEXT, os TEXT, kernel TEXT,
  fingerprint  TEXT NOT NULL UNIQUE
);

CREATE TABLE install (
  id           INTEGER PRIMARY KEY,
  source_id    INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
  host_id      INTEGER NOT NULL REFERENCES host(id),
  path         TEXT,
  size_bytes   INTEGER,
  -- Present on disk RIGHT NOW. ~98% of a 5,000-title library is 0 forever, so
  -- this is deliberately separate from whether it has ever been tested.
  present      INTEGER NOT NULL DEFAULT 0 CHECK (present IN (0,1)),
  first_seen   TEXT, last_seen TEXT,
  UNIQUE (source_id, host_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- TIER A — machine-derived facts. Never typed by a person. Re-derivable, so a
-- better extractor updates the whole library without anyone editing a row.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE binary_fact (
  id            INTEGER PRIMARY KEY,
  install_id    INTEGER NOT NULL REFERENCES install(id) ON DELETE CASCADE,
  exe_path      TEXT NOT NULL,
  bits          INTEGER CHECK (bits IN (32,64)),
  gl            INTEGER NOT NULL DEFAULT 0,
  d3d           TEXT,               -- 'd3d11','d3d12','d3d9',... or NULL
  vulkan        INTEGER NOT NULL DEFAULT 0,
  -- HOW the renderer was found. The Quake lineage LoadLibrary's opengl32 from
  -- inside ref_gl.dll, so an import-table scan alone called Daikatana "no
  -- OpenGL" -- exactly backwards. Recording the method keeps that visible.
  found_by      TEXT CHECK (found_by IN ('import','dynamic','both','none')),
  extracted_at  TEXT NOT NULL,
  extractor_ver TEXT NOT NULL,
  UNIQUE (install_id, exe_path)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- CLUSTERS — derived, never authored. The reason one 200-line probe can cover
-- thousands of titles: "FEX sets 0/320 pixel formats for 32-bit Wine programs"
-- is a statement about a CLASS, established from two runs.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE cluster (
  id            INTEGER PRIMARY KEY,
  key           TEXT NOT NULL UNIQUE,   -- 'idtech4|opengl|32|steamstub'
  engine        TEXT, render_api TEXT, bits INTEGER, launcher TEXT, drm TEXT,
  derived_at    TEXT NOT NULL,
  extractor_ver TEXT NOT NULL
);

CREATE TABLE cluster_member (
  cluster_id  INTEGER NOT NULL REFERENCES cluster(id) ON DELETE CASCADE,
  install_id  INTEGER NOT NULL REFERENCES install(id) ON DELETE CASCADE,
  PRIMARY KEY (cluster_id, install_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNS AND ARTIFACTS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE run (
  id             INTEGER PRIMARY KEY,
  run_dir        TEXT NOT NULL UNIQUE,
  install_id     INTEGER REFERENCES install(id),
  host_id        INTEGER NOT NULL REFERENCES host(id),
  started_at     TEXT NOT NULL,
  seconds        INTEGER,
  runtime_req    TEXT,
  -- Read from /proc/<pid>/exe. NULL means NOBODY CAN SEE which translator ran.
  runtime_actual TEXT CHECK (runtime_actual IN ('FEX','Box64','Prism','native')),
  runtime_digest TEXT,   -- the translator BINARY's hash: a patched build is not stock
  proton         TEXT,
  exit_kind      TEXT CHECK (exit_kind IN ('clean','crash','hang','killed','never_started')),
  -- Generated, so it cannot be asserted. This single column is why a claim that
  -- names a translator cannot cite a run that never identified one.
  attributable   INTEGER GENERATED ALWAYS AS
                   (CASE WHEN runtime_actual IS NOT NULL THEN 1 ELSE 0 END) STORED
);
CREATE INDEX ix_run_install ON run(install_id);

CREATE TABLE artifact (
  id            INTEGER PRIMARY KEY,
  run_id        INTEGER NOT NULL REFERENCES run(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,     -- run.json | proton.log | qconsole.log | gpu.csv | mangohud.csv
  path          TEXT,
  bytes         INTEGER,
  present       INTEGER NOT NULL CHECK (present IN (0,1)),
  -- Absent artifacts are ROWS, not missing rows. "no i386 MangoHud exists" is
  -- information; a blank is not. Five runs reported success and produced no CSV.
  absent_reason TEXT,
  UNIQUE (run_id, kind)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- TIER B — CLAIMS. Everything a person or agent asserts. Guarded.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE claim (
  id             INTEGER PRIMARY KEY,
  scope          TEXT NOT NULL CHECK (scope IN ('title','cluster')),
  scope_id       INTEGER NOT NULL,
  host_class     TEXT NOT NULL,
  kind           TEXT NOT NULL,     -- runs | fails | performance | requires_runtime | workaround
  statement      TEXT NOT NULL,
  status         TEXT NOT NULL CHECK (status IN
                   ('unverified','supported','broken','regressed','retracted','reported')),
  -- The dimension every proposal omitted. Without it, 64 human-confirmed results
  -- import as grey "unverified" while 14 phantom gpu.csv-only directories import
  -- as runs WITH evidence -- inverting this project's best catch.
  verifier_class TEXT NOT NULL CHECK (verifier_class IN
                   ('human_observed','instrumented','community_reported')),
  -- Does the claim name a translator? If so it needs an attributable run,
  -- whatever the verifier class, because nobody can SEE which JIT ran.
  names_runtime  INTEGER NOT NULL DEFAULT 0 CHECK (names_runtime IN (0,1)),
  evidence_run   INTEGER REFERENCES run(id),
  evidence_path  TEXT,              -- repo-relative artifact, for non-run evidence
  source_url     TEXT,              -- required for community_reported
  author_kind    TEXT NOT NULL CHECK (author_kind IN ('human','agent')),
  author         TEXT NOT NULL,
  created_at     TEXT NOT NULL DEFAULT (datetime('now')),
  retracted_why  TEXT,
  supersedes     INTEGER REFERENCES claim(id)
);
CREATE INDEX ix_claim_scope ON claim(scope, scope_id);

-- PREDICTIONS ARE NOT CLAIMS, and live in their own table so the two can never
-- be confused by a careless join or a UI that forgets to filter. A prediction
-- never counts as coverage.
CREATE TABLE prediction (
  id           INTEGER PRIMARY KEY,
  install_id   INTEGER NOT NULL REFERENCES install(id) ON DELETE CASCADE,
  host_class   TEXT NOT NULL,
  expected     TEXT NOT NULL,
  basis_cluster INTEGER REFERENCES cluster(id),
  rationale    TEXT NOT NULL,
  predicted_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (install_id, host_class)
);

CREATE TABLE signature (
  id            INTEGER PRIMARY KEY,
  pattern       TEXT NOT NULL UNIQUE,
  meaning       TEXT,
  -- The descriptor_buffer retraction in one column: how many WORKING titles emit
  -- this same line. Non-zero means it is not a failure signature.
  working_hits  INTEGER NOT NULL DEFAULT 0,
  retracted     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE journal (
  id         INTEGER PRIMARY KEY,
  at         TEXT NOT NULL DEFAULT (datetime('now')),
  actor_kind TEXT NOT NULL CHECK (actor_kind IN ('human','agent')),
  actor      TEXT NOT NULL,
  verb       TEXT NOT NULL,
  entity     TEXT NOT NULL,
  detail     TEXT
);

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARDS. Each fires on INSERT and UPDATE, and each looks up what it needs with
-- an explicit SELECT rather than trusting a foreign key to be enforced.
-- ═══════════════════════════════════════════════════════════════════════════

-- G1: a runtime-naming claim requires an ATTRIBUTABLE run. Verifier class does
--     not matter; a human cannot see which translator ran either.
CREATE TRIGGER g1_names_runtime_ins BEFORE INSERT ON claim
WHEN NEW.names_runtime = 1 AND NEW.status <> 'retracted'
  AND (NEW.evidence_run IS NULL
       OR (SELECT COUNT(*) FROM run WHERE id = NEW.evidence_run AND attributable = 1) = 0)
BEGIN SELECT RAISE(ABORT,
  'G1: a claim naming a runtime needs an attributable run (runtime_actual read from /proc/<pid>/exe)');
END;

CREATE TRIGGER g1_names_runtime_upd BEFORE UPDATE ON claim
WHEN NEW.names_runtime = 1 AND NEW.status <> 'retracted'
  AND (NEW.evidence_run IS NULL
       OR (SELECT COUNT(*) FROM run WHERE id = NEW.evidence_run AND attributable = 1) = 0)
BEGIN SELECT RAISE(ABORT,
  'G1: a claim naming a runtime needs an attributable run (UPDATE path)');
END;

-- G2: 'supported' requires evidence appropriate to its verifier class.
--     human_observed IS sufficient evidence -- a person watched it work -- but it
--     must still say who and when. instrumented needs an artifact that resolves.
CREATE TRIGGER g2_supported_ins BEFORE INSERT ON claim
WHEN NEW.status = 'supported' AND (
     (NEW.verifier_class = 'instrumented'
        AND NEW.evidence_run IS NULL AND NEW.evidence_path IS NULL)
  OR (NEW.verifier_class = 'human_observed' AND (NEW.author IS NULL OR NEW.author = ''))
  OR (NEW.verifier_class = 'community_reported'))
BEGIN SELECT RAISE(ABORT,
  'G2: supported needs evidence for its verifier class; community_reported can never be supported');
END;

CREATE TRIGGER g2_supported_upd BEFORE UPDATE ON claim
WHEN NEW.status = 'supported' AND (
     (NEW.verifier_class = 'instrumented'
        AND NEW.evidence_run IS NULL AND NEW.evidence_path IS NULL)
  OR (NEW.verifier_class = 'human_observed' AND (NEW.author IS NULL OR NEW.author = ''))
  OR (NEW.verifier_class = 'community_reported'))
BEGIN SELECT RAISE(ABORT,
  'G2: supported needs evidence for its verifier class (UPDATE path)');
END;

-- G3: community_reported must carry its source, and can never exceed 'reported'.
CREATE TRIGGER g3_community_ins BEFORE INSERT ON claim
WHEN NEW.verifier_class = 'community_reported'
  AND (NEW.source_url IS NULL OR NEW.source_url = '')
BEGIN SELECT RAISE(ABORT, 'G3: community_reported requires source_url'); END;

CREATE TRIGGER g3_community_upd BEFORE UPDATE ON claim
WHEN NEW.verifier_class = 'community_reported'
  AND (NEW.source_url IS NULL OR NEW.source_url = '')
BEGIN SELECT RAISE(ABORT, 'G3: community_reported requires source_url (UPDATE path)'); END;

-- G4: a retraction must say why. The reason is the valuable part.
CREATE TRIGGER g4_retract_ins BEFORE INSERT ON claim
WHEN NEW.status = 'retracted' AND (NEW.retracted_why IS NULL OR NEW.retracted_why = '')
BEGIN SELECT RAISE(ABORT, 'G4: a retracted claim must record retracted_why'); END;

CREATE TRIGGER g4_retract_upd BEFORE UPDATE ON claim
WHEN NEW.status = 'retracted' AND (NEW.retracted_why IS NULL OR NEW.retracted_why = '')
BEGIN SELECT RAISE(ABORT, 'G4: a retracted claim must record retracted_why (UPDATE path)'); END;

-- G5: a run may not be marked as having produced an artifact it did not produce.
CREATE TRIGGER g5_artifact_ins BEFORE INSERT ON artifact
WHEN NEW.present = 1 AND (NEW.path IS NULL OR NEW.path = '')
BEGIN SELECT RAISE(ABORT, 'G5: present artifact requires a path'); END;

CREATE TRIGGER g5_artifact_upd BEFORE UPDATE ON artifact
WHEN NEW.present = 1 AND (NEW.path IS NULL OR NEW.path = '')
BEGIN SELECT RAISE(ABORT, 'G5: present artifact requires a path (UPDATE path)'); END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEWS — the displayed verdict is COMPUTED. There is no status column on title
-- or cluster, so no prose edit and no UI action can promote anything.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE VIEW v_title_status AS
SELECT t.id AS title_id, t.name,
       (SELECT status FROM claim c
         WHERE c.scope='title' AND c.scope_id=t.id AND c.status<>'retracted'
         ORDER BY CASE c.status WHEN 'broken' THEN 1 WHEN 'regressed' THEN 2
                                WHEN 'supported' THEN 3 WHEN 'reported' THEN 4 ELSE 5 END
         LIMIT 1) AS verdict,
       (SELECT COUNT(*) FROM claim c
         WHERE c.scope='title' AND c.scope_id=t.id AND c.status='retracted') AS retractions
FROM title t;

CREATE VIEW v_cluster_coverage AS
SELECT cl.id, cl.key, cl.engine, cl.render_api, cl.bits,
       (SELECT COUNT(*) FROM cluster_member m WHERE m.cluster_id=cl.id) AS members,
       (SELECT COUNT(*) FROM claim c
         WHERE c.scope='cluster' AND c.scope_id=cl.id
           AND c.status IN ('supported','broken') AND c.verifier_class='instrumented')
         AS instrumented_claims,
       (SELECT COUNT(*) FROM cluster_member m
          JOIN install i ON i.id=m.install_id
         WHERE m.cluster_id=cl.id AND i.present=1) AS installed_now
FROM cluster cl;

-- Triage: what is worth testing next. The whole product in one view -- the
-- smallest INSTALLABLE representative of each class with no instrumented
-- evidence. tools/pick-test-game.sh was this idea before it had a name.
CREATE VIEW v_triage AS
SELECT c.key AS cluster_key, c.engine, c.render_api, c.bits,
       cov.members, cov.instrumented_claims,
       t.name AS smallest_title, i.size_bytes, s.platform
FROM cluster c
JOIN v_cluster_coverage cov ON cov.id = c.id
LEFT JOIN cluster_member m  ON m.cluster_id = c.id
LEFT JOIN install i         ON i.id = m.install_id
LEFT JOIN source  s         ON s.id = i.source_id
LEFT JOIN title   t         ON t.id = s.title_id
WHERE cov.instrumented_claims = 0
GROUP BY c.id
HAVING i.size_bytes = MIN(i.size_bytes) OR i.size_bytes IS NULL
ORDER BY cov.members DESC;

-- G6: an INSTRUMENTED claim citing a run requires that run to have an actual
--     manifest. Found the hard way on 2026-09-08: this machine had FOURTEEN run
--     directories containing gpu.csv and nothing else -- no run.json, no engine
--     log -- produced by a leaked telemetry sampler, some holding 57,000 lines
--     of idle-desktop GPU samples. Without this guard they import as runs WITH
--     evidence, and "the game rendered for 57,518 samples" becomes a fact.
CREATE TRIGGER g6_instrumented_needs_manifest_ins BEFORE INSERT ON claim
WHEN NEW.verifier_class = 'instrumented' AND NEW.evidence_run IS NOT NULL
  AND (SELECT COUNT(*) FROM artifact
        WHERE run_id = NEW.evidence_run AND kind = 'run.json' AND present = 1) = 0
BEGIN SELECT RAISE(ABORT,
  'G6: an instrumented claim cannot cite a run with no run.json manifest (phantom run)');
END;

CREATE TRIGGER g6_instrumented_needs_manifest_upd BEFORE UPDATE ON claim
WHEN NEW.verifier_class = 'instrumented' AND NEW.evidence_run IS NOT NULL
  AND (SELECT COUNT(*) FROM artifact
        WHERE run_id = NEW.evidence_run AND kind = 'run.json' AND present = 1) = 0
BEGIN SELECT RAISE(ABORT,
  'G6: instrumented claim citing a phantom run (UPDATE path)');
END;
