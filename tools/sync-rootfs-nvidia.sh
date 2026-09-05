#!/usr/bin/env bash
# sync-rootfs-nvidia.sh — keep the FEX RootFS's x86 NVIDIA userspace libs in step
# with the host aarch64 driver.
#
# WHY THIS EXISTS
#   Proton (running x86-64 under FEX) loads its GL/Vulkan/NGX libraries from the FEX
#   RootFS, not from the host. Those are hand-copied out of the *x86_64* NVIDIA driver
#   package during setup. When apt later bumps the host aarch64 driver, nothing updates
#   the RootFS copies, so the x86 libs Proton uses silently drift out of sync with the
#   running kernel driver. Symptoms are vague: DLSS/NGX failing to initialise, odd
#   Vulkan behaviour. Re-run this after every host driver bump.
#
# Idempotent: exits 0 immediately when already in sync. Needs no sudo.
set -euo pipefail

RF="${FEX_ROOTFS:-$HOME/.fex-emu/RootFS/Ubuntu_24_04}"
WORKDIR="${WORKDIR:-${TMPDIR:-/tmp}/nvidia-rootfs-sync}"
KEEP_DOWNLOAD="${KEEP_DOWNLOAD:-0}"
PRUNE="${PRUNE:-1}"          # remove superseded .so.<oldver> blobs (~1.2 GB each)
DRY_RUN="${DRY_RUN:-0}"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

[ -d "$RF" ] || die "FEX RootFS not found at $RF (override with FEX_ROOTFS=)"
[ -r /sys/module/nvidia/version ] || die "NVIDIA kernel module not loaded"

host_ver=$(cat /sys/module/nvidia/version)
rootfs_ver=$(ls "$RF/lib/x86_64-linux-gnu/" 2>/dev/null \
  | sed -n 's/^libnvidia-glcore\.so\.\([0-9][0-9.]*\)$/\1/p' | sort -V | tail -1)

info "host aarch64 driver : ${host_ver}"
info "RootFS x86 libs     : ${rootfs_ver:-<none found>}"

if [ "$rootfs_ver" = "$host_ver" ]; then
  info "already in sync — nothing to do."
  exit 0
fi

url="https://download.nvidia.com/XFree86/Linux-x86_64/${host_ver}/NVIDIA-Linux-x86_64-${host_ver}.run"
info "drift detected; fetching x86_64 driver ${host_ver}"
mkdir -p "$WORKDIR"; cd "$WORKDIR"
runfile="NVIDIA-Linux-x86_64-${host_ver}.run"

if [ ! -s "$runfile" ]; then
  curl -fsIL -o /dev/null "$url" || die "no x86_64 package published for ${host_ver} at ${url}"
  run "curl -fL --progress-bar -o '$runfile' '$url'"
fi

[ -d "NVIDIA-Linux-x86_64-${host_ver}" ] || run "sh '$runfile' -x >/dev/null"
src="$WORKDIR/NVIDIA-Linux-x86_64-${host_ver}"
[ -d "$src" ] || { [ "$DRY_RUN" = 1 ] || die "extraction failed"; }

link_variants() {  # $1=dir  $2=file.so.<ver>
  local d=$1 f=$2 base; base=$(echo "$f" | cut -d. -f1-2)
  ( cd "$d" && for v in 0 1 2; do ln -sf "$f" "$base.$v"; done )
}

copy_set() {       # $1=srcdir  $2=destdir  $3=label
  local sd=$1 dd=$2 label=$3 count=0
  [ -d "$dd" ] || die "RootFS lib dir missing: $dd"
  for f in "$sd"/*.so."$host_ver"; do
    [ -e "$f" ] || continue
    local b; b=$(basename "$f")
    if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] cp %s -> %s\n' "$b" "$dd"
    else cp -f "$f" "$dd/$b"; link_variants "$dd" "$b"; fi
    count=$((count+1))
  done
  info "${label}: ${count} libraries"
}

info "installing NGX wine bridge DLLs"
run "mkdir -p '$RF/usr/lib/x86_64-linux-gnu/nvidia/wine'"
if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] cp $src/*.dll -> RootFS nvidia/wine/"
else cp -f "$src"/*.dll "$RF/usr/lib/x86_64-linux-gnu/nvidia/wine/"; fi

copy_set "$src"    "$RF/lib/x86_64-linux-gnu" "x86_64"
copy_set "$src/32" "$RF/lib/i386-linux-gnu"   "i386"

if [ "$PRUNE" = 1 ] && [ -n "$rootfs_ver" ] && [ "$DRY_RUN" != 1 ]; then
  dangling=$(find "$RF" -type l -lname "*${rootfs_ver}*" 2>/dev/null | wc -l)
  if [ "$dangling" -eq 0 ]; then
    freed=$(find "$RF/lib/x86_64-linux-gnu" "$RF/lib/i386-linux-gnu" -maxdepth 1 \
              -name "*.so.${rootfs_ver}" -printf '%s\n' 2>/dev/null | awk '{t+=$1} END{printf "%.1f", t/1073741824}')
    find "$RF/lib/x86_64-linux-gnu" "$RF/lib/i386-linux-gnu" -maxdepth 1 \
      -name "*.so.${rootfs_ver}" -delete
    info "pruned superseded ${rootfs_ver} blobs (~${freed:-0} GiB reclaimed)"
  else
    info "skipped prune — ${dangling} symlink(s) still reference ${rootfs_ver}"
  fi
fi

if [ "$DRY_RUN" != 1 ]; then
  broken=$(find "$RF/lib/x86_64-linux-gnu" "$RF/lib/i386-linux-gnu" -maxdepth 1 -xtype l 2>/dev/null | wc -l)
  [ "$broken" -eq 0 ] || die "$broken broken symlink(s) left behind — inspect $RF manually"
  [ -e "$RF/lib/x86_64-linux-gnu/libGLX_nvidia.so.0" ] || die "libGLX_nvidia.so.0 missing after sync"
  [ -e "$RF/usr/lib/x86_64-linux-gnu/nvidia/wine/nvngx.dll" ] || die "nvngx.dll missing after sync"
  info "verified: libGLX_nvidia.so.0 -> $(readlink "$RF/lib/x86_64-linux-gnu/libGLX_nvidia.so.0")"
fi

[ "$KEEP_DOWNLOAD" = 1 ] || rm -rf "$WORKDIR"
info "RootFS now in sync with host driver ${host_ver}."
