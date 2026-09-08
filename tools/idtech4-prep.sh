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
#   WIDTH=2560 HEIGHT=1440 tools/idtech4-prep.sh <appid>   # override the detected size
#
# Safe to re-run. Only ever writes autoexec.cfg, which is ours, never a file the
# game rewrites behind us (see .claude/hooks/guard-foreign-files.sh for why that
# distinction matters here).
set -uo pipefail
APPID="${1:-}"; [ -n "$APPID" ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
UNDO=0; [ "${2:-}" = "--undo" ] && UNDO=1
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
# Resolution: DETECT the display, never hardcode.
#
# This used to read  W="${WIDTH:-2560}"; H="${HEIGHT:-1440}"  and that was a real
# bug with a real cost. On a 5120x1440 desktop it made both Prey and Quake 4
# create a "fullscreen" window covering only the LEFT HALF of the screen. Wine
# decides whether to grab and confine the pointer by comparing the window rect to
# the monitor rect, so a half-width window is not fullscreen to Wine, the
# exclusive-mode DirectInput grab the engine asks for does not behave as the game
# expects, and the mouse misbehaves. That anomaly was then investigated for a day
# as if it were a translator bug. The header above literally warns that a small
# window gets mistaken for broken mouse capture; the tool caused the condition it
# warned about. Detect, and say what was detected.
detect_res() {
  local r=""
  r=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')
  [ -n "$r" ] || r=$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
  printf '%s' "$r"
}
# CHOOSING A RESOLUTION IS NOT AS SIMPLE AS "USE THE DISPLAY'S".
#
# Measured 2026-09-08 on a 5120x1440 display: setting r_customWidth/Height to the
# native mode with r_fullscreen 1 makes the engine call ChangeDisplaySettings,
# which dies with
#     ...calling CDS: failed, unknown error -1073741819      (0xC0000005)
# and the engine then spins forever in "...trying next higher resolution:".
# The MODE is valid -- xrandr lists 5120x1440 -- so it is the CDS call itself
# that access-violates on this stack. Windowed avoids the call but produces a
# 5128x1474 decorated window, LARGER than the screen.
#
# So this tool no longer just detects and applies. It picks the largest mode
# id Tech 4 can actually express (the engine knows only 4:3, 16:9 and 16:10)
# that FITS inside the display, and prints the native option as an override
# rather than choosing it for you. NATIVE=1 forces the detected mode.
largest_fitting_169() {   # echo "W H" for the biggest 16:9 that fits in $1 x $2
  awk -v dw="$1" -v dh="$2" 'BEGIN{
    split("3840 2160 2560 1440 1920 1080 1600 900 1366 768 1280 720", a, " ");
    for (i=1; i<length(a); i+=2) if (a[i] <= dw && a[i+1] <= dh) { print a[i], a[i+1]; exit }
    print 1280, 720 }'
}

