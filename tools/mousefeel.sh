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

run_one() {
  local name="$1"; shift
  echo
  echo "=================================================================="
  echo " $name — move the mouse as prompted. Cursor will vanish (~20 s)."
  echo "=================================================================="
  "$@" 2>"$HOME/dgx-gaming-work/mousefeel-$name.trace"
  echo "  (wine trace: ~/dgx-gaming-work/mousefeel-$name.trace)"
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
