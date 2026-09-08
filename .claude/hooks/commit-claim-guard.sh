#!/usr/bin/env bash
# commit-claim-guard.sh — git pre-commit hook. Requires an evidence trail on any
# commit that makes a result claim.
#
# WHAT IT CAN AND CANNOT DO — read this before trusting it
#   It CANNOT catch the error this project actually made on 2026-09-07. The commit
#   said "3,983 evaluates, NR running every frame". That number was REAL and sat in
#   a REAL log; the interpretation was wrong, because the counter was the generic
#   NGX hook and the traffic was the game's own DLSS-SR. No pattern match
#   distinguishes a true number from a misread one.
#
#   What it CAN do is refuse a result claim with no artifact behind it, and force
#   the author to name that artifact at the moment of publication. The judgement
#   lives in .claude/skills/log-result — this is only the mechanical half.
#
# RULE
#   If the commit message contains result language, it must also contain a line:
#       Evidence: <path>[, <path>...]
#   naming at least one file or directory that exists. Or an explicit:
#       Evidence: none — <reason>
#   which is allowed, and visible in the history forever, which is the point.
#
# Install:  ln -sf ../../.claude/hooks/commit-claim-guard.sh .git/hooks/commit-msg
#
#   It MUST be commit-msg, not pre-commit. pre-commit runs BEFORE the message
#   exists, so $1 is empty and the script falls back to .git/COMMIT_EDITMSG —
#   which still holds the PREVIOUS commit's message. Installed that way it
#   blocked a commit for the last commit's wording. Found the first time it ran.
set -uo pipefail
MSGFILE="${1:-.git/COMMIT_EDITMSG}"
[ -f "$MSGFILE" ] || exit 0
MSG="$(cat "$MSGFILE")"

# Comment lines are not part of the message.
BODY="$(printf '%s' "$MSG" | grep -v '^#' || true)"
[ -z "${BODY//[[:space:]]/}" ] && exit 0

# Result language. Deliberately narrow: ordinary tooling/doc commits must not trip it.
if ! printf '%s' "$BODY" | grep -qiE '\b(runs|running|works|working|confirmed|verified|proves?|proven|succeeds?|success|fps|frametime|evaluates?|dispatch(es|ed)?|benchmark|faster|slower|[0-9]+ *%|[0-9]+ *fps)\b'; then
  exit 0
fi

EV="$(printf '%s' "$BODY" | grep -iE '^[[:space:]]*Evidence:' | head -1 || true)"
if [ -z "$EV" ]; then
  {
    echo "BLOCKED by .claude/hooks/commit-claim-guard.sh"
    echo
    echo "This commit message makes a result claim but has no Evidence: line."
    echo
    echo "Add one of:"
    echo "  Evidence: ~/dgx-gaming-work/evidence/<file>, runs/<file>"
    echo "  Evidence: none — <why there is no artifact>"
    echo
    echo "On 2026-09-07 a headline result was committed and pushed before being"
    echo "checked, and was wrong. See .claude/skills/log-result for the questions"
    echo "to answer before writing a claim at all."
  } >&2
  exit 1
fi

# "none — reason" is acceptable and stays in the history.
if printf '%s' "$EV" | grep -qiE 'Evidence:[[:space:]]*none'; then exit 0; fi

PATHS="$(printf '%s' "$EV" | sed 's/^[[:space:]]*[Ee]vidence:[[:space:]]*//' | tr ',' '\n')"
found=0; missing=""
while read -r p; do
  p="$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$p" ] && continue
  exp="${p/#\~/$HOME}"
  if [ -e "$exp" ]; then found=$((found+1)); else missing="$missing  $p"$'\n'; fi
done <<< "$PATHS"

if [ "$found" -eq 0 ]; then
  {
    echo "BLOCKED by .claude/hooks/commit-claim-guard.sh"
    echo
    echo "Evidence: line names no path that exists:"
    printf '%s' "$missing"
    echo
    echo "Point it at a real artifact, or write:  Evidence: none — <reason>"
    echo
    echo "Note: the line is split on commas and each piece must be a bare path."
    echo "Prose in it becomes part of a path and will not exist:"
    echo "  BAD   Evidence: runs/foo (Box64, GL ok)   -> tries \"runs/foo (Box64\""
    echo "  GOOD  Evidence: runs/foo, runs/bar"
  } >&2
  exit 1
fi
exit 0
