#!/usr/bin/env python3
"""test-guards.py — adversarial tests for tools/schema/sgl-schema.sql.

WHY THIS EXISTS
    The launcher's distinguishing promise is that an unverified claim cannot be
    rendered as verified. That promise is only worth something if the guards are
    EXECUTED, not merely written. One of the architecture proposals shipped a
    "verified end to end" retraction cascade that did not exist in its own proof
    database; this file is the answer to that.

    Two conditions every test runs under, both deliberate:
      * PRAGMA foreign_keys = OFF -- the sqlite3 CLI default, and therefore the
        writer that a schema-over-daemon design actually invites.
      * Every guard is attacked through BOTH paths: a direct INSERT, and the
        launder (INSERT a harmless row, then UPDATE it into the claim you wanted).

Run:  python3 tools/schema/test-guards.py
Exit: 0 all guards hold, 1 a guard failed to fire (or fired when it should not).
"""
import sqlite3, sys, os

SCHEMA = os.path.join(os.path.dirname(__file__), 'sgl-schema.sql')
RED, GRN, YEL, OFF = '\033[31m', '\033[32m', '\033[33m', '\033[0m'
passed = failed = 0


def db():
    c = sqlite3.connect(':memory:')
    c.executescript(open(SCHEMA).read().replace('PRAGMA journal_mode = WAL;', ''))
    c.execute('PRAGMA foreign_keys = OFF')          # the hostile default
    c.executescript("""
      INSERT INTO host(id,host_class,fingerprint) VALUES (1,'dgx-spark-linux','fp1');
      INSERT INTO title(id,name) VALUES (1,'Quake 4'),(2,'Daikatana');
      INSERT INTO source(id,title_id,platform,platform_id) VALUES (1,1,'steam','2210'),(2,2,'steam','242980');
      INSERT INTO install(id,source_id,host_id,present) VALUES (1,1,1,1),(2,2,1,0);
      INSERT INTO cluster(id,key,derived_at,extractor_ver) VALUES (1,'idtech4|opengl|32','2026-09-08','v1');
      -- run 1: attributable, with a manifest = good evidence
      INSERT INTO run(id,run_dir,install_id,host_id,started_at,runtime_actual)
        VALUES (1,'runs/2210-good',1,1,'2026-09-07','Box64');
      INSERT INTO artifact(run_id,kind,path,present) VALUES (1,'run.json','runs/2210-good/run.json',1);
      -- run 2: NO runtime_actual = unattributable
      INSERT INTO run(id,run_dir,install_id,host_id,started_at) VALUES (2,'runs/242980-old',2,1,'2026-09-07');
      INSERT INTO artifact(run_id,kind,path,present) VALUES (2,'run.json','runs/242980-old/run.json',1);
      -- run 3: the PHANTOM -- gpu.csv only, no manifest
      INSERT INTO run(id,run_dir,install_id,host_id,started_at,runtime_actual)
        VALUES (3,'runs/2210-phantom',1,1,'2026-09-08','Box64');
      INSERT INTO artifact(run_id,kind,path,present) VALUES (3,'gpu.csv','runs/2210-phantom/gpu.csv',1);
    """)
    return c


BASE = ("INSERT INTO claim(scope,scope_id,host_class,kind,statement,status,verifier_class,"
        "names_runtime,evidence_run,evidence_path,source_url,author_kind,author) VALUES ")


def check(name, fn, want_block):
    global passed, failed
    try:
        fn(); blocked, msg = False, ''
    except sqlite3.IntegrityError as e:
        blocked, msg = True, str(e)
    except sqlite3.Error as e:
        blocked, msg = True, str(e)
    ok = blocked == want_block
    passed, failed = passed + ok, failed + (not ok)
    tag = f'{GRN}PASS{OFF}' if ok else f'{RED}FAIL{OFF}'
    want = 'refuse' if want_block else 'accept'
    got = 'refused' if blocked else 'accepted'
    print(f"  {tag}  {name:<62} want {want}, got {got}")
    if not ok and msg:
        print(f"        {YEL}{msg}{OFF}")
    elif ok and blocked:
        # Print WHICH guard fired. Two tests once passed because a different
        # guard caught them; without this line that is invisible.
        gid = msg.split(':')[0].strip().split()[-1] if ':' in msg else '?'
        expect = name.split()[0]
        flag = '' if gid.startswith(expect) else f'  {YEL}<- fired {gid}, not {expect}{OFF}'
        print(f"        via {gid}{flag}")


print("Guards, executed against a real database with foreign_keys=OFF\n")

# ── G1 : naming a runtime requires an attributable run ────────────────────────
# ISOLATION NOTE. These use status='broken' + human_observed, a combination G2
# explicitly ALLOWS, so only G1 can refuse them. An earlier revision used
# 'supported'+instrumented and passed -- but the message showed G2 firing, not
# G1. A test that passes because a different mechanism caught it has not tested
# the guard it names, and 15/15 green would have hidden that.
check("G1 runtime-naming claim with NO evidence run  [isolated from G2]",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Fails under Box64','broken',"
                                  "'human_observed',1,NULL,NULL,NULL,'human','AGB')"), True)