DETECTED=$(detect_res)
if [ -z "${WIDTH:-}${HEIGHT:-}" ] && [ -n "$DETECTED" ] && [ "${NATIVE:-0}" != 1 ]; then
  _dw=${DETECTED%x*}; _dh=${DETECTED#*x}
  set -- $(largest_fitting_169 "$_dw" "$_dh")
  WIDTH="$1"; HEIGHT="$2"
  if [ "${WIDTH}x${HEIGHT}" != "$DETECTED" ]; then
    CDS_NOTE="  note: display is $DETECTED but this sets ${WIDTH}x${HEIGHT}, the largest 16:9
        mode id Tech 4 can express that fits. Fullscreen at $DETECTED makes the
        engine's ChangeDisplaySettings call access-violate and hang (2026-09-08).
        NATIVE=1 overrides, and is expected to hang -- it is there for retesting
        after a Wine or Box64 update, not for playing."
  fi
fi
if [ -n "${WIDTH:-}${HEIGHT:-}" ]; then
  W="${WIDTH:-${DETECTED%x*}}"; H="${HEIGHT:-${DETECTED#*x}}"
  RES_SRC="explicit override"
elif [ -n "$DETECTED" ]; then
  W="${DETECTED%x*}"; H="${DETECTED#*x}"
  RES_SRC="detected from the X display"
else
  W=1920; H=1080
  RES_SRC="FALLBACK -- no display detected, and this may not match your screen"
fi

# id Tech 4 only knows 4:3 (0), 16:9 (1) and 16:10 (2). Pick the nearest and say
# so, because on an ultrawide the nearest is still wrong and the FOV will look it.
ASPECT=$(awk -v w="$W" -v h="$H" 'BEGIN{
  a=w/h; d43=(a-4/3); d169=(a-16/9); d1610=(a-16/10);
  if(d43<0)d43=-d43; if(d169<0)d169=-d169; if(d1610<0)d1610=-d1610;
  if(d43<=d169 && d43<=d1610) print 0; else if(d1610<=d169) print 2; else print 1 }')
ASPECT_NOTE=$(awk -v w="$W" -v h="$H" 'BEGIN{
  a=w/h; if (a > 1.85) print "  !! " w "x" h " is " sprintf("%.2f",a) ":1. id Tech 4 has no ultrawide aspect;\n     16:9 is the closest it offers, so expect a stretched/narrow FOV.\n     That is cosmetic. It does NOT affect mouse capture."; }')

M="$STEAM/steamapps/appmanifest_$APPID.acf"
[ -f "$M" ] || { echo "!! appid $APPID has no appmanifest"; exit 1; }
NAME=$(sed -n 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
INST=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
DIR="$STEAM/steamapps/common/$INST"
[ -d "$DIR" ] || { echo "!! $NAME is not installed at $DIR"; exit 1; }

# The mod directory is whichever one holds the .pk4 archives: base (DOOM 3),
# q4base (Quake 4), preybase (Prey), d3xp (Resurrection of Evil). Detect it
# rather than hardcoding a table that will be wrong for the next title.
# id Tech 4 does not use one archive format across the family:
#   .pk4        DOOM 3, Quake 4, Prey, RoE, Phobos
#   .resources  DOOM 3 BFG Edition (the 2012 remaster)
# and licensees nest the game root a level down (Wolfenstein 2009 ships SP/base
# and MP/base). Searching only for *.pk4 at depth 1 silently skipped both, so
# this now matches either format and looks one level deeper.
BASE=""
for pat in '*.pk4' '*.resources'; do
  for d in "$DIR"/*/ "$DIR"/*/*/; do
    [ -d "$d" ] || continue
    if ls "$d"$pat >/dev/null 2>&1; then BASE="${d%/}"; break 2; fi
  done
done
[ -n "$BASE" ] || { echo "!! no directory with .pk4 or .resources files under $DIR"; echo "   (still downloading?)"; exit 1; }
# Wolfenstein (2009) ships SP/base and MP/base; the glob finds MP first purely
# because M sorts before S, which would arm multiplayer for a singleplayer test.
case "$BASE" in
  */MP/*) _sp=$(printf '%s' "$BASE" | sed 's|/MP/|/SP/|'); [ -d "$_sp" ] && BASE="$_sp" ;;
esac
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
seta r_aspectRatio "$ASPECT"
CFGEOF

echo "armed: $NAME ($APPID)"
echo "  mod dir : $BASE"
echo "  config  : $CFG"
echo "  log will be: $BASE/qconsole.log   (flushed per line)"
echo "  resolution : ${W}x${H} fullscreen   ($RES_SRC; aspect $ASPECT)"
[ -n "${CDS_NOTE:-}" ] && printf '%s\n' "$CDS_NOTE"
[ -n "$ASPECT_NOTE" ] && printf '%s\n' "$ASPECT_NOTE"
if [ -n "$DETECTED" ] && [ "${W}x${H}" != "$DETECTED" ]; then
  echo "  note: window ${W}x${H} does not match the display $DETECTED."
  echo "     Wine judges 'fullscreen' by comparing window rect to monitor rect, so it"
  echo "     will not treat this as fullscreen. That was HYPOTHESISED as the cause of"
  echo "     the id Tech 4 mouse anomaly and is UNVERIFIED -- four launches on"
  echo "     2026-09-08 failed for unrelated reasons and never tested it. Do not"
  echo "     repeat that: measure with tools/mousefeel.sh before changing geometry."
fi
echo
echo "next:  tools/game-run.sh $APPID"
echo "then:  grep -E 'TAGS =|num values on stack|FPU stack is not empty' '$BASE/qconsole.log'"
