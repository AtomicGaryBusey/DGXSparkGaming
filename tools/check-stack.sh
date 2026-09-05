#!/usr/bin/env bash
# check-stack.sh — run the README's Prerequisites Checklist plus the drift and
# Proton-runtime traps that have actually bitten this project.
# Read-only. No sudo. Exit 0 = all pass, 1 = at least one FAIL.
set -uo pipefail

pass=0; fail=0; warn=0
ok()   { printf '  \033[32m✅\033[0m %-34s %s\n' "$1" "${2:-}"; pass=$((pass+1)); }
no()   { printf '  \033[31m❌\033[0m %-34s %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
hm()   { printf '  \033[33m⚠️ \033[0m %-34s %s\n' "$1" "${2:-}"; warn=$((warn+1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

S="${STEAM_ROOT:-$HOME/.local/share/Steam}"
RF="${FEX_ROOTFS:-$HOME/.fex-emu/RootFS/Ubuntu_24_04}"

hdr "Base NVIDIA stack"
if [ -r /sys/module/nvidia/version ]; then
  dv=$(cat /sys/module/nvidia/version)
  case "$dv" in 580.*) ok "1 · NVIDIA driver" "$dv (open kernel)";;
    "") hm "1 · NVIDIA driver" "version unparsed";;
    *)  hm "1 · NVIDIA driver" "$dv — off the 580 branch; GB10 is only validated on 580";; esac
else no "1 · NVIDIA driver" "nvidia module not loaded"; fi

if command -v nvcc >/dev/null 2>&1; then ok "2 · CUDA toolkit" "$(nvcc --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')"
else hm "2 · CUDA toolkit" "nvcc not on PATH"; fi

[ -f /usr/share/vulkan/icd.d/nvidia_icd.json ] && ok "3 · NVIDIA Vulkan ICD" || no "3 · NVIDIA Vulkan ICD" "missing"

# /sys/module/nvidia_drm/parameters/modeset is mode 0400 (root-only), so infer it:
# DRM connectors under an nvidia-bound card only appear when modeset=1 took effect.
nvcard=$(for c in /sys/class/drm/card[0-9]*; do
           [ -e "$c/device/driver" ] || continue
           [ "$(basename "$(readlink -f "$c/device/driver")")" = nvidia ] && basename "$c" && break
         done)
if [ -n "$nvcard" ] && compgen -G "/sys/class/drm/${nvcard}-*" >/dev/null; then
  ok "4 · nvidia-drm modeset=1" "$nvcard + $(ls -d /sys/class/drm/${nvcard}-* | wc -l) connectors"
elif [ -n "$nvcard" ]; then no "4 · nvidia-drm modeset=1" "$nvcard has no connectors — modeset off?"
else no "4 · nvidia-drm modeset=1" "no DRM card bound to nvidia"; fi

if command -v vulkaninfo >/dev/null 2>&1; then
  gpu=$(vulkaninfo --summary 2>/dev/null | sed -n 's/.*deviceName *= *\(NVIDIA.*\)/\1/p' | head -1)
  [ -n "$gpu" ] && ok "5 · vulkan-tools" "$gpu" || no "5 · vulkan-tools" "no NVIDIA device enumerated"
else no "5 · vulkan-tools" "vulkaninfo not installed"; fi

g=$(id -nG); case " $g " in *" video "*) case " $g " in *" render "*) ok "6 · video+render groups";;
  *) no "6 · video+render groups" "missing render";; esac;; *) no "6 · video+render groups" "missing video";; esac

hdr "Translation layers"
if command -v FEXBash >/dev/null 2>&1; then
  fv=$(dpkg-query -W -f='${Version}' fex-emu-armv8.4 2>/dev/null || echo '?')
  ok "7 · FEX-Emu" "armv8.4 $fv"
else no "7 · FEX-Emu" "FEXBash not on PATH"; fi

[ -f "$HOME/.fex-emu/Config.json" ] && ok "8 · FEX Config.json" || no "8 · FEX Config.json" "missing"
[ -x "$RF/usr/bin/bash" ] && ok "8 · FEX RootFS userland" "$RF" \
  || no "8 · FEX RootFS userland" "no guest bash — RootFS not extracted"

command -v steam >/dev/null 2>&1 && ok "9 · Steam" "$(command -v steam)" || no "9 · Steam" "not on PATH"
grep -qc FEXBash /usr/lib/steam/bin_steam.sh 2>/dev/null && ok "9 · Steam ARM64 patch" \
  || hm "9 · Steam ARM64 patch" "bin_steam.sh not patched"

if command -v box64 >/dev/null 2>&1; then ok "10 · Box64" "$(box64 --version 2>&1 | head -1 | cut -d' ' -f1-4)"
else no "10 · Box64" "not on PATH"; fi

ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -qiE 'box64|FEX' \
  && ok "11 · x86 binfmt handlers" "$(ls /proc/sys/fs/binfmt_misc/ | grep -iE 'box64|box32|FEX' | tr '\n' ' ')" \
  || no "11 · x86 binfmt handlers" "none registered"

hdr "RootFS driver drift  (tools/sync-rootfs-nvidia.sh fixes)"
hv=$(cat /sys/module/nvidia/version 2>/dev/null || echo '?')
rv=$(ls "$RF/lib/x86_64-linux-gnu/" 2>/dev/null | sed -n 's/^libnvidia-glcore\.so\.\([0-9][0-9.]*\)$/\1/p' | sort -V | tail -1)
if [ "$hv" = "$rv" ]; then ok "RootFS x86 NVIDIA libs" "$rv — matches host"
else no "RootFS x86 NVIDIA libs" "RootFS ${rv:-none} vs host ${hv} — DRIFTED"; fi
[ -e "$RF/usr/lib/x86_64-linux-gnu/nvidia/wine/nvngx.dll" ] \
  && ok "NGX bridge DLLs (DLSS)" "present in RootFS" \
  || no "NGX bridge DLLs (DLSS)" "nvngx.dll missing — DLSS will silently disable"

hdr "Proton + required runtimes"
have_manifest() { [ -f "$S/steamapps/appmanifest_$1.acf" ] && \
  grep -q '"StateFlags"[[:space:]]*"4"' "$S/steamapps/appmanifest_$1.acf" 2>/dev/null; }
for d in "$S"/steamapps/common/Proton*; do
  [ -d "$d" ] || continue
  nm=$(basename "$d"); ver=$(head -c 64 "$d/version" 2>/dev/null | tr -d '\n' | cut -d' ' -f2)
  rt=$(sed -n 's/.*"require_tool_appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$d/toolmanifest.vdf" 2>/dev/null)
  if [ -z "$rt" ]; then hm "$nm" "no require_tool_appid"; continue; fi
  if have_manifest "$rt"; then ok "$nm" "${ver:-?} · runtime $rt ok"
  else no "$nm" "${ver:-?} · RUNTIME $rt NOT INSTALLED — will not launch"; fi
done

printf '\n\033[1m%d passed, %d warnings, %d failed\033[0m\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
