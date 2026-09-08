#!/usr/bin/env python3
"""x87-fuzz.py — differential fuzzer for x87 stack/tag semantics, FEX vs Box64.

WHY THIS EXISTS
---------------
id Tech 4's Sys_FPU_StackIsEmpty() reads the x87 TAG WORD and nothing else, and
fatals when it is not all-Empty. On this rig Prey strands SEVEN values and
Quake 4 strands THREE, both reporting TOP=0 -- and at TOP=0 Box64's known
tag-word rotation bug is a no-op, so those tag words are CORRECT. The values are
genuinely stranded. Something executes that pushes without a matching pop, or
pops without updating the tag word.

Hand-written probes found two real bugs but they only ever cover the case someone
already thought of: tools/isa-probe/x87tags.32.S tested three pushes, a fix made
that case correct, and Prey still died -- because Prey's state was seven pushes,
which nobody had written a case for. That is the argument for fuzzing rather than
for a nineteenth hand-written case.

THE ORACLE
----------
Differential: run the SAME 32-bit binary under FEX and under Box64 and compare
the tag word, TOP and status word after each sequence. Neither is trusted as
truth -- a disagreement proves only that at least one is wrong, and which one is
then settled against the Intel SDM by hand. That is a real limit and it is why
this complements tools/isa-probe.sh (whose answers come from the SDM) instead of
replacing it. Sequences both runtimes get identically wrong are invisible here,
exactly as CLAUDE.md's "when two implementations fail identically, suspect the
test" warns.

The first run of this tool reported that FEX computes 0x3800 >> 11 = 0. It was
right that the runtimes disagreed and wrong about why: the generated program had
a .data section, which triggers an unrelated FEX bug (tools/isa-probe/a3store.32.S)
that duplicates the instruction before a `mov %eax, moffs32` store. A differential
oracle finds real disagreements and tells you nothing about their cause, so an
absurd-looking result is a reason to dig, not to publish.

WHY THESE INSTRUCTIONS
----------------------
The pool is weighted toward things that move TOP or write tags without moving
data, because those are what an emulator most often gets wrong AND what id Tech 4
actually executes: DOOM 3's Sys_FPU_ClearStack() is a loop of FFREE + FINCSTP.
FPTAN/FSINCOS/FXTRACT push, FYL2X/FPATAN pop, FPTAN can REFUSE to push when its
operand is out of range (setting C2) -- a conditional stack effect, which is
precisely the shape of a bug that strands a value only sometimes. MMX ops set all
tags valid and EMMS sets them all empty, aliased onto the same register file.

Exceptions stay masked (FINIT leaves CW=0x037F), so stack overflow and underflow
produce the defined indefinite results instead of trapping. Every sequence is
therefore safe to run, and its result is defined by the SDM rather than by luck.

Usage:
  tools/x87-fuzz.py                     # 400 random sequences, minimise any find
  tools/x87-fuzz.py --cases 2000 --len 12
  tools/x87-fuzz.py --seed 12345        # reproduce a previous run exactly
  tools/x87-fuzz.py --replay 'fld1;ffree %st(0);fincstp'   # one sequence

Exit: 0 = the runtimes agreed everywhere, 1 = disagreement (printed + minimised),
      2 = could not build or run (never a silent pass).
"""
import argparse, random, struct, subprocess, sys, os, shutil, tempfile

# ---- instruction pool -------------------------------------------------------
# (text, comment) — every one is safe with exceptions masked.
PUSH = ["fld1", "fldz", "fldpi", "fldl2e", "fldl2t", "fldlg2", "fldln2",
        "flds fval", "fldl dval", "fildl ival"] + [f"fld %st({i})" for i in range(8)]
POP  = ["fstps out32", "fstpl out64", "fistpl out32",
        "faddp", "fsubp", "fmulp", "fdivp", "fsubrp", "fdivrp",
        "fcompp", "fucompp"] + \
       [f"fstp %st({i})" for i in range(8)] + \
       [f"fcomp %st({i})" for i in range(8)] + \
       [f"fucomp %st({i})" for i in range(8)]
