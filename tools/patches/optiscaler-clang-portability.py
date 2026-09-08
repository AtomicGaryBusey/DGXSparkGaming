#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# optiscaler-clang-portability.py — build fixes for OptiScaler under clang.
#
# LICENSE NOTE — THIS FILE IS GPL-3.0, THE REST OF THE REPOSITORY IS NOT.
#   Every edit below quotes a short excerpt of OptiScaler source as its anchor and
#   emits a modified version of it. OptiScaler is GPL-3.0, so these modifications
#   are a derivative work of it and carry that license, regardless of the MIT
#   license covering the rest of tools/. Split out of build-optiscaler-nr.sh on
#   2026-09-07 so that boundary is unambiguous rather than buried in a heredoc.
#
#   Upstream:  https://github.com/optiscaler/OptiScaler            (GPL-3.0)
#   NR fork:   https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass  (GPL-3.0)
#
# WHAT THESE ARE
#   Not features and not fixes to OptiScaler's behaviour: every one is a
#   clang-vs-MSVC portability fix, needed because this builds on ARM64 with
#   clang + lld-link instead of MSBuild. Each carries a comment saying which
#   language rule MSVC lets slide. They are deliberately narrow so they stay
#   easy to re-sync when upstream moves.
#
# IDEMPOTENT: each patch tests a `marker` string that exists ONLY after it has
#   been applied. Testing the first line of the replacement is WRONG when that
#   line is also the anchor -- it always matches, so the patch silently never
#   applies and the build fails much later at link time. That cost a full build
#   cycle to find.
#
# CONTRACT: run with the OptiScaler source tree as the current directory.
#   Invoked by tools/build-optiscaler-nr.sh; safe to run by hand.

import re, sys
def patch(path, old, new, tag, marker):
    # `marker` must be a string that exists ONLY after the patch is applied. Testing new's first
    # line is wrong when that line is the anchor itself (it always matches, so the patch silently
    # never applies and the build fails later at link time).
    try: t=open(path,encoding="utf-8",errors="replace").read()
    except FileNotFoundError: print(f"  !! missing {path}"); return False
    if marker in t: print(f"  = {tag} (already applied)"); return True
    if old not in t: print(f"  !! {tag}: ANCHOR NOT FOUND — upstream changed?"); return False
    open(path,"w",encoding="utf-8").write(t.replace(old,new,1)); print(f"  + {tag}"); return True

patch("external/streamline/sl_pcl.h",
 "#if __cplusplus == 202302L\nusing to_underlying = std::to_underlying;",
 "// PATCHED FOR CLANG (local build only): alias to a function template is invalid C++; MSVC never\n"
 "// reaches this branch because it reports __cplusplus == 199711L. Force the correct fallback.\n"
 "#if 0  // was: __cplusplus == 202302L\nusing to_underlying = std::to_underlying;",
 "sl_pcl.h to_underlying", "#if 0  // was: __cplusplus == 202302L")

patch("OptiScaler/with_dx12/dx11_with_dx12.h",
 "    inline static D3D11_UPSCALER_RESOURCE_CACHE_C UpscalerResourceCache = {};",
 "    // PATCHED FOR CLANG (local build only): in-class inline static of a nested type evaluates that\n"
 "    // type's default member initializers while the enclosing class is incomplete. Defined out-of-line.\n"
 "    static D3D11_UPSCALER_RESOURCE_CACHE_C UpscalerResourceCache;",
 "dx11_with_dx12.h static", "    static D3D11_UPSCALER_RESOURCE_CACHE_C UpscalerResourceCache;")

patch("OptiScaler/with_dx12/dx11_with_dx12.cpp",
 '#include "with_dx12.h"\n',
 '#include "with_dx12.h"\n\n// PATCHED FOR CLANG (local build only): out-of-line definition; class is complete here.\n'
 'Dx11WithDx12::D3D11_UPSCALER_RESOURCE_CACHE_C Dx11WithDx12::UpscalerResourceCache = {};\n',
 "dx11_with_dx12.cpp definition", "Dx11WithDx12::UpscalerResourceCache = {};")

patch("OptiScaler/hooks/Gdi32_Hooks.h",
 "static NTSTATUS hkD3DKMTQueryAdapterInfo(const D3DKMT_QUERYADAPTERINFO* data)",
 "// PATCHED FOR CLANG (local build only): VALIDATE_HOOK above declares this extern, so `static`\n"
 "// does not give internal linkage and every including TU emits the symbol. inline merges them.\n"
 "inline NTSTATUS hkD3DKMTQueryAdapterInfo(const D3DKMT_QUERYADAPTERINFO* data)",
 "Gdi32_Hooks.h inline", "inline NTSTATUS hkD3DKMTQueryAdapterInfo")

patch("OptiScaler/hooks/Kernel_Hooks.h",
 "    static constexpr HMODULE amdxc64Mark = HMODULE(0xFFFFFFFF13372137);",
 "    // PATCHED FOR CLANG (local build only): int->pointer is a reinterpret_cast, not a constant\n"
 "    // expression. `static inline const` is the same sentinel object without constexpr.\n"
 "    static inline const HMODULE amdxc64Mark = HMODULE(0xFFFFFFFF13372137);",
 "Kernel_Hooks.h constexpr", "static inline const HMODULE amdxc64Mark")

# FfxApiExe_Dx12.cpp: five file-local shims whose names are declared extern in FfxApi_Dx12.h and
# defined there too -- `static` after an extern declaration keeps external linkage, so they collide.
p="OptiScaler/inputs/FfxApiExe_Dx12.cpp"
s=open(p,encoding="utf-8",errors="replace").read()
n=0
for fn in ("ffxCreateContext_Dx12","ffxDestroyContext_Dx12","ffxConfigure_Dx12","ffxQuery_Dx12","ffxDispatch_Dx12"):
    if f"Exe_{fn}(" in s: continue
    s=s.replace(f"static ffxReturnCode_t {fn}(", f"static ffxReturnCode_t Exe_{fn}(")
    s=re.sub(rf'(?<![A-Za-z0-9_"]){fn}\b(?!\s*:)', f"Exe_{fn}", s); n+=1
if n: open(p,"w",encoding="utf-8").write(s)
print(f"  {'+' if n else '='} FfxApiExe_Dx12.cpp renames ({n} changed)")

p="OptiScaler/framegen/ffx/FSRFG_Dx12.cpp"
s=open(p,encoding="utf-8",errors="replace").read()
if "_version = feature_version{};" in s: print("  = FSRFG_Dx12.cpp (already applied)")
elif "    _version = {};" in s:
    s=s.replace("    _version = {};",
      "    // PATCHED FOR CLANG (local build only): `= {}` is ambiguous between implicit copy-assign\n"
      "    // and feature_version::operator=(const version_t&).\n    _version = feature_version{};",1)
    open(p,"w",encoding="utf-8").write(s); print("  + FSRFG_Dx12.cpp ambiguity")
else: print("  !! FSRFG_Dx12.cpp anchor not found")
