# Box64 FSAVE/FNSTENV tag-word order — bug and fix, 2026-09-08

## The bug
src/emu/x87emu_private.h keeps emu->fpu_tags as a shift register indexed by STACK
position (push: fpu_tags<<=2, pop: fpu_tags>>=2). fpu_savenv() in x87emu_private.c
then writes that value straight out as the tag word. Intel SDM vol.1 8.1.7 defines
the FSAVE/FNSTENV tag word as indexed by PHYSICAL register R0..R7, with TOP naming
which physical register is ST0. So the right NUMBER of live registers is reported
in the wrong SLOTS.

## Why it went unnoticed
Almost nothing reads the tag word. id Tech 4 does, and reads nothing else:
    Sys_FPU_StackIsEmpty(): fnstenv; eax=[env+8]; eax ^= 0xFFFF; jz empty

## Observed in real games on a DGX Spark (GB10, ARM64)
  Prey 2006 reached gameplay (Regenerated world, 2560x1440) then died:
      CTRL=0000037f  STAT=00004000  TAGS=0000c000   (7 pushes, TOP=1)
      hardware would give 0x0003
  Quake 4 died on frame 1:
      TAGS=0000ffc0                                  (3 pushes, TOP=5)
      hardware would give 0x03ff
  Both are exactly rol16(fpu_tags, 2*TOP).

## The fix
In fpu_savenv(), rotate left by 2*TOP before writing:
    uint16_t phys_tags = emu->fpu_tags;
    int rot = (emu->top & 7) * 2;
    if (rot) phys_tags = (phys_tags << rot) | (phys_tags >> (16 - rot));
An all-empty tag word is 0xffff, and rotating 0xffff by any amount is still
0xffff, so a genuinely empty stack cannot regress.

## Verified by tools/isa-probe.sh (expected values from the Intel SDM)

  check   expected   STOCK box64   PATCHED box64
  CWD0    0x037f     0x037f        0x037f
  TAG0    0xffff     0xffff        0xffff     (empty stack — no regression)
  TAG3    0x03ff     0xffc0 BAD    0x03ff  OK (3 pushes)
  TOP3    5          5             5
  TAGB    0xffff     0xffff        0xffff     (balanced push/pop)

## Raw probe output (8-byte tag/value records)
stock:
 43 57 44 30 7f 03 00 00 54 41 47 30 ff ff 00 00
 54 41 47 33 c0 ff 00 00 54 4f 50 33 05 00 00 00
 54 41 47 42 ff ff 00 00 46 49 50 31 00 00 00 00
patched:
 43 57 44 30 7f 03 00 00 54 41 47 30 ff ff 00 00
 54 41 47 33 ff 03 00 00 54 4f 50 33 05 00 00 00
 54 41 47 42 ff ff 00 00 46 49 50 31 00 00 00 00

  TAG3 record is '54 41 47 33' followed by the LE value:
    stock   c0 ff -> 0xffc0
    patched ff 03 -> 0x03ff

## Reproduce
  tools/build-box64-symfix.sh
  BOX64_BIN=~/dgx-gaming-work/box64-symfix/bin/box64 tools/isa-probe.sh x87tags
