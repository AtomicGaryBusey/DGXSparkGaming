#!/usr/bin/env bash
# pick-test-game.sh — find the SMALLEST owned game matching a render API.
#
# WHY THIS EXISTS
#   Testing a graphics-layer hypothesis needs a game with the right renderer, and
#   bandwidth here is the real cost. Guessing wasted 36 GB and 45 minutes once:
#   Shadow of the Tomb Raider was picked from memory, and — because no compat tool
#   was set first — Steam pulled its *native Linux* depot, which is useless for
#   Windows-side injection and runs at ~1 FPS anyway.
#   This asks Steam's own metadata instead: owned apps from localconfig.vdf, real
#   over-the-wire `download` sizes from appinfo.vdf, and DX12 evidence from each
#   game's declared launch options. PEAK (1.45 GiB) beat SOTTR (36 GB) 25:1.
#
#   TWO RULES this encodes, both learned the hard way:
#     1. Prefer `oslist: windows` titles — a native Linux depot is a trap for any
#        Windows-side test, and Steam will silently prefer it.
#     2. Set the compat tool BEFORE installing, never after.
#
# Usage:  ./tools/pick-test-game.sh [dx12|dx11|vulkan|any]
set -uo pipefail
API="${1:-dx12}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LC=$(ls "$HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf 2>/dev/null | head -1)
[ -f "$LC" ] || { echo "!! no localconfig.vdf found"; exit 2; }
python3 - "$HERE" "$LC" "$API" <<'PY'
import sys, re
sys.path.insert(0, sys.argv[1])
from appinfo import apps
lc, api = sys.argv[2], sys.argv[3].lower()
t = open(lc, encoding='utf-8', errors='replace').read()
i = t.find('"apps"')
owned = set(int(x) for x in re.findall(r'"(\d{3,7})"\s*\{', t[i:i+400000])) if i > 0 else set()
keys = {'dx12': ('dx12','d3d12','directx 12'), 'dx11': ('dx11','d3d11','directx 11'),
        'vulkan': ('vulkan',), 'any': ()}.get(api, ('dx12',))
rows = []
for a, ai in apps():
    if a not in owned: continue
    com = ai.get('common', {}) or {}
    if (com.get('type','') or '').lower() != 'game': continue
    launch = (ai.get('config', {}) or {}).get('launch', {}) or {}
    blob = ' '.join(str(v.get('description','')) for v in launch.values() if isinstance(v, dict)).lower()
    if keys and not any(k in blob for k in keys): continue
    dl = 0
    for k, v in (ai.get('depots', {}) or {}).items():
        if not isinstance(v, dict): continue
        m = (v.get('manifests') or {}).get('public')
        if not isinstance(m, dict): continue
        osl = ((v.get('config') or {}).get('oslist','') or '')
        if 'windows' in osl or osl == '': dl += int(m.get('download', 0) or 0)
    if dl: rows.append((dl, a, com.get('name','?'), com.get('oslist','')))
print(f"{'SIZE':>9}  {'APPID':<9} {'OS':<14} NAME")
for dl, a, n, osl in sorted(rows)[:20]:
    flag = '' if osl == 'windows' else '   <-- has non-Windows depot, set compat tool BEFORE installing'
    print(f"{dl/2**30:8.2f}G  {a:<9} {osl:<14} {n[:42]}{flag}")
PY