check("G1 runtime-naming claim citing an UNATTRIBUTABLE run",
      lambda: db().execute(BASE + "('title',2,'dgx','runs','Runs under FEX','supported',"
                                  "'instrumented',1,2,NULL,NULL,'human','AGB')"), True)
def launder_g1():
    c = db()
    c.execute(BASE + "('title',1,'dgx','runs','x','broken','human_observed',0,NULL,NULL,NULL,'human','AGB')")
    # status stays 'broken', so G2 never applies; only G1 can refuse this.
    c.execute("UPDATE claim SET names_runtime=1 WHERE id=1")
check("G1 LAUNDER: UPDATE a plain claim into a runtime claim  [isolated from G2]", launder_g1, True)
check("G1 runtime-naming claim citing a GOOD attributable run  (must be allowed)",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Runs under Box64','supported',"
                                  "'instrumented',1,1,NULL,NULL,'human','AGB')"), False)

# ── G2 : supported needs evidence appropriate to verifier class ───────────────
check("G2 instrumented + supported with NO evidence at all",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Works','supported',"
                                  "'instrumented',0,NULL,NULL,NULL,'agent','claude')"), True)
check("G2 human_observed + supported, named author  (must be allowed)",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Smooth at 5120x1440','supported',"
                                  "'human_observed',0,NULL,NULL,NULL,'human','AGB')"), False)
check("G2 community_reported can NEVER be supported",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Someone said it works','supported',"
                                  "'community_reported',0,NULL,NULL,'https://x','human','AGB')"), True)
def launder_g2():
    c = db()
    c.execute(BASE + "('title',1,'dgx','runs','x','unverified','instrumented',0,NULL,NULL,NULL,'agent','claude')")
    c.execute("UPDATE claim SET status='supported' WHERE id=1")
check("G2 LAUNDER: insert unverified, then UPDATE to supported", launder_g2, True)

# ── G3 : community claims must cite a source ──────────────────────────────────
check("G3 community_reported without source_url",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Heard it works','reported',"
                                  "'community_reported',0,NULL,NULL,NULL,'human','AGB')"), True)

# ── G4 : a retraction must say why ────────────────────────────────────────────
check("G4 retracted with no reason",
      lambda: db().execute(BASE + "('title',1,'dgx','runs','Old claim','retracted',"
                                  "'instrumented',0,NULL,NULL,NULL,'agent','claude')"), True)

# ── G5 : a present artifact must have a path ──────────────────────────────────
check("G5 artifact marked present with no path",
      lambda: db().execute("INSERT INTO artifact(run_id,kind,path,present) VALUES (1,'mangohud.csv',NULL,1)"), True)
check("G5 artifact marked ABSENT with a reason  (must be allowed)",
      lambda: db().execute("INSERT INTO artifact(run_id,kind,path,present,absent_reason) "
                           "VALUES (1,'mangohud.csv',NULL,0,'no i386 MangoHud build exists')"), False)

# ── G6 : the phantom-run guard (14 of these existed on this machine today) ────
check("G6 instrumented claim citing a PHANTOM run (gpu.csv only, no manifest)",
      lambda: db().execute(BASE + "('title',1,'dgx','performance','221 samples','supported',"
                                  "'instrumented',0,3,NULL,NULL,'agent','claude')"), True)
def launder_g6():
    c = db()
    c.execute(BASE + "('title',1,'dgx','runs','x','unverified','human_observed',0,NULL,NULL,NULL,'human','AGB')")
    c.execute("UPDATE claim SET verifier_class='instrumented', evidence_run=3, status='supported' WHERE id=1")
check("G6 LAUNDER: human claim UPDATEd into an instrumented phantom-run claim", launder_g6, True)

# ── the inversion this schema exists to prevent ───────────────────────────────
c = db()
c.execute(BASE + "('title',1,'dgx','runs','Prey reaches gameplay','supported','human_observed',"
                 "0,NULL,NULL,NULL,'human','AGB')")
human_ok = c.execute("SELECT COUNT(*) FROM claim WHERE status='supported'").fetchone()[0] == 1
try:
    c.execute(BASE + "('title',1,'dgx','performance','57518 samples','supported','instrumented',"
                     "0,3,NULL,NULL,'agent','claude')")
    phantom_ok = False
except sqlite3.Error:
    phantom_ok = True
inv = human_ok and phantom_ok
passed, failed = passed + inv, failed + (not inv)
print(f"\n  {(GRN+'PASS'+OFF) if inv else (RED+'FAIL'+OFF)}  "
      f"INVERSION: a human-observed result outranks a phantom instrumented one")

print(f"\n  {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
