#!/usr/bin/env python3
"""pick-runtime.py — which JIT can actually run this title, from what it imports.

WHY THIS EXISTS
---------------
On 2026-09-08 it was measured that FEX can set **0 of 320** pixel formats for a
32-bit Windows program under Wine, while Box64 manages 320/320 and a 64-bit build
under FEX manages 320/320 (tools/probes/wgl/wgl-formatsweep32.c). So a 32-bit
OpenGL title cannot create a GL context under FEX at all. That is the whole id
Tech 4 family.

The tempting simplification is "Box64 for 32-bit, FEX for 64-bit". It is WRONG,
and this repo's own results table disproves it: Half-Life 2 is 32-bit and runs
smooth and maxed at 5120x1440 under FEX, because DX9 goes through DXVK to
*Vulkan* -- a different thunk that works. The broken path is GLX, not 32-bit code
generation. So the axis is the RENDER API, not the word size, and that is a fact
about a specific binary rather than something to remember.

Hence this tool: read the actual import tables and say what the evidence supports.

WHAT IT DOES NOT DO
-------------------
It does not claim one runtime is FASTER. Nobody here has ever benchmarked FEX
against Box64 on any title -- every runtime claim in this log is functional. If
you want a performance statement, run tools/bench-ab.sh and get numbers.

It also will not pretend the picture is settled: README's Daikatana row (32-bit,
ref_gl.dll, which imports SetPixelFormat) claims excellent performance "through
FEX's 32-bit path", which contradicts the 0/320 measurement. That run predates
run.json and carries no verified runtime, so it is flagged, not trusted. See
docs/OPEN-QUESTIONS.md. If it is ever shown that some 32-bit GL titles DO work
under FEX, this tool's rule is what needs revisiting.

Usage:
  tools/pick-runtime.py <path-to-exe> [--gamedir DIR] [--quiet]

Prints a human-readable rationale on stderr and one machine-readable line on
stdout:  VERDICT=box64 | VERDICT=fex | VERDICT=either
"""
import os, struct, sys, glob

GL = {"opengl32.dll"}
# ddraw.dll is deliberately NOT here. DirectDraw is 2D/video and enumeration;
# Quake 4 and Prey both import it while being OpenGL-only, and counting it as a
# 3D renderer made this tool call them "either" -- i.e. it would have sent two
# titles we KNOW fail under FEX to FEX. Only real 3D device DLLs belong here.
D3D = {"d3d8.dll", "d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d11.dll",
       "d3d12.dll", "dxgi.dll"}
VK = {"vulkan-1.dll"}
DD = {"ddraw.dll"}


