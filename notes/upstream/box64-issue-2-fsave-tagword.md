# [box32] FSAVE/FNSTENV writes the x87 tag word stack-relative instead of physical

**Repo:** ptitSeb/box64 · **Version:** v0.4.4 (`2f130fab1`)
**Host:** NVIDIA GB10 (Grace-Blackwell), ARM64

## Summary

`fpu_savenv()` writes `emu->fpu_tags` directly. That field is indexed **stack-relative** (ST(i)),
but the x87 environment image defines the tag word as **physical** register order (R0..R7). The
two agree only when `TOP == 0`, so any `FSAVE`/`FNSTENV` taken with a non-zero TOP writes a tag
word rotated by `2 * TOP` bits.

Intel SDM Vol. 1 §8.1.7 and Vol. 2 (`FSTENV`) specify the physical ordering.

## Reproducer

Freestanding 32-bit assembly, no Wine, no libc — pushes N values, executes `FNSTENV`, and prints
the tag word:
`tools/isa-probe/x87tags.32.S` in <https://github.com/AtomicGaryBusey/DGXSparkGaming>
(`tools/isa-probe.sh` runs it under both box64 and FEX and diffs against the SDM-derived
expected values in `x87tags.32.expect`).

| pushes | TOP | expected tag word | box64 v0.4.4 | FEX |
|---:|---:|---|---|---|
| 3 | 5 | `0x03ff` | `0xffc0` | `0x03ff` |
| 7 | 1 | `0x3fff` | `0xfffc` | `0x3fff` |
| 0 | 0 | `0xffff` | `0xffff` | `0xffff` |

The observed values are the expected ones rotated by `2 * TOP`, which is the diagnosis.

## Fix

`src/emu/x87emu_private.c`, in `fpu_savenv()`, rotate into physical order before storing:

```c
uint16_t phys_tags = emu->fpu_tags;
{
    int rot = (emu->top & 7) * 2;
    if (rot)
        phys_tags = (uint16_t)(((uint32_t)phys_tags << rot) |
                               ((uint32_t)phys_tags >> (16 - rot)));
}
```

then write `phys_tags` instead of `emu->fpu_tags` through both the 16- and 32-bit store paths.

Verified against the probe for the 3-push and 7-push cases and for the empty-stack case (where
the rotation is a no-op and must not change the answer).

## Honest scope note

This was found while investigating id Tech 4's `Sys_FPU_StackIsEmpty()` fatal error (DOOM 3,
Quake 4, Prey), and it does **not** explain that crash: those games report `TOP=0`, where the
rotation is a no-op. It is a genuine, separate conformance bug found on the way.
