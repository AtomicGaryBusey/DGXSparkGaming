# [box32] Missing libc wrappers cause steamclient_init access violation

**Repo:** ptitSeb/box64 · **Version:** v0.4.4 (`2f130fab1`), also HEAD at time of writing
**Host:** NVIDIA GB10 (Grace-Blackwell), ARM64, Ubuntu, kernel 6.17
**Guest:** 32-bit Windows PE under Proton Experimental (Wine), i.e. box32

## Summary

Four libc symbols have no box32 wrapper. Steam's 32-bit `steamclient.so` binds them with
`RTLD_NOW`, the bind-now relocation fails, and the failure surfaces as an access violation in
`steamclient_init` rather than as a missing-symbol error the caller could handle.

## Symptoms

```
Symbol arc4random not found
Symbol strfromf128 not found
Symbol strtof128 not found
Symbol strtold not found
```
plus 2 × `libstdc++ Plt` failures and 1 × access violation in `steamclient_init`.

## Fix

`src/wrapped32/wrappedlibc_private.h`, after `GO(strtod, dEpBp_)`:

```c
GO(arc4random,  uEv)
GO(strtof128,   DEpBp_)
GO(strfromf128, iEpLpD)
```

and uncomment the existing `//GO(strtold, DEpp)` on the same table. Note `strtold` must be
*uncommented*, not added — adding a third entry makes the wrapper generator fail with
`The symbol strtold is duplicated!`.

## Verification

| | before | after |
|---|---:|---:|
| missing-symbol errors | 9 | 1 |
| libstdc++ Plt failures | 2 | 0 |
| `steamclient_init` access violations | 1 | 0 |

Build script that applies this idempotently, for reproduction:
`tools/build-box64-symfix.sh` in <https://github.com/AtomicGaryBusey/DGXSparkGaming>.
