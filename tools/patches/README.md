# `tools/patches/` — GPL-3.0, unlike the rest of this repository

**Everything in this directory is licensed GPL-3.0-or-later.** The rest of `tools/` is MIT
and the documentation is CC BY 4.0; this is the one deliberate exception.

## Why

`optiscaler-clang-portability.py` modifies [OptiScaler](https://github.com/optiscaler/OptiScaler)
source, specifically the NR fork
[wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass).
Both are GPL-3.0. Each edit quotes a short excerpt of that source as its anchor and emits a
modified version of it, which makes these modifications a derivative work of OptiScaler
regardless of what licence covers the script that applies them.

They were originally embedded in a heredoc inside `tools/build-optiscaler-nr.sh`. Splitting
them out on 2026-09-07 makes the licence boundary explicit rather than buried, and has the
side benefit of making them easier to re-sync when upstream moves.

Nothing else in this repository is derived from, links against, or requires OptiScaler.
The build script *fetches* it at build time; this repository vendors no third-party source.

## What the patches are

Not features, and not changes to OptiScaler's behaviour. Every one is a **clang-vs-MSVC
portability fix**, needed only because this builds on ARM64 with clang + `lld-link` + `xwin`
instead of MSBuild on Windows. Each carries a comment naming the language rule MSVC lets
slide:

| File | Problem |
|---|---|
| `external/streamline/sl_pcl.h` | `using to_underlying = std::to_underlying;` — an alias to a function template is invalid C++. MSVC never reaches the branch because it reports `__cplusplus == 199711L`. |
| `OptiScaler/with_dx12/dx11_with_dx12.h` / `.cpp` | In-class `inline static` of a nested type evaluates that type's default member initialisers while the enclosing class is still incomplete. Moved out-of-line. |
| `OptiScaler/hooks/Gdi32_Hooks.h` | `VALIDATE_HOOK` declares the function `extern`, so a later `static` does not give internal linkage and every including TU emits the symbol. `inline` merges them. |
| `OptiScaler/hooks/Kernel_Hooks.h` | `constexpr HMODULE = HMODULE(0xFFFF...)` is a `reinterpret_cast`, not a constant expression. `static inline const` is the same sentinel without `constexpr`. |
| `OptiScaler/inputs/FfxApiExe_Dx12.cpp` | Five file-local shims are declared `extern` in a header and defined there too; `static` after an `extern` declaration keeps external linkage, so they collide. Renamed. |
| `OptiScaler/framegen/ffx/FSRFG_Dx12.cpp` | `_version = {}` is ambiguous between implicit copy-assign and `feature_version::operator=(const version_t&)`. |

## A note on the format

These are Python string replacements rather than unified diffs. That is deliberate: a `.patch`
file needs exact surrounding context and breaks on any upstream churn, while an anchor/marker
pair survives unrelated edits nearby and reports honestly when the anchor is genuinely gone
(`ANCHOR NOT FOUND — upstream changed?`). Naming these `.patch` would misrepresent what they
are.

Each is **idempotent** via a `marker` string that only exists after application. Testing the
first line of the replacement is wrong whenever that line is also the anchor — it always
matches, so the patch silently never applies and the build fails much later at link time.
That cost a full build cycle to discover, and it is the reason the helper takes `marker`
separately from `new`.

## Running them

```bash
cd <optiscaler source tree>
python3 /path/to/tools/patches/optiscaler-clang-portability.py
```

`tools/build-optiscaler-nr.sh` does this for you after cloning and initialising submodules.

## Provenance

This repository builds OptiScaler **from source** rather than shipping a binary, on purpose.
Before the NR fork was used, its bundled libraries were verified byte-identical to upstream's.
No third-party prebuilt DLLs are used or distributed here.
