#!/usr/bin/env bash
# config-snapshot.sh — snapshot and diff the config files that OTHER PROGRAMS
# rewrite behind your back, so an experiment's inputs are known rather than assumed.
#
# WHY THIS EXISTS
#   Every one of these was discovered by accident on 2026-09-06/07, mid-experiment:
#     * OptiScaler rewrites OptiScaler.ini on exit, persisting whatever was changed
#       in its overlay. Two DLSS runs were done on top of settings (Style=1,
#       WhitePointSource=2, an empty ScanAnchors) nobody knew were there, and the
#       results could not be attributed.
#     * Cyberpunk rewrites UserSettings.json. Frame Generation turned itself back on
#       between runs; DLSS quality flipped from Balanced to Auto. Both silently
#       invalidated comparisons that were already underway.
#     * Wine rewrites the prefix user.reg on exit, so DLL overrides set by hand can
#       be reordered or lost.
#     * Steam rewrites localconfig.vdf (launch options) when it exits.
#   The hook in .claude/hooks/guard-foreign-files.sh stops you EDITING these blind.
#   This shows you what CHANGED, which is the other half of the problem.
#
# Usage:
#   tools/config-snapshot.sh save <label> [appid]     # default appid 1091500
#   tools/config-snapshot.sh diff <label> [appid]     # snapshot vs current
#   tools/config-snapshot.sh list
#
#   FILES="/a /b" tools/config-snapshot.sh save mylabel   # override the file set
set -uo pipefail
CMD="${1:-}"; LABEL="${2:-}"; APPID="${3:-1091500}"
STEAM="$HOME/.local/share/Steam/steamapps"
SNAPROOT="$HOME/dgx-gaming-work/config-snapshots"

game_dir() { local m="$STEAM/appmanifest_$APPID.acf" d
  d=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$m" 2>/dev/null | head -1)
  [ -n "$d" ] && printf '%s' "$STEAM/common/$d"; }

default_files() {
  local g; g="$(game_dir)"
  [ -n "$g" ] && {
    printf '%s\n' "$g/bin/x64/OptiScaler.ini" "$g/bin/x64/ReShade.ini"
  }
  printf '%s\n' "$STEAM/compatdata/$APPID/pfx/user.reg"
  find "$STEAM/compatdata/$APPID/pfx/drive_c/users/steamuser" -name 'UserSettings.json' 2>/dev/null | head -1
  ls "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf 2>/dev/null | head -1
}

file_list() { if [ -n "${FILES:-}" ]; then printf '%s\n' $FILES; else default_files; fi | while read -r f; do [ -n "$f" ] && [ -f "$f" ] && echo "$f"; done; }

case "$CMD" in
  list)
    [ -d "$SNAPROOT" ] || { echo "no snapshots yet"; exit 0; }
    for d in "$SNAPROOT"/*/; do [ -d "$d" ] && printf '  %-28s %s  (%s files)\n' "$(basename "$d")" "$(stat -c%y "$d" | cut -c1-19)" "$(ls "$d" | grep -c '\.copy$')"; done ;;
  save)
    [ -z "$LABEL" ] && { echo "usage: $0 save <label> [appid]"; exit 2; }
    D="$SNAPROOT/$LABEL"; rm -rf "$D"; mkdir -p "$D"
    n=0
    while read -r f; do
      k=$(printf '%s' "$f" | sha256sum | cut -c1-16)
      cp "$f" "$D/$k.copy" 2>/dev/null || continue
      printf '%s\t%s\t%s\n' "$k" "$(stat -c%Y "$f")" "$f" >> "$D/manifest"
      n=$((n+1))
    done < <(file_list)
    echo "saved $n files to $D"
    while read -r f; do echo "  $f"; done < <(file_list) ;;
  diff)
    [ -z "$LABEL" ] && { echo "usage: $0 diff <label> [appid]"; exit 2; }
    D="$SNAPROOT/$LABEL"; [ -f "$D/manifest" ] || { echo "no snapshot '$LABEL'"; exit 1; }
    changed=0
    while IFS=$'\t' read -r k mtime f; do
      if [ ! -f "$f" ]; then echo "  GONE     $f"; changed=$((changed+1)); continue; fi
      if cmp -s "$D/$k.copy" "$f"; then continue; fi
      changed=$((changed+1))
      echo "=== CHANGED: $f"
      echo "    snapshot mtime $(date -d "@$mtime" '+%F %T')   now $(stat -c%y "$f" | cut -c1-19)"
      diff -u "$D/$k.copy" "$f" 2>/dev/null | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
        | grep -vE '^[+-]\s*$' | head -40 | sed 's/^/    /'
      echo
    done < "$D/manifest"
    [ "$changed" -eq 0 ] && echo "  no changes since snapshot '$LABEL'" || echo "  $changed file(s) changed"
    ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
esac
