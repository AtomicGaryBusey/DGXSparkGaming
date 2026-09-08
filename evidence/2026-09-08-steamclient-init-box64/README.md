# `steamclient_init` access violation — evidence

Backs the *"`steamclient_init` access violation — root-caused to Box64"* section of
[`../../README.md`](../../README.md) and the signature row in
[`../../docs/DIAGNOSTICS.md`](../../docs/DIAGNOSTICS.md).

Documented to the `log-result` convention: the six questions are answered explicitly below,
because the value of this log is that its claims are true, and two published claims have
already turned out not to be.

---

## 1. What was observed, without interpretation?

DOOM 3 (9050), Prey 2006 (3970) and RoE (9070), launched under **Box64**, write no engine log
at all and their Proton log contains `err:steamclient:steamclient_call Access violation in
steamclient_init`. The same titles launched under **FEX** reach their own config parser, write
`qconsole.log`, and fail later and differently (`SetPixelFormat failed`). Quake 4 (2210) shows
neither failure under either runtime.

## 2. Does the thing measured belong to the claim?

Yes, and this is the question that killed two earlier claims here, so it is answered stepwise.
The chain is not inferred from the AV — each link was read off a file:

| Link | How it was established |
|---|---|
| The exe is SteamStub-wrapped | PE header parsed directly: entry point falls **inside** a `.bind` section for Prey/DOOM 3/RAGE, inside `.text` for Quake 4 |
| It loads `Steam.dll` at runtime | Neither exe imports it statically; it appears as module ~#44 in the load order, after all static imports |
| Proton redirects `steamclient` to `lsteamclient` | ValveSoftware/wine `53ba023e` |
| That unix half needs `libstdc++` | `readelf -dW i386-unix/lsteamclient.so` — one of only two `.so` in `i386-unix/` that does |
| Box64 lacks four of its imports | `src/wrapped32/` at box64 `2f130fab1`: three absent, `strtold` commented out at `wrappedlibc_private.h:1754` |
| `dlopen` therefore fails | The log shows the missing symbols, then `relocating Plt symbols in elf libstdc++.so.6` |
| So the handle is NULL and the call faults | Fault dump shows `eax=00000000 edx=00000000` at `ntdll.so+0x465d6`, where the instruction is `call dword ptr [eax+edx*4]` |

The last row is the important one: the faulting instruction was **decoded from the binary**, not
assumed. `eax` is the unixlib handle.

## 3. What is the control?

Three, and all three are in this directory or reproducible by `verify.sh`:

- **Same title, other runtime.** Prey under FEX: **zero** missing-symbol errors, **zero** AVs
  (`prey-fex-control.txt`). Everything else — Proton, container, prefix, config — held constant.
- **Same runtime, other title.** Quake 4 under Box64: zero of both, and it *plays*. It has no
  `.bind` section, so it never enters the path.
- **The negative case for the discriminator.** Prey and Quake 4 are *both*
  `legacykeyregistrationmethod=disk` in Steam's appinfo yet behave oppositely, which rules the
  DRM key out as the cause and points at the PE instead.

## 4. If it should change pixels, did anyone look?

Not applicable — this is a crash before any rendering. GPU utilisation for the affected runs is
in each run's `gpu.csv`.

## 5. What would falsify this?

`verify.sh` is written so that each check *can* fail, and says what it means when it does:

- Any of the four symbols turning out to be wrapped in `src/wrapped32/` (upstream may fix this).
- The container's i386 `libstdc++` not importing them.
- An entry point *not* in `.bind` for Prey/DOOM 3, or one that *is* for Quake 4.
- The FEX control run showing the same missing-symbol errors — that would mean it is not
  Box64-specific.

The strongest falsification is the fix itself: **build box64 with the four entries added, and
the `Symbol ... not found` lines and the AV should both disappear.** That has not been done yet
and the README says so.

## 6. Evidence

| File | What it is |
|---|---|
| `verify.sh` | Re-runs all 16 checks. Exit 0 = the README entry is supported. |
| `verify-output-2026-09-08.txt` | Its output on the day of the claim: 16/16 pass. |
| `prey-box64-failure-chain.txt` | The excerpt: missing symbols → `libstdc++` Plt failure → load order → `eax=0` fault → AV. |
| `prey-fex-control.txt` | The control: same title under FEX, zeros throughout. |
| `../runs/3970-*`, `../runs/9050-*` | Run manifests, each recording `runtime_actual`. |
| `../../notes/2026-09-08-ultracode-steamclient-init-dive.md` | The research run that proposed the chain (14 agents, 1.48M tokens, 8 of 9 findings survived verification). |

Full Proton logs are on the machine, not in git — `tools/find-logs.sh 3970`.

## Provenance, stated plainly

The chain was **proposed by a multi-agent research run**, then re-derived locally before any of
it was written into `README.md`. That order matters: an earlier run's headline claim was
demolished by five minutes of local disassembly, and this project has published agent findings
that were wrong. Nothing here rests on an agent's word.
