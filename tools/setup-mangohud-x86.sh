#!/usr/bin/env bash
# setup-mangohud-x86.sh — get an x86-64 MangoHud, because the distro one cannot
# possibly work here.
#
# WHY THIS EXISTS
#   game-run.sh has advertised "mangohud: on (CSV -> ...)" since it was written
#   and has never produced a single frametime CSV. Two independent reasons, both
#   found on 2026-09-07:
#     1. Its environment never reached the game at all -- `steam -applaunch` is an
#        IPC forwarder, and the Steam daemon spawns the game with ITS env. Fixed
#        separately by launching Proton directly.
#     2. THIS one, which survives that fix: the installed package is
#        `mangohud:arm64`, shipping only
#            /usr/lib/aarch64-linux-gnu/mangohud/libMangoHud.so
#            /usr/share/vulkan/implicit_layer.d/MangoHud.aarch64.json
#        An ARM64 Vulkan layer cannot be loaded into an x86-64 game process. The
#        tool's own hint -- "sudo apt install mangohud" -- pointed at a package
#        that was already installed and could never have helped.
#
#   So the numbers this performance log is built on were never being captured,
#   and bench-ab.sh rests on the same mechanism. That is the whole reason the
#   results table is full of adjectives.
#
#   Same approach as setup-mingw.sh: pull the official Ubuntu .deb and unpack it
#   into a local prefix. No sudo, nothing installed system-wide, no third-party
#   binaries, trivially deletable.
#
# KNOWN LIMIT, stated rather than discovered later: Ubuntu ships no i386 build of
# mangohud, so 32-bit titles (Quake 4, DOOM 3, Prey -- all PE32) cannot be
# instrumented this way. They are also all OpenGL, which needs MangoHud's GL path
# rather than the Vulkan layer. For those, use the engine's own com_showFPS and
# tools/watch-run.sh. This covers the 64-bit DXVK/VKD3D titles, which is where
# every performance comparison in this log actually lives.
#
# Usage:  tools/setup-mangohud-x86.sh [prefix]     (default ~/dgx-gaming-work/mangohud-x86)
#         then: eval "$(tools/setup-mangohud-x86.sh --env)"
set -uo pipefail
POOL="http://archive.ubuntu.com/ubuntu/pool/universe/m/mangohud/"
PREFIX="${1:-$HOME/dgx-gaming-work/mangohud-x86}"
[ "${1:-}" = "--env" ] && PREFIX="$HOME/dgx-gaming-work/mangohud-x86"

LAYERDIR="$PREFIX/root/usr/share/vulkan/implicit_layer.d"
if [ "${1:-}" = "--env" ]; then
  [ -d "$LAYERDIR" ] || { echo "# not installed; run tools/setup-mangohud-x86.sh" >&2; exit 1; }
  echo "export VK_ADD_LAYER_PATH='$LAYERDIR'"
  exit 0
fi

mkdir -p "$PREFIX/debs" "$PREFIX/root"
SO="$PREFIX/root/usr/lib/x86_64-linux-gnu/mangohud/libMangoHud.so"
if [ -f "$SO" ]; then echo "==> already present at $PREFIX"; else
  # Match the host's version when it exists, so the overlay and any host-side
  # mangohudctl agree; otherwise take the newest listed.
  HOSTVER=$(dpkg-query -W -f='${Version}' mangohud 2>/dev/null || true)
  LIST=$(curl -sS --max-time 30 "$POOL" | grep -oE '"mangohud_[^"]*_amd64\.deb"' | tr -d '"' | sort -u)
  [ -n "$LIST" ] || { echo "!! could not list $POOL"; exit 1; }
  DEB=""
  [ -n "$HOSTVER" ] && DEB=$(printf '%s\n' "$LIST" | grep -F "_${HOSTVER}_" | head -1)
  [ -z "$DEB" ] && DEB=$(printf '%s\n' "$LIST" | tail -1)
  echo "==> host mangohud: ${HOSTVER:-none};  fetching $DEB"
  # Resume + retry: on 2026-09-07 this truncated repeatedly because five Steam
  # downloads were saturating the link. A partial .deb that dpkg then rejects is
  # a confusing way to fail.
  curl -fL --retry 5 --retry-all-errors --retry-delay 3 -C - --max-time 600 \
       -o "$PREFIX/debs/$DEB" "$POOL$DEB" \
    || { echo "!! download failed (network busy? re-run, it resumes)"; exit 1; }
  echo "==> sha256: $(sha256sum "$PREFIX/debs/$DEB" | cut -d' ' -f1)"
  dpkg-deb --info "$PREFIX/debs/$DEB" >/dev/null 2>&1 || { echo "!! not a valid .deb"; exit 1; }
  dpkg -x "$PREFIX/debs/$DEB" "$PREFIX/root"
fi
[ -f "$SO" ] || { echo "!! no libMangoHud.so after unpack"; exit 1; }
ARCH=$(file -b "$SO" | cut -d, -f2 | tr -d ' ')
echo "==> $SO"
echo "==> arch: $ARCH"
case "$(file -b "$SO")" in *x86-64*) ;; *) echo "!! not x86-64 — refusing"; exit 1;; esac

# The packaged layer JSON points at /usr/lib/..., which does not exist here.
# Rewrite every manifest to the absolute unpacked path.
mkdir -p "$LAYERDIR"
for j in "$PREFIX"/root/usr/share/vulkan/implicit_layer.d/*.json; do
  [ -e "$j" ] || continue
  python3 - "$j" "$SO" <<'PY'
import json, sys
p, so = sys.argv[1], sys.argv[2]
d = json.load(open(p))
lay = d.get("layer") or {}
if lay.get("library_path"):
    lay["library_path"] = so
    json.dump(d, open(p, "w"), indent=2)
    print(f"  rewrote {p} -> {so}")
PY
done
echo
echo "==> done. game-run.sh picks this up automatically."
echo "    manual use:  eval \"\$(tools/setup-mangohud-x86.sh --env)\"  MANGOHUD=1 <cmd>"
