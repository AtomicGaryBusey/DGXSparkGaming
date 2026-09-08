#!/usr/bin/env bash
# idtech4-prep.sh — arm an id Tech 4 game so that if it dies, it says WHY.
#
# WHY THIS EXISTS
#   DOOM 3, DOOM 3 BFG and Prey were each recorded here as "crashes on map load,
#   x87 FPU stack" for months. The engine had been printing its ENTIRE x87
#   environment one line before dying the whole time -- control word, status
#   word, tag word, instruction pointer, all eight ST registers, and a decoded
#   stack depth -- and nobody had ever turned the log on to read it. Quake 4 was
#   armed with exactly this config on 2026-09-07 and answered a months-old
#   question on its first run.
#
#   Doing that by hand meant knowing that `logFile 1` BUFFERS (so the crash eats
#   the very lines you need) and `logFile 2` flushes every write. That is the
#   kind of detail a tool should hold, not a person.
#
#   It also sets a real resolution. id Tech 4 defaults to a 640x480 window here,
#   which on 2026-09-07 was briefly mistaken for broken mouse capture -- the
#   pointer was simply bounded by a small window.
#
# Usage:
#   tools/idtech4-prep.sh <appid>            # arm it
#   tools/idtech4-prep.sh <appid> --undo     # remove our autoexec.cfg
#   WIDTH=2560 HEIGHT=1440 tools/idtech4-prep.sh <appid>
#
# Safe to re-run. Only ever writes autoexec.cfg, which is ours, never a file the
# game rewrites behind us (see .claude/hooks/guard-foreign-files.sh for why that
# distinction matters here).
set -uo pipefail
APPID="${1:-}"; [ -n "$APPID" ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
UNDO=0; [ "${2:-}" = "--undo" ] && UNDO=1
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
W="${WIDTH:-2560}"; H="${HEIGHT:-1440}"

M="$STEAM/steamapps/appmanifest_$APPID.acf"
[ -f "$M" ] || { echo "!! appid $APPID has no appmanifest"; exit 1; }
NAME=$(sed -n 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
INST=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
DIR="$STEAM/steamapps/common/$INST"
[ -d "$DIR" ] || { echo "!! $NAME is not installed at $DIR"; exit 1; }

# The mod directory is whichever one holds the .pk4 archives: base (DOOM 3),
# q4base (Quake 4), preybase (Prey), d3xp (Resurrection of Evil). Detect it
# rather than hardcoding a table that will be wrong for the next title.
BASE=""
for d in "$DIR"/*/; do
  if ls "$d"*.pk4 >/dev/null 2>&1; then BASE="${d%/}"; break; fi
done
[ -n "$BASE" ] || { echo "!! no directory with .pk4 files under $DIR"; echo "   (still downloading?)"; exit 1; }
CFG="$BASE/autoexec.cfg"

if [ "$UNDO" = 1 ]; then
  if grep -q 'DGX Spark log' "$CFG" 2>/dev/null; then rm -f "$CFG"; echo "removed $CFG"
  else echo "not ours (or absent) — left alone: $CFG"; fi
  exit 0
fi

cat > "$CFG" <<CFGEOF
// Written by tools/idtech4-prep.sh for the DGX Spark log.
//
// WHY: id Tech 4 prints its whole x87 environment one line before
//   "the FPU stack is not empty at the end of the frame" --
//   CTRL/STAT/TAGS/INOF, ST0..ST7 and a decoded stack depth. Sys_FPU_StackIsEmpty()
//   reads the TAG WORD and nothing else, so the tag word is the number that matters.
//   Reading it settled a months-old question on the first try with Quake 4.
//
// logFile 2 = log AND FLUSH EVERY WRITE. With 1 the buffer is lost in the crash,
// which loses exactly the lines this exists to capture.
seta logFile "2"
seta logFileName "qconsole.log"
seta com_showFPS "1"
seta com_allowConsole "1"
// pinned so the run has no unrecorded variable; 0 is the stock default
seta win_enableFPUExceptions "0"
// id Tech 4 defaults to a 640x480 window here; r_mode -1 honours the custom size
seta r_mode "-1"
seta r_customWidth "$W"
seta r_customHeight "$H"
seta r_fullscreen "1"
seta r_aspectRatio "1"
CFGEOF

echo "armed: $NAME ($APPID)"
echo "  mod dir : $BASE"
echo "  config  : $CFG"
echo "  log will be: $BASE/qconsole.log   (flushed per line)"
echo "  resolution : ${W}x${H} fullscreen"
echo
echo "next:  tools/game-run.sh $APPID"
echo "then:  grep -E 'TAGS =|num values on stack|FPU stack is not empty' '$BASE/qconsole.log'"
