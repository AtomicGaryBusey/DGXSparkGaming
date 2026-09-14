# DLSS 5 NR reference binaries preserved from NBA 2K27 — and what they say about GB10

**2026-09-14.** NBA 2K27 is DLSS 5's launch title (NVIDIA's own article: *"DLSS 5 is available
starting now in NBA 2K27"*). Before uninstalling it for disk, its `data/streamline/` directory was
preserved. The binaries live in `~/dgx-gaming-work/dlss5-reference/nba2k27-streamline/`, **outside
this public repo** — they are proprietary. Only hashes and sizes are recorded here.

## The acquisition question is now settled

Previous research (`notes/2026-09-05-dlss5-research-*.md`) concluded the NR route *"requires a
~165 MB proprietary DLL that ships inside retail games"*, and that the only documented working
configuration used **a community-patched model circulated in a Discord channel** — an acquisition
route this project explicitly ruled out on legal grounds.

That obstacle is gone. AGB owns NBA 2K27; the file shipped with it.

| | bytes | SHA-256 |
|---|---:|---|
| **`nvngx_dlssnr.dll` (ours, retail)** | 165,840,496 | `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` |
| community-patched (from the 09-05 notes) | 165,840,496 | `8270B350CD82DE5CE89806872CDD6B6A9249B80836B91BBEB3573470744CC206` |

**Byte-identical in size, different in content.** That is consistent with the reported modding
technique — rewriting CUDA fatbins *in place* — which preserves file length. We now hold the
pristine original as a baseline against which any patched copy can be diffed.

Also preserved: `nvngx_dlss.dll` (58,956,400), `nvngx_dlssg.dll` (7,453,808), the Streamline
interposer and plugins (`sl.dlss_nr.dll`, `sl.interposer.dll`, and six others), and the NVIDIA
licence texts. Full manifest in `PROVENANCE.txt` beside the binaries.

## What the NR DLL reveals about hardware gating

Strings from `nvngx_dlssnr.dll`:

- **`-arch sm_120`, fifteen times, and no other architecture.** The surrounding strings are NVRTC
  command lines (`-e cg2r_copy_kernel -arch sm_120 -m 64 -split-compile 0`), so the DLL compiles
  its CUDA kernels **at runtime** with the target architecture **hardcoded**.
- **`DLSSNR: Unsupported GPU architecture 0x%x, minimum required 0x%x`** — an explicit gate, with
  `NVSDK_NGX_GetGPUArchitecture` beside it. Note the wording: a **minimum**, not an equality.

**GB10 on this machine reports compute capability 12.1** (`nvidia-smi --query-gpu=compute_cap`),
i.e. **sm_121**. The DLL targets **sm_120**.

**This is better news than it first looks.** CUDA's binary-compatibility rule is that a cubin built
for compute capability *X.y* runs on devices of *X.z* where **z ≥ y**. sm_120 → sm_121 is the same
major generation with a higher minor, so it is the *compatible* direction. And the gate is phrased
as a minimum, which 12.1 would clear.

By the same rule, **Ada (sm_89) is a different major generation and cannot run sm_120 code at all**
— which is exactly why modders must rewrite the fatbins for RTX 40, and why an RTX 4060 cannot
simply be pointed at this file.

## Status of the claim

**Inferred from strings and the documented CUDA compatibility rule — NOT executed.** Nobody has
run this DLL on GB10. Specifically unverified:

1. Whether the runtime NVRTC path actually succeeds when the device is sm_121 and the flag says
   sm_120 (NVRTC may refuse a mismatch even where a prebuilt cubin would load).
2. What value the gate compares against, and whether it tests a *family* rather than a number.
3. Everything above the CUDA layer: the repo's earlier conclusion that NR costs 40–60% of frame
   time makes it **unplayable on 273 GB/s regardless of whether it loads**. Running and being
   usable are different questions, and only the first is addressed here.

*Cheapest decisive test:* load `nvngx_dlssnr.dll` under the stack and read what
`NVSDK_NGX_GetGPUArchitecture` returns and whether the gate message fires —
`tools/wine-dll-loadtest.sh` exists for exactly this and names the faulting module rather than
guessing.
