#!/usr/bin/env bash
# guard-foreign-files.sh — PreToolUse/PostToolUse hook. Stops edits to config files
# that OTHER PROGRAMS own and rewrite behind your back.
#
# WHY THIS EXISTS
#   On 2026-09-07 two DLSS experiments were silently contaminated. OptiScaler
#   rewrites OptiScaler.ini on exit -- it had persisted the user's overlay changes
#   (Style=1, WhitePointSource=2, an empty ScanAnchors) into the file. The agent
#   then edited that file from a stale mental model, ran two experiments on top of
#   settings it did not know were there, and reported results it could not attribute.
#   The same class of thing bit us three more times:
#     * Cyberpunk rewrote UserSettings.json and Frame Generation turned itself back
#       on between runs -- discovered by accident.
#     * Wine rewrites the prefix user.reg on exit.
#     * A stale OptiScaler.log was read as if it described the running session, and
#       produced a confidently wrong "OptiScaler was unloaded" conclusion.
#
#   The rule "re-read before editing" is exactly the kind of rule this project has
#   already proven it will not follow. So: enforce it.
#
# HOW
#   PostToolUse(Read)  -> record the file's mtime as "last seen".
#   PreToolUse(Edit|Write|Bash) -> if the operation writes a foreign-owned file and
#   the on-disk mtime differs from what was last seen, BLOCK. Re-Read it first.
#
# exit 0 allow, exit 2 block (stderr shown to the model).
# Escape hatch: # HOOK_OVERRIDE: <reason>  in the command.
set -uo pipefail

STATE="${XDG_CACHE_HOME:-$HOME/.cache}/dgx-guard"; mkdir -p "$STATE" 2>/dev/null

# Files owned by another program. Substring match against absolute paths.
FOREIGN=(
  "OptiScaler.ini"
  "UserSettings.json"
  "/pfx/user.reg"
  "/pfx/system.reg"
  "localconfig.vdf"
  "ReShade.ini"
)

INPUT="$(cat)"
read -r EVENT TOOL <<<"$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("hook_event_name","") or "-", d.get("tool_name","") or "-")
except Exception: print("- -")' 2>/dev/null)"

payload() { printf '%s' "$INPUT" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
ti=d.get('tool_input',{}) or {}
print(ti.get('file_path','') or '')
print((ti.get('command','') or '').replace(chr(10),' '))
"; }
FP="$(payload | sed -n 1p)"; CMD="$(payload | sed -n 2p)"

key() { printf '%s' "$1" | sha256sum | cut -c1-40; }
mt()  { stat -c%Y "$1" 2>/dev/null || echo 0; }

# --- record what we have seen -------------------------------------------------
if [ "$EVENT" = "PostToolUse" ] && [ "$TOOL" = "Read" ] && [ -n "$FP" ]; then
  printf '%s' "$(mt "$FP")" > "$STATE/$(key "$FP")" 2>/dev/null
  exit 0
fi
[ "$EVENT" = "PreToolUse" ] || exit 0
case "$CMD" in *"HOOK_OVERRIDE:"*) exit 0;; esac

# --- find a foreign-owned target ----------------------------------------------
target=""
for f in "${FOREIGN[@]}"; do
  case "$FP" in *"$f"*) target="$FP"; break;; esac
done
if [ -z "$target" ] && [ -n "$CMD" ]; then
  # A Bash command counts only if it also looks like a write. Most config edits in
  # this project go through python heredocs, not the Edit tool, so Edit/Write
  # matchers alone would miss every real case.
  case "$CMD" in
    *">"*|*"sed -i"*|*"'w'"*|*'"w"'*|*"tee "*|*"cp "*|*"mv "*|*"truncate"*|*"rm "*)
      for f in "${FOREIGN[@]}"; do
        case "$CMD" in *"$f"*) target="$f"; break;; esac
      done ;;
  esac
fi
[ -z "$target" ] && exit 0

# Resolve a concrete path when we only matched a basename inside a command.
# Done in python: shell regex-building around paths with spaces and quotes was
# silently producing nothing, so every Bash-side write sailed through.
path="$target"
if [ ! -f "$path" ]; then
  path="$(TARGET="$target" CMDLINE="$CMD" python3 -c '
import os,re,shlex,sys
t=os.environ["TARGET"]; c=os.environ["CMDLINE"]
cands=[]
try: cands=[w for w in shlex.split(c) if t in w]
except Exception: pass
if not cands: cands=[m for m in re.findall(r"\S+", c) if t in m]
for w in cands:
    w=w.strip("\"'"'"'")
    if os.path.isfile(w): print(w); break
else:
    # path may contain spaces and have been split; fall back to a greedy scan
    i=c.find(t)
    if i!=-1:
        for start in range(i,-1,-1):
            cand=c[start:i+len(t)].strip().strip("\"'"'"'")
            if os.path.isfile(cand): print(cand); break
' 2>/dev/null)"
fi
[ -n "$path" ] && [ -f "$path" ] || exit 0

seen_file="$STATE/$(key "$path")"
seen=$(cat "$seen_file" 2>/dev/null || echo "")
now=$(mt "$path")

if [ -z "$seen" ]; then
  reason="you have not Read it in this session"
elif [ "$seen" != "$now" ]; then
  reason="it changed on disk after you last Read it (owner program rewrote it)"
else
  exit 0
fi

{
  echo "BLOCKED by .claude/hooks/guard-foreign-files.sh"
  echo
  echo "About to write a config file owned by another program:"
  echo "  $path"
  echo "  reason: $reason"
  echo
  echo "OptiScaler rewrites OptiScaler.ini on exit; Cyberpunk rewrites UserSettings.json;"
  echo "Wine rewrites user.reg. Editing from a stale view silently contaminated two"
  echo "DLSS experiments on 2026-09-07 and produced results that could not be attributed."
  echo
  echo "Read the file first, then repeat this command."
  echo "If you are deliberately overwriting it wholesale, append:  # HOOK_OVERRIDE: <reason>"
} >&2
exit 2
