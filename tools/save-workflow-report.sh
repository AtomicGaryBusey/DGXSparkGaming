#!/usr/bin/env bash
# save-workflow-report.sh — persist a multi-agent workflow's synthesis into notes/.
#
# WHY THIS EXISTS
#   Ultracode / workflow runs cost hundreds of thousands of tokens and produce the
#   most carefully verified prose in this project -- ranked paths, dead ends, and
#   explicit statements of what is still unknown. All of it lived in
#   /tmp/claude-*/tasks/*.output, which is scratch: it disappears with the job, is
#   invisible to anyone else, and is invisible to a later session of the same work.
#
#   That is the same failure that let a session rebuild two probes it already had.
#   A report nobody can find is a report nobody has.
#
#   Reports are saved with a provenance header -- run id, agent count, token cost,
#   date -- because a synthesis is only as trustworthy as the conditions that
#   produced it, and because "16 agents, 1.46M tokens" tells a reader how much
#   scrutiny a claim actually received.
#
# Usage:
#   tools/save-workflow-report.sh <task-output.json> [slug]
#   tools/save-workflow-report.sh --all                # every workflow output found
#
# Writes notes/<YYYY-MM-DD>-<slug>.md and prints the path.
# Existing files are never overwritten; a numeric suffix is added instead.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
NOTES="$REPO/notes"
mkdir -p "$NOTES"

save_one() {
  local f="$1" slug="${2:-}"
  [ -s "$f" ] || { echo "  skip (empty): $f"; return 1; }
  NOTES="$NOTES" SLUG="$slug" python3 - "$f" <<'PY'
import json, os, re, sys, datetime
path = sys.argv[1]
notes, slug = os.environ["NOTES"], os.environ.get("SLUG", "")
try:
    d = json.load(open(path))
except Exception:
    print(f"  skip (not workflow json): {os.path.basename(path)}"); raise SystemExit(0)
res = d.get("result")
if not isinstance(res, dict): print(f"  skip (no result object): {os.path.basename(path)}"); raise SystemExit(0)
# the synthesis is the longest string field in the result
body, key = "", ""
for k, v in res.items():
    if isinstance(v, str) and len(v) > len(body): body, key = v, k
if len(body) < 400: print(f"  skip (no synthesis text): {os.path.basename(path)}"); raise SystemExit(0)

summary = str(d.get("summary", "")).strip()
if not slug:
    slug = re.sub(r"[^a-z0-9]+", "-", summary.lower())[:52].strip("-") or "workflow-report"
stamp = datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat()
out = os.path.join(notes, f"{stamp}-{slug}.md")
n = 2
while os.path.exists(out):
    out = os.path.join(notes, f"{stamp}-{slug}-{n}.md"); n += 1

# run id, if the transcript dir recorded one
runid = ""
for p in d.get("workflowProgress", []) or []:
    if isinstance(p, dict) and p.get("runId"): runid = p["runId"]; break

counts = {k: v for k, v in res.items() if isinstance(v, (int, float))}
hdr = [
    f"# {summary or slug}", "",
    "> **Machine-generated report from a multi-agent workflow run.** Persisted from",
    "> scratch storage so it can be read, cited and *checked* later. Treat every claim",
    "> in it as untrusted until verified locally — this project has published agent",
    "> findings that were wrong, and the synthesis itself flags which of its own claims",
    "> survived adversarial verification and which were refuted.", "",
    "| | |", "|---|---|",
    f"| Run date | {stamp} |",
    f"| Agents | {d.get('agentCount', '?')} |",
    f"| Tokens | {d.get('totalTokens', '?'):,} |" if isinstance(d.get("totalTokens"), int) else "| Tokens | ? |",
    f"| Tool calls | {d.get('totalToolCalls', '?')} |",
]
if runid: hdr.append(f"| Run id | `{runid}` |")
for k, v in counts.items(): hdr.append(f"| {k} | {v} |")
hdr += ["", "---", ""]
open(out, "w").write("\n".join(hdr) + body.rstrip() + "\n")
print(f"  saved: {os.path.relpath(out, os.path.dirname(notes))}  ({len(body)} chars, from '{key}')")
PY
}

if [ "${1:-}" = "--all" ]; then
  # task outputs are the only place a completed workflow's return value lands
  found=0
  for d in /tmp/claude-*/*/*/tasks "${CLAUDE_JOB_DIR:-/nonexistent}/../"*/tasks; do
    [ -d "$d" ] || continue
    for f in "$d"/*.output; do
      [ -s "$f" ] || continue
      grep -q '"workflowProgress"' "$f" 2>/dev/null || continue
      save_one "$f" && found=$((found+1))
    done
  done
  echo "  ($found report(s) processed)"
  exit 0
fi

[ -n "${1:-}" ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
save_one "$1" "${2:-}"
