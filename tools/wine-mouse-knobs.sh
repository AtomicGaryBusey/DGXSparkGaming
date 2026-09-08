#!/usr/bin/env bash
# wine-mouse-knobs.sh — set/clear the three Wine registry knobs that actually
# change mouse behaviour for old exclusive-mode DirectInput games.
#
# WHY THIS EXISTS
#   These are the standard levers, and all three are UNSET (Wine defaults) in
#   this prefix, so they have never been tried here. They are worth exactly one
#   controlled A/B each -- and controlled means change ONE, relaunch, judge, put
#   it back. Changing all three and declaring victory teaches nothing about which
#   one mattered, which is how this log has previously ended up with fixes it
#   could not explain.
#
#     X11 Driver\GrabPointer     Y  confine the pointer to the window
#     X11 Driver\GrabFullscreen  Y  ...also for fullscreen windows. Relevant here
#                                   because Wine only calls a window fullscreen
#                                   when its rect matches the monitor rect.
#     DirectInput\MouseWarpOverride  force
#                                   force the warp emulation old DirectInput
#                                   games rely on for relative motion.
#
#   Writes go through `wine reg`, never by editing user.reg directly -- Wine owns
#   that file and rewrites it (see .claude/hooks/guard-foreign-files.sh).
#
# Usage:
#   tools/wine-mouse-knobs.sh show
#   tools/wine-mouse-knobs.sh set   grab|grabfs|warp|all
#   tools/wine-mouse-knobs.sh clear grab|grabfs|warp|all
#
#   APPID=2210 tools/wine-mouse-knobs.sh show    # a different game's prefix
set -uo pipefail
APPID="${APPID:-3970}"
PFX="$HOME/.local/share/Steam/steamapps/compatdata/$APPID/pfx"
PROTON="$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/files/bin/wine"
[ -d "$PFX" ] || { echo "!! no prefix for appid $APPID at $PFX"; exit 1; }
export WINEPREFIX="$PFX" WINEDEBUG=-all

X11='HKCU\Software\Wine\X11 Driver'
DI='HKCU\Software\Wine\DirectInput'

show() {
  for k in "$X11:GrabPointer" "$X11:GrabFullscreen" "$DI:MouseWarpOverride"; do
    key="${k%:*}"; val="${k##*:}"
    out=$("$PROTON" reg query "$key" /v "$val" 2>/dev/null | grep -a "$val")
    printf '  %-46s %s\n' "$key\\$val" "${out:-<unset — Wine default>}"
  done
}

apply() { # apply <set|clear> <what>
  local act="$1" what="$2"
  do_one() { # do_one <key> <value> <data>
    if [ "$act" = set ]; then "$PROTON" reg add "$1" /v "$2" /t REG_SZ /d "$3" /f >/dev/null 2>&1 \
      && echo "  set   $1\\$2 = $3"
    else "$PROTON" reg delete "$1" /v "$2" /f >/dev/null 2>&1 && echo "  clear $1\\$2"
    fi
  }
  case "$what" in
    grab)   do_one "$X11" GrabPointer Y ;;
    grabfs) do_one "$X11" GrabFullscreen Y ;;
    warp)   do_one "$DI" MouseWarpOverride force ;;
    all)    do_one "$X11" GrabPointer Y; do_one "$X11" GrabFullscreen Y; do_one "$DI" MouseWarpOverride force ;;
    *) echo "!! what must be grab|grabfs|warp|all"; exit 2 ;;
  esac
  echo; echo "now:"; show
  [ "$what" = all ] && echo "
  !! You changed three variables at once. If the mouse improves you will not
     know which one did it. Clear them and reintroduce one at a time."
}

case "${1:-show}" in
  show) echo "appid $APPID prefix:"; show ;;
  set|clear) apply "$1" "${2:-}" ;;
  *) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
