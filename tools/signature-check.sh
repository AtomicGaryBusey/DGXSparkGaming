#!/usr/bin/env bash
# signature-check.sh — is this log line actually a FAILURE signature, or does it
# also appear in games that work?
#
# WHY THIS EXISTS
#   This project's single most expensive recurring error is publishing a real log
#   line as the cause of a crash without ever checking a WORKING title for it.
#   It has now happened twice:
#     * "3,983 evaluates, DLSS 5 NR running every frame" — the counter was the
#       GENERIC NGX evaluate hook, carrying the game's own DLSS-SR. Committed and
#       pushed. The NR-specific line had occurred twice.
#     * "vkGetPhysicalDeviceDescriptorSizeEXT unthunked" — cited for months as the
#       root cause of No Man's Sky, Halo Infinite and Elden Ring. Cyberpunk 2077
#       emits it 16 times and runs fine; Daikatana emits it 4 times and runs
#       excellently. The driver exposes the extension that was blamed.
#   Both would have died to ONE grep against a working game's log. That grep is
#   this script, so that nobody has to think of it at the decision moment.
#
#   The status of each title is read from README.md itself — "Tested by AGB" means
#   it works, "Known Issues" means it does not — so the log audits its own claims
#   and cannot drift out of sync with them.
#
# Usage:
#   tools/signature-check.sh 'DescriptorSizeEXT'
#   tools/signature-check.sh -E 'Unknown Vulkan function.*Descriptor'
#   tools/signature-check.sh 'foo' extra.log another.log
#
# Exit: 0 = only failing titles emit it (a plausible signature)
#       1 = a WORKING title emits it too -> NOT a failure signature
#       2 = no title emits it at all (nothing to conclude)
set -uo pipefail
[ $# -ge 1 ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 3; }
MODE=fixed
[ "$1" = "-E" ] && { MODE=ere; shift; }
PAT="$1"; shift || true
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"

PAT="$PAT" MODE="$MODE" REPO="$REPO" STEAM="$STEAM" python3 - "$@" <<'PY'
import os, re, sys, glob

pat, mode = os.environ["PAT"], os.environ["MODE"]
repo, steam = os.environ["REPO"], os.environ["STEAM"]
rx = re.compile(re.escape(pat) if mode == "fixed" else pat)

# --- title status, straight out of README.md so the two can never disagree -----
readme = open(os.path.join(repo, "README.md"), encoding="utf-8", errors="replace").read()
def rows_under(heading):
    i = readme.find(heading)
    if i < 0: return set()
    # stop at the next heading of the same or higher level
    j = re.search(r'^#{1,3} ', readme[i + len(heading):], re.M)
    seg = readme[i:i + len(heading) + (j.start() if j else len(readme))]
    return {m.group(1).strip().lower()
            for m in re.finditer(r'^\|\s*\*\*(.+?)\*\*\s*\|', seg, re.M)}
works = rows_under("### Tested by AGB")
fails = rows_under("### Known Issues")

def status(name):
    if not name: return "?"
    n = name.lower()
    for s, label in ((works, "WORKS"), (fails, "FAILS")):
        for g in s:
            if g == n or g in n or n in g: return label
    return "unrecorded"

def appname(appid):
    p = os.path.join(steam, "steamapps", f"appmanifest_{appid}.acf")
    try:
        m = re.search(r'"name"\s*"([^"]*)"', open(p, encoding="utf-8", errors="replace").read())
        return m.group(1) if m else ""
    except OSError:
        return ""

# --- scan: proton logs are named by appid, so they carry the mapping for free --
targets = []
for f in sorted(glob.glob(os.path.expanduser("~/steam-*.log"))):
    m = re.search(r'steam-(\d+)\.log$', f)
    if m: targets.append((m.group(1), appname(m.group(1)), f))
for extra in sys.argv[1:]:
    targets.append(("", os.path.basename(extra), extra))

if not targets:
    print("no logs to scan (expected ~/steam-<appid>.log; pass extra paths as args)")
    sys.exit(2)

hits, scanned = [], 0
for appid, name, path in targets:
    try:
        n = sum(1 for line in open(path, encoding="utf-8", errors="replace") if rx.search(line))
    except OSError:
        continue
    scanned += 1
    if n: hits.append((appid, name, status(name), n, path))

print(f"pattern: {pat!r}  ({mode})")
print(f"scanned {scanned} log(s)\n")
if not hits:
    print("NOT FOUND in any log. Nothing to conclude — this is not evidence for or")
    print("against anything. Check the pattern, and check that a log exists for the")
    print("title you care about (PROTON_LOG=1 in the Steam launch options).")
    sys.exit(2)

w = max(len(h[1] or h[0]) for h in hits)
for appid, name, st, n, _ in sorted(hits, key=lambda h: (h[2] != "WORKS", -h[3])):
    mark = {"WORKS": "  <-- WORKING TITLE", "FAILS": "", "unrecorded": "  (status not in README)"}[st]
    print(f"  {(name or appid):<{w}}  {st:<10} {n:>5} hit(s){mark}")

good = [h for h in hits if h[2] == "WORKS"]
print()
if good:
    names = ", ".join(h[1] or h[0] for h in good)
    print("VERDICT: NOT A FAILURE SIGNATURE.")
    print(f"  Emitted by {len(good)} title(s) recorded as WORKING: {names}.")
    print("  Whatever kills the failing titles, this line is not evidence for it.")
    print("  Do not cite it as a root cause, and do not substitute a fresh guess.")
    sys.exit(1)
print("VERDICT: plausible — only failing/unrecorded titles emit it.")
print("  NOT proof. A control that cannot be run is still a missing control:")
print("  if no working title has a log at all, this says little. Get one.")
sys.exit(0)
PY