# The tag/TOP manipulators — the prime suspects, and id Tech 4's own idiom.
TAGOPS = [f"ffree %st({i})" for i in range(8)] + ["fincstp", "fdecstp"]
# Conditional / multi-effect stack changes.
XFORM = ["fptan", "fsincos", "fxtract", "fyl2x", "fpatan", "f2xm1",
         "fscale", "fprem", "fprem1", "frndint", "fsqrt", "fabs", "fchs"]
PLAIN = [f"fxch %st({i})" for i in range(8)] + \
        [f"fadd %st({i}),%st" for i in range(8)] + \
        [f"fmul %st({i}),%st" for i in range(8)]
MMX   = ["emms", "movd ival,%mm0", "movq %mm0,%mm1", "paddd %mm1,%mm0"]

POOL = (PUSH * 3) + (POP * 3) + (TAGOPS * 4) + (XFORM * 2) + PLAIN + (MMX * 2)

# NO .data SECTION. This is not style — it is required for correctness.
#
# FEX-emu 2607 executes the instruction before a `mov %eax, moffs32` (the `a3`
# encoding) TWICE when the binary's writable segment is file-backed, i.e. when it
# has a .data section. The first version of this fuzzer put its float constants
# in .data and immediately "found" that FEX computes 0x3800 >> 11 = 0. That was
# this bug, not an x87 bug, and it would have been published as one.
# Reproducer and regression gate: tools/isa-probe/a3store.32.S.
# So the constants live in .bss and are written at runtime instead.
PROLOGUE = r"""/* GENERATED by tools/x87-fuzz.py — do not edit; regenerate with --seed.
 * Deliberately has NO .data section; see the note in the generator. */
    .code32
    .section .bss
    .lcomm  fval,  4
    .lcomm  dval,  8
    .lcomm  ival,  4
    .lcomm  env,   32
    .lcomm  out32, 4
    .lcomm  out64, 8
    .lcomm  buf,   %d
    .section .text
    .globl  _start
_start:
    movl    $0x3fc00000, fval        /* 1.5f  */
    movl    $0x00000000, dval
    movl    $0x40020000, dval+4      /* 2.25  */
    movl    $7, ival
"""

CASE = """
    finit
%s
    fnstenv env
    movl    $%d, buf+%d
    movzwl  env+8, %%eax
    movl    %%eax, buf+%d
    movzwl  env+4, %%eax
    movl    %%eax, %%edx
    shrl    $11, %%eax
    andl    $7, %%eax
    movl    %%eax, buf+%d
    movl    %%edx, buf+%d
    emms
"""

EPILOGUE = """
    movl    $4, %%eax
    movl    $1, %%ebx
    movl    $buf, %%ecx
    movl    $%d, %%edx
    int     $0x80
    movl    $1, %%eax
    xorl    %%ebx, %%ebx
    int     $0x80
"""

REC = 16  # caseidx, tagword, top, status


def emit(cases):
    n = len(cases)
    out = [PROLOGUE % (n * REC)]
    for i, ops in enumerate(cases):
        o = i * REC
        body = "\n".join("    " + x for x in ops)
        out.append(CASE % (body, i, o, o + 4, o + 8, o + 12))
    out.append(EPILOGUE % (n * REC))
    return "".join(out)


