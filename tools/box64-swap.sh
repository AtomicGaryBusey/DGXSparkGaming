#!/usr/bin/env bash
# box64-swap.sh — install or revert a locally built box64, without destroying the
# stock binary by accident.
#
# WHY THIS EXISTS
#   A patched box64 can only be tested by replacing /usr/local/bin/box64: the game
#   runs inside pressure-vessel, and once that container namespace exists every
#   exec goes through binfmt_misc, whose interpreter is that exact path. Passing
#   the binary via BOX64_BIN affects only the first process (reaper), so a run
#   done that way tests NOTHING while looking exactly like a failed fix. That
#   near-miss cost a full debugging cycle on 2026-09-08.
#
#   So the swap is necessary, and it is also the most dangerous command in this
#   repo, because of one asymmetry:
#
#       sudo cp /usr/local/bin/box64 /usr/local/bin/box64.stock-backup
#
#   is harmless when the STOCK binary is installed and destroys the backup when
#   the PATCHED one is. Run it twice in the wrong order and the real stock binary
#   is gone from both paths; recovery is a full rebuild from a clean checkout.
#   This script makes that impossible: it refuses to overwrite a backup that does
#   not currently look like stock, and verifies by md5 rather than by hope.
#
# Usage:
#   tools/box64-swap.sh status     # what is installed right now
#   tools/box64-swap.sh install    # put the built box64 in place (backs up first)
#   tools/box64-swap.sh revert     # restore the stock binary
#
# Needs sudo for install/revert; `status` does not.
set -uo pipefail
LIVE=/usr/local/bin/box64
BACKUP=/usr/local/bin/box64.stock-backup
BUILT="${BOX64_BUILT:-$HOME/dgx-gaming-work/box64-symfix/bin/box64}"

sum() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
ver() { "$1" --version 2>&1 | grep -oE 'built on .*' | head -1; }
note() { printf '  %s\n' "$*"; }
die()  { printf '  \033[31mx %s\033[0m\n' "$*"; exit 1; }

L=$(sum "$LIVE"); B=$(sum "$BACKUP"); P=$(sum "$BUILT")

status() {
  printf '  %-46s %s\n' "path" "md5 / build"
  for f in "$LIVE" "$BACKUP" "$BUILT"; do
    [ -e "$f" ] && printf '  %-46s %s  %s\n' "$f" "$(sum "$f")" "$(ver "$f")" \
                || printf '  %-46s \033[90m(absent)\033[0m\n' "$f"
  done
  echo
  if   [ -n "$P" ] && [ "$L" = "$P" ]; then note "installed: \033[33mPATCHED\033[0m"
  elif [ -n "$B" ] && [ "$L" = "$B" ]; then note "installed: STOCK"
  else note "installed: UNKNOWN (matches neither the backup nor the built binary)"; fi
  if [ -n "$P" ] && [ "$B" = "$P" ]; then
    printf '  \033[31m! the backup holds the PATCHED build — the stock binary is NOT recoverable from it\033[0m\n'
  fi
}

case "${1:-status}" in
  status) status ;;

  install)
    [ -x "$BUILT" ] || die "no built box64 at $BUILT (run tools/build-box64-symfix.sh)"
    [ "$L" = "$P" ] && { note "already installed (patched)"; status; exit 0; }
    # Only ever back up something that is NOT the patched build.
    if [ -e "$BACKUP" ]; then
      [ "$B" = "$P" ] && die "backup already holds the patched build — refusing to touch it. Restore a real stock box64 first."
      note "backup exists and is not the patched build; leaving it alone"
    else
      [ "$L" = "$P" ] && die "live binary is already patched and there is no backup — cannot create a stock backup now"
      sudo cp -n "$LIVE" "$BACKUP" || die "could not create backup"
      note "backed up stock -> $BACKUP"
    fi
    sudo cp "$BUILT" "$LIVE" || die "install failed"
    [ "$(sum "$LIVE")" = "$P" ] || die "post-install md5 mismatch"
    note "installed the patched build"
    echo; status
    echo
    note "remember to revert when done:  tools/box64-swap.sh revert" ;;

  revert)
    [ -e "$BACKUP" ] || die "no backup at $BACKUP"
    [ -n "$P" ] && [ "$B" = "$P" ] && die "the backup IS the patched build — reverting would change nothing. Rebuild stock from a clean checkout."
    sudo cp "$BACKUP" "$LIVE" || die "revert failed"
    [ "$(sum "$LIVE")" = "$B" ] || die "post-revert md5 mismatch"
    note "reverted to stock"
    echo; status ;;

  *) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
