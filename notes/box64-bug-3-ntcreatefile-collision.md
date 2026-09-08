# Box64 bug #3 — `NtCreateFile` name collision faults and returns the wrong status under box32

Found 2026-09-08. Reproducer: `tools/probes/namedobj/namedobj32.c` (~200 lines, no game needed).

## Summary

Under Box64's 32-bit path (box32), a 32-bit Windows program that creates a **file or directory
that already exists** takes an access violation inside Wine's 32-bit syscall return path. Wine
catches it, but the caught fault **replaces the syscall's status**, so the program receives
`STATUS_ACCESS_VIOLATION` / `ERROR_NOACCESS` (998) instead of `STATUS_OBJECT_NAME_COLLISION` /
`ERROR_FILE_EXISTS` (80) or `ERROR_ALREADY_EXISTS` (183).

100% reproducible, one fault per call.

## Matrix

| binary | runtime | faults | `CreateFileA(CREATE_NEW)` on existing | `CreateDirectoryA` on existing |
|---|---|---|---:|---|
| 32-bit PE | **Box64 (box32)** | **100 / 100 calls** | **err=998 `ERROR_NOACCESS`** | **err=998 `ERROR_NOACCESS`** |
| 32-bit PE | FEX-Emu | 0 | err=80 `ERROR_FILE_EXISTS` | err=183 `ERROR_ALREADY_EXISTS` |
| 64-bit PE | Box64 | 0 | err=80 | err=183 |

Identical on **stock box64 v0.4.4** (`97aeb516…`) and on our locally patched build
(`89cd9de8…`), so the two local patches (libc box32 wrappers; x87 FSAVE tag word) are not the
cause. FEX being clean on the same Wine, same prefix, same binary is what implicates box32
rather than Wine — this repo's `tools/run-both.sh` rule.

## Scope — it is narrow

Everything adjacent is correct under box32, which is useful for whoever fixes it:

| case | status involved | result |
|---|---|---|
| `CreateMutexA` / `CreateEventA` / `CreateSemaphoreA` / `CreateFileMappingA` on an existing **name** | `OBJECT_NAME_COLLISION` | clean, err=183 |
| `CreateFileA(OPEN_EXISTING)` on a **missing** file | `OBJECT_NAME_NOT_FOUND` (`c0000034`) | clean, err=2 |
| `CreateFileA(CREATE_ALWAYS)` on an existing file (succeeds) | success + `ERROR_ALREADY_EXISTS` | clean, err=183 |
| `RemoveDirectoryA` on a missing directory | `OBJECT_NAME_NOT_FOUND` | clean, err=2 |

So it is **not** "named object collisions" in general — the kernel-object collisions are fine.
It is specifically `NtCreateFile` with `FILE_CREATE` disposition returning
`STATUS_OBJECT_NAME_COLLISION`. (`CreateDirectoryA` is also `NtCreateFile`/`FILE_CREATE`, with
`FILE_DIRECTORY_FILE`.)

## The fault record

Byte-identical between the probe and the games:

```
trace:seh:handle_syscall_fault code=c0000005 flags=0 addr=0x4000d1f0 ip=4000d1f0
trace:seh:handle_syscall_fault  info[0]=00000000        <- a read
trace:seh:handle_syscall_fault  info[1]=0000007c        <- of null+0x7c
trace:seh:handle_syscall_fault  eax=c0000035 ebx=00000000 ecx=00000000 edx=<varies> esi=00000000 edi=00000004
trace:seh:handle_syscall_fault  ebp=xxxxf7e8 esp=xxxxf4ac cs=0023 ds=002b es=002b fs=004b gs=0033
warn:seh:handle_syscall_fault backtrace: --- Exception 0xc0000005 at 0x4000d1f0:
    .../files/lib/wine/i386-unix/ntdll.so + 0x71f0 (_init + 0x1f0).
trace:seh:handle_syscall_fault returning to user mode ip=7bf1d620 ret=c0000005
```

`eax` already holds `c0000035` when it faults — the syscall completed and produced the correct
status; the fault is in the code that returns it. `esp`/`ebp` low bits, `eax`, `ebx`, `ecx`,
`esi`, `edi` are constant across every occurrence, so it is one code path re-entered, not
wandering corruption. `_init + 0x1f0` is a bogus symbolisation (nearest exported symbol);
the real location is `ntdll.so + 0x71f0`.

## Reproducing

```bash
~/dgx-gaming-work/toolchain/root/usr/bin/i686-w64-mingw32-gcc-win32 \
    -O1 -o namedobj32.exe tools/probes/namedobj/namedobj32.c
WINEDEBUG=+seh box64 <proton>/files/bin/wine namedobj32.exe 2>&1 | grep -c 'handle_syscall_fault code='
```

Count with a pattern anchored to `:seh:` — an earlier revision of the probe printed the literal
search strings in its own output and the naive grep matched the probe's own stdout.

## Why it matters here

Prey (2006) logged 276 of these and Quake 4 124, which is simply how many file/directory
creations each makes against paths that already exist. Both games tolerate the wrong error, so
this is **not** what makes them crash and **not** the cause of their odd mouse behaviour — a
DirectInput probe (`tools/probes/dinput/`) already refuted the input-path theory. It does mean
any 32-bit title using the ordinary "create it, ignore ALREADY_EXISTS" idiom will see a failure
where Windows reports a benign collision.

## Status

Not yet filed upstream (needs a GitHub account action). Everything a maintainer needs is above.