def build(asm, work):
    src = os.path.join(work, "fuzz.S")
    obj = os.path.join(work, "fuzz.o")
    exe = os.path.join(work, "fuzz")
    open(src, "w").write(asm)
    # The host has NO x86 assembler; the one inside FEX's RootFS is the only one.
    r = subprocess.run(["FEXBash", "-c",
                        f"as --32 -o '{obj}' '{src}' && ld -m elf_i386 -o '{exe}' '{obj}'"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, (r.stdout + r.stderr)
    return exe, None


def run(exe, how, box64_bin):
    if how == "fex":
        cmd = ["FEXBash", "-c", f"'{exe}'"]
    else:
        cmd = [box64_bin, exe]
    r = subprocess.run(cmd, capture_output=True, timeout=180)
    return r.stdout


def parse(raw, n):
    if len(raw) < n * REC:
        return None
    out = {}
    for i in range(n):
        idx, tag, top, sw = struct.unpack_from("<IIII", raw, i * REC)
        out[idx] = (tag, top, sw)
    return out


def compare(cases, work, box64_bin):
    """Returns list of (case_index, fex_tuple, box_tuple) that differ, or raises."""
    asm = emit(cases)
    exe, err = build(asm, work)
    if exe is None:
        raise RuntimeError("build failed:\n" + err)
    fx = parse(run(exe, "fex", box64_bin), len(cases))
    bx = parse(run(exe, "box64", box64_bin), len(cases))
    if fx is None or bx is None:
        raise RuntimeError("a runtime produced no/short output "
                           f"(fex={'ok' if fx else 'BAD'} box64={'ok' if bx else 'BAD'})")
    return [(i, fx[i], bx[i]) for i in range(len(cases)) if fx[i] != bx[i]]


def minimise(seq, work, box64_bin):
    """Delta-debug: drop instructions while the disagreement survives."""
    cur = list(seq)
    changed = True
    while changed and len(cur) > 1:
        changed = False
        for i in range(len(cur)):
            trial = cur[:i] + cur[i + 1:]
            if not trial:
                continue
            try:
                if compare([trial], work, box64_bin):
                    cur = trial
                    changed = True
                    break
            except RuntimeError:
                continue
    return cur


def show(tag_top_sw):
    tag, top, sw = tag_top_sw
    return f"tag=0x{tag:04x} top={top} status=0x{sw:04x}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=400)
    ap.add_argument("--len", type=int, default=8)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--replay", type=str, default=None,
                    help="run one ';'-separated sequence instead of fuzzing")
    ap.add_argument("--box64", default=os.environ.get("BOX64_BIN", "box64"))
    ap.add_argument("--keep", action="store_true", help="keep the work dir")
    a = ap.parse_args()

    if not shutil.which("FEXBash"):
        print("!! FEXBash not found — it supplies both the x86 assembler and the FEX side")
        return 2
    if not (shutil.which(a.box64) or os.path.exists(a.box64)):
        print(f"!! box64 not found: {a.box64}")
        return 2

    seed = a.seed if a.seed is not None else random.randrange(1 << 30)
    random.seed(seed)
    work = tempfile.mkdtemp(prefix="x87fuzz.", dir=os.environ.get("CLAUDE_JOB_DIR", "/tmp") + "/tmp"
                            if os.environ.get("CLAUDE_JOB_DIR") else None)

    print(f"x87 differential fuzzer — FEX vs Box64 ({a.box64})")
    print(f"  seed {seed}   (reproduce with --seed {seed})")

    try:
        if a.replay:
            cases = [[x.strip() for x in a.replay.split(";") if x.strip()]]
        else:
            cases = [[random.choice(POOL) for _ in range(random.randint(1, a.len))]
                     for _ in range(a.cases)]
        print(f"  {len(cases)} sequences, up to {a.len} instructions each")

        try:
            diffs = compare(cases, work, a.box64)
        except RuntimeError as e:
            print(f"!! {e}")
            return 2

        if not diffs:
            print(f"\n  no disagreement in {len(cases)} sequences.")
            print("  NOTE: this does not mean both are correct. A sequence both get")
            print("  identically wrong is invisible to a differential oracle — that is")
            print("  what tools/isa-probe.sh (SDM-derived answers) is for.")
            return 0

        print(f"\n  {len(diffs)} DISAGREEING sequences. Minimising…\n")
        seen = set()
        for idx, fx, bx in diffs:
            small = minimise(cases[idx], work, a.box64)
            key = ";".join(small)
            if key in seen:
                continue
            seen.add(key)
            try:
                d = compare([small], work, a.box64)
                fx2, bx2 = (d[0][1], d[0][2]) if d else (fx, bx)
            except RuntimeError:
                fx2, bx2 = fx, bx
            print(f"  --- minimal sequence ({len(small)} instr) ---")
            for op in small:
                print(f"        {op}")
            print(f"      FEX   : {show(fx2)}")
            print(f"      Box64 : {show(bx2)}")
            print(f"      replay: tools/x87-fuzz.py --replay '{key}'")
            print()
        print("  Now decide WHO is wrong against the Intel SDM (vol.1 8.1.7 tag word,")
        print("  vol.2 per instruction). A differential result names a disagreement,")
        print("  never a culprit. Add the winner to tools/isa-probe/*.expect so it is")
        print("  regression-gated from then on.")
        return 1
    finally:
        if a.keep:
            print(f"  work dir kept: {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
