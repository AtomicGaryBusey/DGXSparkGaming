#!/usr/bin/env bash
# mousefeel.sh — measure the mouse path the way an id Tech 4 game uses it.
#
# WHY THIS EXISTS
#   "The mouse behaves oddly" is unfalsifiable, and this project spent a day
#   attaching that sentence to whatever log line happened to be nearby. Twice.
#   First to a DirectInput theory, refuted by tools/probes/dinput/dinput-enum32.c;
#   then to a flood of c0000005 faults, which turned out to be a filesystem-status
#   bug (notes/box64-bug-3-ntcreatefile-collision.md) with no connection to input.
#
#   This runs tools/probes/dinput/mousefeel32.c, which reads the SAME hand
#   movement through DirectInput (exclusive + relative + buffered, exactly what
#   id Tech 4 asks for) and through Win32 raw input at the same time. Raw input is
#   the control: a separate Wine path with no warping, grabbing or clipping. If
#   the two disagree about one movement, the DirectInput path is at fault and the
#   shape of the disagreement names the bug. If they agree, the input layer is
#   fine and the problem is above or below it -- which is also an answer, and a
#   cheaper one than another day of theories.
#
#   BEFORE running this, check the window size. On a 5120x1440 desktop both games
#   were configured (by tools/idtech4-prep.sh, our own tool) to a 2560x1440
#   "fullscreen" window covering half the screen. Wine decides fullscreen by
#   comparing window rect to monitor rect, so the pointer was never confined the
#   way an exclusive-mode game expects. Fix the resolution first; it is free.
#
# Usage:
#   tools/mousefeel.sh              # both runtimes, one after the other
#   tools/mousefeel.sh box64|fex    # just one
#
# It grabs the mouse exclusively for ~20 s per runtime and the cursor vanishes.
# It always exits by itself; ESC also quits. You must be at the machine.
set -uo pipefail
cd "$(dirname "$0")/.."
WHICH="${1:-both}"
SRC=tools/probes/dinput/mousefeel32.c
EXE="$HOME/dgx-gaming-work/mousefeel32.exe"
CC="$HOME/dgx-gaming-work/toolchain/root/usr/bin/i686-w64-mingw32-gcc-win32"
PROTON="$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/files/bin/wine"
PFX="$HOME/.local/share/Steam/steamapps/compatdata/3970/pfx"

[ -x "$CC" ] || { echo "!! no 32-bit mingw. Run: MINGW_ARCH=i686 tools/setup-mingw.sh"; exit 1; }
[ -e "$PROTON" ] || { echo "!! no Proton wine at $PROTON"; exit 1; }
[ -d "$PFX" ]    || { echo "!! no wine prefix at $PFX (launch Prey once first)"; exit 1; }

echo "==> building probe"
"$CC" -O1 -o "$EXE" "$SRC" -ldinput8 -ldxguid -lole32 -luser32 || exit 1

echo "==> display: $(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"
grep -hE 'r_customWidth|r_customHeight' \
  "$HOME/.local/share/Steam/steamapps/common/Prey 2006/base/autoexec.cfg" 2>/dev/null \
  | sed 's/^/    game is configured for: /'

# X-SERVER CONTROL. Wine's rawinput is not usable as a control here: with
# RIDEV_INPUTSINK this Wine logs "Unhandled flags" and delivers nothing, and with
# flags=0 it still delivers nothing while DirectInput receives thousands of
# events -- measured 2026-09-08. So the control moves OUTSIDE Wine entirely.
#
# `xinput test-xi2 --root` reports each RawMotion with TWO numbers per valuator:
# the accelerated value and, in parentheses, the RAW device delta. That answers a
# question no Wine-side probe can: whether pointer acceleration is being applied
# before the game ever sees the motion.
#
# This matters on this machine specifically. `xinput list` shows the pointer
# devices are `xwayland-pointer` and `xwayland-relative-pointer` -- there is NO
# physical trackball in X at all. mutter owns the device and synthesises a
# virtual pointer, so the chain is:
#     trackball -> libinput -> mutter (accel) -> Xwayland -> Wine -> DI -> game
xi_start() {
  XI_LOG="$HOME/dgx-gaming-work/mousefeel-xi2.log"
  : > "$XI_LOG"
  if command -v xinput >/dev/null 2>&1; then
    xinput test-xi2 --root >"$XI_LOG" 2>/dev/null &
    XI_PID=$!
  else
    XI_PID=""; echo "  (xinput missing — no X-server control)"
  fi
}
xi_stop() {
  [ -n "${XI_PID:-}" ] && kill "$XI_PID" 2>/dev/null
  [ -s "${XI_LOG:-/nonexistent}" ] || { echo "  X control: no events captured"; return; }
  awk '
    /RawMotion/      { inraw=1; next }
    /^EVENT/         { inraw=0 }
    inraw && /^ *[01]: / {
        acc=$2; raw=$3; gsub(/[()]/,"",raw)
        if (acc<0) acc=-acc; if (raw<0) raw=-raw
        if ($1=="0:") { ax+=acc; rx+=raw; n++ } else { ay+=acc; ry+=raw }
    }
    END {
      if (n==0) { print "  X control: 0 RawMotion events"; exit }
      printf "  X control (outside Wine): %d raw motion events\n", n
      printf "    X accelerated travel |x| : %.0f\n", ax
      printf "    X RAW device travel  |x| : %.0f\n", rx
      if (rx>0) printf "    accel factor applied by the compositor: %.2fx\n", ax/rx
    }' "$XI_LOG"
}

run_one() {
  local name="$1"; shift
  echo
  echo "=================================================================="
  echo " $name — move the mouse as prompted. Cursor will vanish (~20 s)."
  echo "=================================================================="
  xi_start
  "$@" 2>"$HOME/dgx-gaming-work/mousefeel-$name.trace"
  echo
  xi_stop
  echo "  (wine trace: ~/dgx-gaming-work/mousefeel-$name.trace)"
  echo "  COMPARE: the probe's DI travel|x| totals against 'X RAW device travel' above."
  echo "    DI ~= X raw            -> the input path is faithful; look at m_smooth / engine."
  echo "    DI ~= X accelerated    -> the game is getting COMPOSITOR-ACCELERATED motion,"
  echo "                              which for a trackball is a real feel problem and has"
  echo "                              nothing to do with FEX, Box64 or window geometry."
  echo "    DI far from both       -> the DirectInput path is rescaling; that is a Wine bug."
}

case "$WHICH" in
  box64|both) run_one box64 env WINEPREFIX="$PFX" BOX64_LOG=0 "$PROTON" "$EXE" ;;
esac
case "$WHICH" in
  fex|both) run_one fex FEXBash -c "env WINEPREFIX='$PFX' BOX64_LOG=0 '$PROTON' '$EXE'" ;;
esac

echo
echo "Read the DI/RAW ratio lines. Both agreeing = input layer is fine; look at"
echo "window size, engine smoothing (m_smooth) or Xwayland, not at the translator."
