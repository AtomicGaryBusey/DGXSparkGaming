# COMPLETENESS CRITIQUE — DLSS 5 on GB10 synthesis

## 0. The method caveat is worse than stated, and it is fixable in two minutes

The synthesis ends with "every research angle exhausted the 200-call WebSearch budget… no open-ended discovery was possible… Reddit was unreachable." That caveat is load-bearing for at least eight negative claims, and it is **an artifact of only trying two channels**. From this machine, right now:

- `gh api /search/repositories` and `/search/code` work fully authenticated and unthrottled. **This is a complete discovery channel for exactly the ecosystem the verdict depends on**, and it was used only to run a handful of `total_count` queries that were then reported as global negatives.
- Bing via plain `curl` returns real SERPs (title-verified). It degrades to spam filler on narrow queries, so it is a weak channel — but it is not nothing, and it is how I found the NVIDIA research page below.
- Reddit is genuinely dead here (403 on `reddit.com`, `api.reddit.com`; old.reddit 404; redlib/searx instances 403/429; DDG and Mojeek both captcha). **Reddit remains unchecked, and the synthesis is right to flag it as the largest hole.** But it is now the *only* hole, not the general condition.

Because of this, the sentence *"GitHub searches for GB10/Spark/arm64 across the entire DLSS 5 ecosystem return `total_count: 0`"* is **false as written**. `gh api -X GET /search/code -f q='dlssnr GB10'` returns **9**; `'dlssnr aarch64'` returns **3**. (Several hits are this repo's own README and unrelated noise — but "zero across the ecosystem" was asserted as a verified negative and it is not one.)

---

## 1. The single biggest miss: NVIDIA's own DLSS 5 technical page and report were never cited

**[research.nvidia.com/labs/adlr/DLSS5/](https://research.nvidia.com/labs/adlr/DLSS5/)** — NVIDIA ADLR, **published September 01, 2026**, NVIDIA-official primary source. Fetched first-hand (HTTP 200). It does not appear anywhere in the synthesis, which cites only the GeForce marketing article. Verbatim content that matters:

- *"a one-step pixel-space diffusion model designed for high-resolution, real-time rendering"* — conditioned on *"the current rendered frame, engine motion vectors, carried temporal state, and artistic-direction values."*
- *"causal and deterministic… operates under a strict per-frame compute budget, enabling real-time rendering at up to 4K resolution."*
- *"DLSS 5 runs locally as a rendering stage within existing game pipelines on **GeForce RTX 50 Series GPUs**."*

That last line is a **stronger and better-sourced version of Blocker 3 than the synthesis had** — it is NVIDIA Research, not GeForce marketing, saying RTX 50. It does not change the verdict, but the synthesis's characterisation of blocker 3 as merely "product-tier marketing scope" now has to contend with NVIDIA's research org saying the same thing.

The page links **`files/DLSS5_Report.pdf`** — an NVIDIA technical report on DLSS 5. **I could not retrieve it** (403 from curl with browser UA + Referer, and 403 via WebFetch; Akamai bot block). This is now the top unretrieved primary source in the whole investigation, and it is the document most likely to contain the per-frame compute budget, precision, and hardware-requirement statements that the entire "playable on GB10?" question rests on. Anyone continuing this should fetch it from a real browser on this box (Chrome 152 aarch64 is installed) and save it into the repo's notes.

---

## 2. A source the synthesis misread, in the direction of its own conclusion

The synthesis states:

> *Issue #3: RTX 4080 (Ada), driver 610.57.04, GE-Proton11-6, GTA V Enhanced — 16,200 evaluations with a community-patched model, no failures.*

[NapXDD/addon-dlssnr-linux issue #3](https://github.com/NapXDD/addon-dlssnr-linux/issues/3) is titled **"RTX 40 + community-patched model: NGX call never returns, process dies with no Windows exception"** and is a **failure report against NapXDD's forwarder**, closed 2026-09-05. Read first-hand via `gh api`, the actual content is:

- With NapXDD's `ngx-probe`/forwarder: `D3D12_CreateFeature(feature=1)` entries = 1, **returns = 0, `nr-fwd:` lines = 0, feature 18 = 0**. Process dies inside the trampoline on the first real `CreateFeature`. No `c0000005`, no core dump, no Xid.
- The success on that same machine came from a **different implementation**: *"RenoDX DLSS5 4.5 (it reports itself as v4.1.5) goes all the way through… `feature 18 created via the signed snippet after DLSS/DLAA`… `inline feature 18 evaluation succeeded`."*

**This inverts the synthesis's own Path A recommendation.** Step 3 tells the user to deploy `dlssnr-linux.addon64` + `nvngx.dll_nrfwd.dll` from NapXDD v0.2.2 — which is the implementation with a documented Linux failure on non-RTX-50 hardware, while the thing that actually worked on Ada under Proton was the **RenoDX DLSS5 add-on** (clshortfuse). If GB10 is even slightly off the RTX-50 happy path, the recommended artifact is the wrong one. That is a concrete, actionable correction, not a nitpick.

Also from that issue, two facts the synthesis did not carry:
- The Ada success required a **community-patched** model (sha256 `8270B350CD82DE5CE89806872CDD6B6A9249B80836B91BBEB3573470744CC206`, 165,840,496 bytes) circulated in a Discord `#dlss5-downloads` channel. That is the acquisition route the synthesis correctly rules out on legal grounds — worth stating explicitly that the *documented working Linux configuration* depends on it.
- On an x86-64 host, `/usr/lib/nvidia/wine/` ships `_nvngx.dll`, `nvngx.dll`, `nvngx_dlssg.dll` from the driver. Consistent with this box's aarch64 directory being hand-made, and a good cross-check the synthesis could have cited.

---

## 3. "The one decidable unknown" is already decided, publicly, and the answer is favourable

The synthesis's §7 says under *"Nobody could establish"*: **"Whether `nvngx_dlssnr.dll` ships `sm_120` or `sm_120a` cubins."** It then builds Path A step 2 around carving fatbins out of a purchased game's DLL to find out.

That question is answered in a third-party RE project's committed documentation, retrievable in one `gh api` call — [ljmng7/Metal_DLSS5_Research](https://github.com/ljmng7/Metal_DLSS5_Research) `FINDINGS.md` and `PTX_AND_WEIGHT_LAYOUT.md` (audit dated **2026-09-05**), read first-hand:

> *"The Swapper `nvngx_dlssnr.dll` contains 15 NVIDIA fatbins. Each has an `sm_89` ELF CUBIN, a Zstandard-compressed plaintext PTX 9.4 entry targeted at `sm_120`, and an `sm_120` ELF CUBIN."*
> *"The 15 PTX modules expose 231 visible entry kernels."*

So: **plain `sm_120`, not `sm_120a`, plus `sm_120`-targeted PTX in every fatbin.** This box measured `sm_120` cubins loading and PTX JIT working; `sm_120a` was the only failing case. The hard-exclusion branch is closed and the JIT-fallback hedge is no longer a hedge. Confidence: **secondary but strong** — an independent RE project, corroborated by [xXJSONDeruloXx/dlssnr-native](https://github.com/xXJSONDeruloXx/dlssnr-native)'s tested filename `nvngx_dlssnr.approx-fp16-sm_75-sm_86-sm_89-sm_120.dll` (sha256 `dcc0dc24…`) and by dlssnr-patcher's one-PTX-per-fatbin assertion. It should be verified locally once a DLL is legitimately in hand, but it should no longer be listed as unknowable.

Same two sources also independently corroborate the FP8 claim at a level the synthesis lacked: **mixed FP8 E4M3 transformer core (blocks 15–55) + FP16 conv shell**, **153 tensors / ~147.7 MB weight blob / ~146–147M parameters**, **342 E4M3 matrices vs 2 FP16 matrices** ([windystrife/dlssnr-re](https://github.com/windystrife/dlssnr-re), [huaxueye/DLSSNR-Reversed](https://github.com/huaxueye/DLSSNR-Reversed)). This box's measured `QMMA.16832.F32.E4M3.E4M3` execution is therefore aimed at exactly the right instruction.

---

## 4. The user's leads: one genuinely run down, one badly under-sampled

**RTX Spark — run down properly.** I re-verified independently: [nvidia.com/en-us/products/rtx-spark/](https://www.nvidia.com/en-us/products/rtx-spark/) returns HTTP 200 and its spec table contains three `DLSS 5` cells and `OS Support: Windows 11` for both configurations. The synthesis's handling is accurate and its "indirectly yes, directly no" framing is right.

**"Posts from today" — hand-waved by under-sampling, not by dismissal.** The synthesis found NapXDD, dlssnr-patcher, DLSS-NR-on-AMD, dlss5-bridge and OptiScaler PR #1116. `gh api /search/repositories -f q='dlssnr' -f sort=updated` returns **23 repos**, of which **9 were pushed on 2026-09-05 or 09-06**. The ones that change the analysis:

| Repo | Pushed | Why it matters |
|---|---|---|
| [huaxueye/DLSSNR-Reversed](https://github.com/huaxueye/DLSSNR-Reversed) | 2026-09-05 | Complete RE + **working PyTorch port**, validated at PSNR 34.5 dB against the real DLL — i.e. at the capture-chain measurement ceiling. Opens a path with no Wine, no FEX, no NVAPI, no D3D12. |
| [xXJSONDeruloXx/dlssnr-native](https://github.com/xXJSONDeruloXx/dlssnr-native) | 2026-09-05 | **Native Vulkan backend** + PTX compiler frontend, `libdlssnr-native.so`. Explicitly no HIP/ROCm/Windows binary needed. 104 kernels still blocked on memory-barrier ops. |
| [xenmods/DLSSNR-Cost-Scaler](https://github.com/xenmods/DLSSNR-Cost-Scaler) (24★) | 2026-09-05 | Runs the neural model at **reduced resolution** with a matched-residual composite, "decouples DLSS-NR's GPU cost from display resolution." |
| [Markxiao94/OptiScaler-DLSSNR-NR-before-SR](https://github.com/Markxiao94/OptiScaler-DLSSNR-NR-before-SR) | 2026-09-03 | Runs NR *before* super-resolution, i.e. at internal render resolution. |
| [ljmng7/Metal_DLSS5_Research](https://github.com/ljmng7/Metal_DLSS5_Research) | 2026-09-05 | DLSS-NR reconstruction aimed at **Apple Metal** — a non-NVIDIA **ARM64** target. Directly relevant precedent the synthesis never saw. |
| [NIGos/dlss5-bridge](https://github.com/NIGos/dlss5-bridge) (240★) | 2026-09-05 | Now at **v1.4.12, six releases in three days**, with a working **Vulkan** path (`vkmirror`; issue #23, a Vulkan render-target bug, closed 2026-09-04). |

The synthesis cites dlss5-bridge exactly once — as a **dead end**, via issue #22. Issue #22 is a D3D11 Linux/Proton fault, still open (updated 2026-09-06), on a project shipping twice a day with an active Vulkan branch. Calling that a "definitive dead end" on a three-day-old snapshot is the clearest case of dismissing a live lead too quickly.

---

## 5. Where the synthesis is overconfident

**"Playable frame rate: ~0%."** This is the least-evidenced number in the document and it is stated with more force than anything else. Its stated basis is a bandwidth ratio: *"GB10 is 48 SMs on 273 GB/s unified LPDDR5X against an RTX 5090's ~1.8 TB/s."* Problems:

1. **273 GB/s is a spec sheet number.** I measured it: a 1 GiB `float4` stream copy on this GB10, `nvcc -arch=sm_121`, gives **221.3 GB/s read+write achieved**. Use the measured number, not the spec one.
2. **The bandwidth argument doesn't obviously bind.** The model is ~147.7 MB of weights. At 221 GB/s that is a **~0.7 ms/frame floor** for weight streaming — irrelevant at any playable frame time. The real cost is FP8 tensor throughput and activation traffic through a 71-block Swin/ViT at output resolution. The synthesis reasons about bandwidth and then concludes about compute; the two are not interchangeable, and nobody measured the one that matters.
3. **The comparison GPU is wrong for the conclusion.** The cited costs are 39% of frame time on a 4090 and ~51% on a 5070 Ti — percentages of a frame, not absolute milliseconds. Scaling those to GB10 requires an absolute per-frame cost, which is in the unretrieved NVIDIA report.
4. **Cost scaling is ignored entirely.** `DLSSNR-Cost-Scaler` and the NR-before-SR forks exist precisely to decouple NR cost from output resolution. A verdict of "~0% playable" that does not consider running the model at 1/4 area at 1080p output is not a measured verdict.

The honest form is: *"unmeasured; the roofline argument is unresolved and the tools to reduce cost by 2-4x already exist."* Not "~0%."

**"Feature 18 == DLSSNR" is labelled thin; it should be upgraded.** huaxueye's RE captured the runtime block executor at `ngx+0x2ac60` and names the DLL `v310.8, Feature=18`; NapXDD issue #3's RenoDX log prints `feature=18 (DLSSNR/reserved-18)`. Three independent projects with runtime evidence is not "community consensus."

---

## 6. Two dismissals that were too fast

**Windows-on-Arm as a "definitive dead end."** The reasoning (INF binds only `2E03`/`2E06`/`2E13` SUBSYS-locked to Microsoft; Secure Boot on; no ARM64 616.64) is correct *today*. But NVIDIA's own site now carries **"Announcing NVIDIA DGX Station for Windows"** ([nvidia.com/en-us/products/workstations/dgx-station/](https://www.nvidia.com/en-us/products/workstations/dgx-station/), fetched HTTP 200) — Windows on a **GB300 Grace Blackwell** deskside Arm superchip. NVIDIA is expanding, not contracting, its ARM64 Windows driver surface for deskside Grace-Blackwell hardware. That belongs on the watch list as a Tier-2 item, not in §5 "Definitive Dead Ends." A dead end that depends on a driver INF's device list is a *current-snapshot* dead end.

**The native/non-Windows execution paths were never considered as a category.** The synthesis frames the only unsanctioned option as "Windows DLL + ReShade + Detours + NVAPI + D3D12, under FEX." Two of the four riskiest components in that chain are avoidable given what shipped this week (native Vulkan backend; PyTorch reference implementation). The synthesis's own risk list — *"Detours hooking x86-64 prologues under FEX's JIT; ReShade's `dxgi` hook under FEX"* — is an argument for looking at paths that have neither.

---

## 7. Cheap experiments runnable on this GB10 that settle open questions empirically

Ordered by (information gained) / (effort), all no-sudo unless noted, all obeying the repo's process-hygiene rules.

1. **Fetch `DLSS5_Report.pdf` in Chrome** (`https://research.nvidia.com/labs/adlr/DLSS5/files/DLSS5_Report.pdf`) — curl and WebFetch both get 403. Five minutes; it is the primary source for the compute-budget question the whole playability verdict turns on.

2. **Measure the roofline properly, no DLSS DLL required.** Already started: `221.3 GB/s` measured copy bandwidth (`/tmp/bw.cu`, `nvcc -O3 -arch=sm_121`). Add a cuBLASLt FP8 E4M3 GEMM sweep at the documented shapes (dim 32/64/128/256/512/1024, the `[out_features, in_features]` layouts windystrife documents) and you can bound the 71-block forward pass at 1080p/1440p/4K within an afternoon, with zero proprietary bytes on disk. **This converts "~0% playable" from an opinion into a number**, and it is the highest-value experiment on the list.

3. **Build the reversed topology in PyTorch with random weights and time it.** `huaxueye/DLSSNR-Reversed` ships `dlssnr/model.py` (`DLSsnrNet`) with no weights. Note **torch is not installed** on this box (`ModuleNotFoundError`); CUDA 13.0 is at `/usr/local/cuda`. Install an aarch64 CUDA torch wheel, instantiate the net, feed `(1,3,1080,1920)` linear RGB, and measure. This gives a real per-frame ms on GB10 for the actual architecture — no NVIDIA DLL, no EULA exposure, no Wine, no FEX. If this comes back at 200 ms/frame, Path A is dead on performance grounds and the repo can say so with a measurement. If it comes back at 15 ms, the whole verdict needs revisiting.

4. **Prove the CuBIN path end-to-end under FEX before spending money on a game.** Write a trivial CUDA kernel, compile to a `sm_120` cubin *and* `sm_120` PTX, and drive it through the exact production chain — a small x86-64 D3D12 test exe under Proton 11.0 calling `NvAPI_D3D12_CreateCubinComputeShaderExV2` + `LaunchCubinShader` + `GetCudaSurfaceObject` → vkd3d-proton → `VK_NVX_binary_import` → FEX thunks → ARM64 driver. Confirmed present on this box: `VK_NVX_binary_import` rev 2, `VK_NVX_image_view_handle` rev 3, `VK_NV_cuda_kernel_launch` rev 2 (`vulkaninfo`). **This is the single highest-risk unknown in Path A and it costs nothing but a weekend.** A worthwhile side observation the synthesis never made explicitly: cubins are *GPU* code, so the x86→ARM64 CPU translation is irrelevant to them — the cubin crosses the FEX boundary as opaque bytes and is JIT'd by the native ARM64 driver. That is an argument *for* the path, and it also means `NvAPI_D3D12_GetCudaSurfaceObject` (the [dxvk-nvapi #393](https://github.com/jp7677/dxvk-nvapi/issues/393) crash site) is the thing to stress first.

5. **Re-run `apt-get -s install nvidia-driver-610-open …` and paste the output into the log.** The synthesis itself says two passes disagreed about whether DKMS gets pulled. That is thirty seconds of work and it is currently an unresolved contradiction inside a document recommending the upgrade.

6. **Do the Proton ARM64 `nvapi64.dll` build.** [Proton #9439](https://github.com/ValveSoftware/Proton/issues/9439) is open, `Saancreed` posted a working ARM64EC meson cross file and said he lacks hardware, and this box is the hardware. The synthesis is right that this is the best use of the weekend, and it is the one item on the list with a guaranteed non-null outcome.

---

## 8. What I could not close

- **Reddit.** Blocked through every channel available from this machine. If the user's "posts from today" were on r/nvidia, r/linux_gaming or r/LocalLLaMA, they are still unread. **Ask the user for the actual links** — this is the cheapest possible fix and it has now survived two rounds of analysis unaddressed.
- **`DLSS5_Report.pdf`** — 403 to every automated fetch.
- **N1X compute capability** — still unestablished; if N1X is `sm_121` like this GB10, NVIDIA already builds DLSS 5 kernels for this exact compute capability.
- **Whether the RenoDX DLSS5 add-on (the thing that actually worked on Ada under Proton) has any published Linux ARM64 or GB10 report** — searched via GitHub code search, nothing; Discord (where the working configuration is actually discussed, per issue #3) not accessible.

**Bottom line on the synthesis:** the verdict — *no DLSS 5 on this box today* — survives every check I ran, and its correction of the "GB10 is pinned to 580" error is solid and valuable. But its confidence is misallocated: it is most certain (`~0% playable`) where it has the least evidence, it lists as unknowable (`sm_120` vs `sm_120a`) something that was publicly documented before it was written, it recommends the one Linux implementation with a documented failure on non-RTX-50 hardware, and its "we searched and found nothing" negatives rest on a search channel that was never actually the only one available.