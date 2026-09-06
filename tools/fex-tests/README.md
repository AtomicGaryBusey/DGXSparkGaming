# fex-tests/

Self-contained Windows PE test sources used to answer *"does Windows-side code injection
survive FEX on GB10?"* — the question the DLSS 5 Path A route rests on.

All of these are **our own code**, deliberately: the alternative was executing prebuilt
binaries from a one-day-old repository. Built with `tools/setup-mingw.sh` (Ubuntu's own
mingw-w64, unpacked locally, no sudo) and run by `tools/fex-inject-tests.sh`.

| file | answers |
|---|---|
| `hook-inline-patch.c` | Does patching a function prologue at runtime take effect, or does the JIT run stale translated code? (**PASS** on FEX and Box64) |
| `load-forwarder.c` | Does the NGX forwarder shim load and execute under translation? (**PASS**) |
| `load-reshade.c` | Standalone ReShade load — **inconclusive by design**; ReShade declines a bare load outside a D3D host. Kept as the record of a method that does *not* work. |
| `ngx-arch-probe.c` | Asks the ARM64 NGX core what GPU architecture it reports for GB10. Produced `0x7FFFFFF` (wildcard) — the result that killed the "GB10 is architecture-gated" theory. |
| `ngx-stub-snippet.c` | A fake NGX snippet exporting only the metadata getters, so `NGXValidateSnippetMetaData` runs and logs the driver's own values. **Not an NVIDIA artifact** — anything built from this must never be mistaken for one. |

**Binaries are not committed.** Build them; don't trust a stray `.dll` that looks like an NGX
snippet. Check `file` and `strings` for a `/dvs/p4/build/...` provenance path first.