def pe_info(path):
    """Return (bits, {imported dll names lowercased}) or None if not a PE."""
    try:
        d = open(path, "rb").read()
    except OSError:
        return None
    if len(d) < 0x40 or d[:2] != b"MZ":
        return None
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    if pe + 24 > len(d) or d[pe:pe + 4] != b"PE\0\0":
        return None
    machine, nsec = struct.unpack_from("<HH", d, pe + 4)
    opt_size = struct.unpack_from("<H", d, pe + 20)[0]
    magic = struct.unpack_from("<H", d, pe + 24)[0]
    bits = 64 if magic == 0x20B else 32
    ddir = pe + 24 + (112 if bits == 64 else 96)

    sections = []
    soff = pe + 24 + opt_size
    for i in range(nsec):
        o = soff + i * 40
        if o + 40 > len(d):
            break
        va, rawsz, rawptr = struct.unpack_from("<III", d, o + 12)
        sections.append((va, rawsz, rawptr))

    def rva2off(rva):
        for va, rawsz, rawptr in sections:
            if va <= rva < va + max(rawsz, 1):
                return rawptr + (rva - va)
        return None

    def cstr(off):
        if off is None or off >= len(d):
            return None
        e = d.find(b"\0", off)
        return d[off:e].decode("latin-1", "replace") if e > off else None

    names = set()
    # directory 1 = imports, directory 13 = delay-load imports. Games delay-load
    # opengl32 often enough that checking only the first misses them.
    for idx, stride, name_off in ((1, 20, 12), (13, 32, 4)):
        try:
            rva, size = struct.unpack_from("<II", d, ddir + idx * 8)
        except struct.error:
            continue
        if not rva or not size:
            continue
        off = rva2off(rva)
        if off is None:
            continue
        for k in range(0, 4096):
            e = off + k * stride
            if e + stride > len(d):
                break
            chunk = d[e:e + stride]
            if chunk == b"\0" * stride:
                break
            nr = struct.unpack_from("<I", d, e + name_off)[0]
            if not nr:
                continue
            n = cstr(rva2off(nr))
            if n and n.lower().endswith(".dll"):
                names.add(n.lower())
    return bits, names


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in sys.argv
    gamedir = None
    if "--gamedir" in sys.argv:
        gamedir = sys.argv[sys.argv.index("--gamedir") + 1]
    if not args:
        print(__doc__.strip().split("Usage:")[1], file=sys.stderr)
        return 2
    exe = args[0]
    if gamedir is None:
        gamedir = os.path.dirname(exe) or "."

    info = pe_info(exe)
    if info is None:
        print(f"  not a PE file (or unreadable): {exe}", file=sys.stderr)
        print("VERDICT=either")
        return 0
    bits, imports = info

    # The renderer often lives in a sibling DLL, not the exe: Daikatana's GL
    # backend is ref_gl.dll and the exe imports no GL at all. Scanning only the
    # exe would call that title "no OpenGL" and be wrong.
    scanned = 1
    for dll in sorted(glob.glob(os.path.join(gamedir, "*.dll")) +
                      glob.glob(os.path.join(gamedir, "*", "*.dll")))[:250]:
        sub = pe_info(dll)
        if sub and sub[0] == bits:
            imports |= sub[1]
            scanned += 1

    # An import-table scan alone is not enough. The Quake lineage loads its
    # renderer with LoadLibrary("opengl32.dll") from inside ref_gl.dll, so
    # NOTHING imports opengl32 statically -- Daikatana came back "no OpenGL",
    # which is exactly backwards. Modern titles do the same for d3d12/dxgi.
    # So also look for the names as strings in the same files.
    dynamic = set()
    files = [exe] + [d for d in sorted(glob.glob(os.path.join(gamedir, "*.dll")) +
                                       glob.glob(os.path.join(gamedir, "*", "*.dll")))[:250]]
    wanted = [n.encode() for n in (GL | D3D | VK)]
    for f in files:
        try:
            blob = open(f, "rb").read().lower()
        except OSError:
            continue
        for w in wanted:
            if w in blob:
                dynamic.add(w.decode())
    allrefs = imports | dynamic

    gl = sorted(allrefs & GL)
    d3d = sorted(allrefs & D3D)
    vk = sorted(allrefs & VK)
    dd = sorted(allrefs & DD)

    if not quiet:
        print(f"  binary        : {bits}-bit  ({os.path.basename(exe)})", file=sys.stderr)
        print(f"  scanned       : exe + {scanned - 1} same-arch DLL(s) in {gamedir}", file=sys.stderr)
        how = lambda n: "import" if n in imports else "dynamic"
        fmt = lambda lst: ", ".join(f"{n} ({how(n)})" for n in lst) if lst else "-"
        print(f"  OpenGL        : {fmt(gl)}", file=sys.stderr)
        print(f"  Direct3D      : {fmt(d3d)}", file=sys.stderr)
        print(f"  Vulkan        : {fmt(vk)}", file=sys.stderr)
        if dd:
            print(f"  (DirectDraw   : {fmt(dd)} — 2D/video, not counted as a 3D renderer)",
                  file=sys.stderr)

    if bits == 32 and gl and not d3d and not vk:
        if not quiet:
            print("  verdict       : \033[33mBox64\033[0m — 32-bit and OpenGL-only.", file=sys.stderr)
            print("                  FEX sets 0 of 320 pixel formats for 32-bit Wine", file=sys.stderr)
            print("                  programs, so it cannot create a GL context at all.", file=sys.stderr)
        print("VERDICT=box64")
    elif bits == 32 and gl and (d3d or vk):
        if not quiet:
            print("  verdict       : \033[33meither, but prefer a non-GL backend on FEX\033[0m —", file=sys.stderr)
            print("                  32-bit with BOTH GL and D3D/Vulkan backends. FEX can run", file=sys.stderr)
            print("                  the D3D one (Half-Life 2 does, at 5120x1440); it cannot", file=sys.stderr)
            print("                  run the GL one. Force the D3D renderer, or use Box64.", file=sys.stderr)
        print("VERDICT=either")
    else:
        if not quiet:
            why = "64-bit" if bits == 64 else "32-bit, no OpenGL import"
            print(f"  verdict       : FEX is fine ({why}). Box64 remains a valid", file=sys.stderr)
            print("                  fallback to TRY on failure — not a performance claim,", file=sys.stderr)
            print("                  since the two have never been benchmarked here.", file=sys.stderr)
        print("VERDICT=fex")
    return 0


if __name__ == "__main__":
    sys.exit(main())
