# Per-title status — 2026-07-13 (official rexglue-sdk `development` + local fixes)

Sorted game packages live in `/home/jon/XBLA/{1-PLAYABLE,2-NEEDS-FIXES,3-NOT-WORKING}/`.
Launch any built port with `./play.sh <game>` (full license, no sign-in modals, dev overlays off,
plus any per-game workaround flags — see `play.sh`).

## 1-PLAYABLE (user-verified)

| Game | Verdict |
|------|---------|
| SoulCalibur | plays; setjmp/longjmp fix. NOTE: after the "LOADING" art screen it waits for a **fire (A) press** to reach the menu — auto-advanced in play.sh by pulsing A (per-game keyboard driver is Win32-only, INERT on Linux → needs a gamepad). |
| SoulCalibur II HD | plays (SPIR-V resync + load-shader pitch). OPEN: in-fight **backgrounds render as scrambled black/white blocks** — a texture-format/pitch decode corruption (not the loop logic); needs a targeted fix. |
| Bubble Bobble Neo | works — setjmp/longjmp fix |
| Space Giraffe | works — same fix + thunk-cluster batch |
| Hydro Thunder Hurricane | works fine; white/untextured surfaces fixed by the exp_adjust fix |
| OutRun | plays well; gear-change SFX "crackle" — RUNTIME-TRACED 2026-07-18: NOT a loop (0 loop contexts), a decode-level PCM artifact; deprioritized (cosmetic). |
| Choplifter HD | plays; colours correct **only via `--render_target_path_vulkan=fsi`**, which `play.sh` now passes automatically. See "Host render-target path" below. |

## 2-NEEDS-FIXES (runs, impaired)

| Game | Problem | Diagnosis |
|------|---------|-----------|
| Bionic Commando Rearmed 1 | **renders, but frozen** — the picture appears and never advances | Crash is GONE: codegen is clean (0 unresolved calls) and it presents ~2400 frames with **zero fatals**, 116 fns in toml. The guest is ALIVE (timers fire, APCs deliver) but its logic never advances; every presented frame is byte-identical. Fixed along the way: `cache:` was unmounted so its `cache:\` opens failed (now mounted — real bug, but NOT the freeze). Prime suspect: **`XamTaskCloseHandle` is a stub** — XamTask is the async-task API; if a scheduled task never signals completion the title blocks forever on a loading screen. Compare `src/kernel/xam/` against xenia's `xam_task.cc` (xenia implements `XamTaskSchedule`/`XamTaskCloseHandle`). Also seen: `BroadcastNotification -> 0 listeners`. Next: run the same xex under xenia (oracle) to confirm it gets further. |
| Jetpac Refuelled | title art + in-game sprites invisible (geometry draws, nothing shown) | NOT the exp_adjust bug and NOT fixed by `fsi` (which makes it fully black). Localized: the invisible content is drawn by ONE pixel shader (`PS FE2EB03A937B160F`, `tfetch3D` + `mul oC0, r0, r1`) whose fetch constant says `k2DOrStacked` — the 3D-or-stacked ambiguous path. Ruled out: alpha/blend (the *opaque* draw is invisible too), DXT2_3 handling, geometry shaders, EDRAM path, guest-side art decode (the DXT1 data at `0x1DA1C000` is real). Next: force the fetch result to (1,1,1,1) in `spirv_translator_fetch.cpp` — if solid quads appear, it's the texture sample (array-layer index for a stacked texture); if not, it's the geometry. |

## CROSS-GAME open issue: dual-monitor swapchain thrash

On a multi-monitor X display the Vulkan presenter sizes the swapchain to the
**full virtual desktop** (e.g. 5120x1440 = 2x 2560x1440) and thrashes recreating
it at odd sizes (5096x1380, 1261x1380). Suspected behind SC1's rough loading,
SC2 background corruption, and PGR3 window weirdness. `--monitor=1` did NOT
constrain it in testing. Prime shared fix — next PGR3-adjacent target.

## Downloads

Per-game build packs (config + scaffold + build_and_play.sh, NO game code) are
published as GitHub releases (`game-packs-v1`). `tools/make_gamepack.sh <game>`
regenerates them; every per-game fix flag is auto-baked from play.sh.

## 3-NOT-WORKING

| Game | Problem |
|------|---------|
| Daytona | **RUNS** (was mis-filed "never presents a frame"). Root cause: our `main.cpp` deleted the two Vulkan readback cvars the working sibling (Subarasheese/daytona-xbla-recomp) bakes in, and play.sh never restored them. With `--vulkan_readback_memexport=true --vulkan_readback_resolve=true` it renders textured menus (verified 1920x1080 save-content screen) and runs interactively. Now in play.sh's `daytona)` case. REMAINING: substantial flickering (async-placeholder frame-skip suspected — `--vulkan_async_skip_incomplete_frames=false` applied, needs eval); intermittent headless `vkQueueSubmit` device-lost still seen in dump runs (submit-path, not render-path). The dead 690-hunk codegen patch is a separate cleanup, NOT the present-blocker. |
| Geometry Wars | REVIVED — same readback-cvar fix as Daytona renders its neon title menu (verified 1280x720). In play.sh geometrywars) case. Remaining: horizontal green-band overlay artifact (RT/overlay), and interactive playability unverified. |
| Trials HD | black screen; XUI menu files never load from .pak archives |
| Rainbow Islands | grind incomplete (setjmp fix applied, more boundaries to clear) |
| Bionic Commando Rearmed 2 | built, but **zero** functions in its toml and never run — from-scratch bring-up. Try the improved `bringup.sh` first (see below). |
| SoulCalibur 4 (retail disc, 2026-07-18) | bring-up COMPLETE and codegen-clean (30,056 fns, discovery converged, 0 FATALs, setjmp 0x825E2610/longjmp 0x825E22F0) — but the title stalls after 1 black present on a guest render-ring `NtSignalAndWaitForSingleObjectEx` rendezvous **that upstream xenia fails identically** (compat #1128, "cyan screen"). We are AT xenia parity; further progress = guest RE of the awaited event (main in sub_823A4A70/sub_825468E0). Full report in `games/soulcalibur4/logs/`. |

---

## SDK bugs fixed 2026-07-13

**Texture `exp_adjust` read from the wrong fetch-constant word** — the single root cause of the
white/untextured surfaces across ALL ports (Choplifter's white sprites, Hydro Thunder's white
barrels). The SPIR-V translator applied the result exponent bias from fetch-constant **word 4**;
`exp_adjust` lives in **word 3** (`xenos.h:1239`). Word 4 bits 13:18 fall inside `lod_bias`, so every
texel was multiplied by `2^(lod_bias bits)`: bias 0 → x1 (correct by accident — why most surfaces
always looked fine), positive → x16/x65536 → saturates to flat WHITE, negative → crushed to black.
The tree's own DXBC translator already read word 3 correctly; the bug was SPIR-V-only.
Matches upstream xenia `32889f51b`. The textures were always bound, loaded and decoded correctly —
the damage happened *after* sampling, which is why every texture-cache diagnostic came back clean.

**10:10:10:2 render targets stored at 8 bits/channel** — `GetColorVulkanFormat` returned
`VK_FORMAT_A8B8G8R8_UNORM_PACK32` instead of `A2B10G10R10_UNORM_PACK32`, silently truncating two bits
of colour precision. (Does not affect Choplifter, which uses the 7e3 float variant.)

Plus: SPIR-V shader blob resync + load-shader pitch contract (SC2 corruption), codegen shared-epilogue
tail calls, XUsbcam build, dev-overlay cvar, resolve no-op, socket recv timeout.

## Host render-target path — OPEN BUG

The Vulkan **host render-target (FBO)** path blows every lit/HDR surface out toward RED.
`--render_target_path_vulkan=fsi` (pixel shader interlock) renders correctly.

Measured on Choplifter's title screen (frames before the 3D scene are byte-identical, so this is
deterministic):

| path | mean R | mean G | mean B | R−G |
|---|---|---|---|---|
| host RT / FBO (default) | 75.7 | 64.6 | 79.7 | **+11.1** (red excess — WRONG) |
| fsi | 58.0 | 66.2 | 81.7 | **−8.2** (CORRECT) |

Both rexglue AND xenia default to `kHostRenderTargets`, and **xenia renders this game correctly on the
same GPU with that same default** — so the fork's FBO path is genuinely broken, not merely
mis-defaulted. Choplifter's RTs are `k_8_8_8_8` + `k_2_10_10_10_FLOAT` (7e3 HDR, host
`R16G16B16A16_SFLOAT`), resolving the HDR RT to a `k_16_16_16_16_FLOAT` texture with
`color_exp_bias = -3`. Suspects: the 7e3/float10 clamp in the shader RB output path, the
transfer/dump shaders, `color_exp_bias` application, or fork-only `direct_host_resolve` (default on).

### 2026-07-17 audit: the RB encode itself is CLEAN — suspects are fork-only FBO features

A full token-level diff of the RB output path against xenia found the 7e3 pack/unpack, exp-bias
compute+apply, fixed-16 −5 gate, and the whole blend translation **semantically identical** — stop
re-auditing those. The divergences are all fork-only behaviors that exist ONLY on the host-RT path
(exactly why FSI is clean), ranked:

1. **`gamma_render_target_as_unorm16` (cvar default TRUE)** — fork blends gamma RTs in LINEAR on
   `R16G16B16A16_UNORM`; xenia hard-disables this (`vulkan_render_target_cache.cc:530`) and blends
   in GAMMA space on `R8G8B8A8`. Every blended pixel into a `k_8_8_8_8_GAMMA` RT differs. Prime
   suspect for the red shift. A/B: `--gamma_render_target_as_unorm16=false`.
2. Fork implements alpha-to-mask (+ `gl_SampleMask` written by every RT0 shader); xenia-Vulkan has
   a TODO and never applies it. (PGR3 glass confetti: `--alpha_to_mask=false` did NOT fix, so a2m
   alone isn't that bug — but the always-written sample mask is still fork-only.)
3. Async placeholder pipelines: on pipeline-creation FAILURE the `discard`-FS placeholder is kept
   forever (`pipeline_cache.cpp:3565`) — a permanently-missing material renders as stale dst.
4. Dynamic rendering (fork-only, default on): ownership-transfer pipeline format omits
   `key.msaa_samples` (`render_target_cache.cpp:4714`) — latent mismatch on 2xMSAA transfers.

PGR3 datapoint: car-glass "disco confetti" is FBO-only (FSI renders glass clean, user-verified);
scene RT is `k_2_10_10_10_FLOAT_AS_16_16_16_16` (host RGBA16F, 2xMSAA). Forensic RenderDoc capture:
`pgr3race_frame126545.rdc` (glass draw eid 9707). NOTE: xenia-Vulkan was never actually verified to
render PGR3 glass correctly — "identical to xenia" and "still broken" can both be true; FSI is the
only known-good reference for this class.

### Bisect results (Choplifter title-screen mean R−G; broken=+11.1, FSI-correct=−8.2)

ALL four cvar-gated candidates are EXONERATED — each still measures +11.0:
`--gamma_render_target_as_unorm16=false`, `--vulkan_dynamic_rendering=false`,
`--direct_host_resolve=false`, and (on PGR3 glass) `--alpha_to_mask=false`. The divergence is in
code no cvar bypasses. Next session: capture-forensics through the FBO display chain with the
PGR3-proven method — RenderDoc auto-capture (REX_RENDERDOC_CAPTURE_DRAWS/SIZE), pixel-history the
same pixel on FBO vs FSI runs, and walk resolve→frontbuffer→present numerically to find where the
values fork. The presenter/swap gamma pipeline was OUTSIDE the 2026-07-17 RB audit's scope and is
now the top unaudited suspect.

## `bringup.sh` now harvests codegen's unresolved branch targets

The grind loop only ever scraped addresses from the **runtime** FATAL. But codegen separately
reports unresolved `b` (tail-call) branches — *"target not in any function"* — and continues anyway
because of `--force`. Those targets never surface as a runtime crash, so the loop would grind the
same chain forever, adding one address per rebuild and never converging. That is what had Bionic 1
stuck.

Registering those targets as function entries cleared codegen (6 unresolved → 0), and the game went
from dying at 14 frames to presenting ~2400 with zero fatals. `tools/bringup.sh` now feeds
codegen's own unresolved targets back into the toml and re-runs codegen until it reports none.
**Rainbow Islands and Bionic 2 are both "grind incomplete" — try them again with this.**

## Debugging technique that cracked these (reuse it)

1. **Xenia is the oracle.** A prebuilt Linux xenia-canary is in the AUR cache:
   `/home/jon/.cache/yay/xenia-canary-bin/xenia_canary_linux-*.tar.xz`. Run the SAME xex:
   `xenia_canary games/<g>/extracted/default.xex --license_mask=1`. If xenia renders it right and we
   don't, the bug is ours and it is findable.
2. **Dump our own frames** instead of asking a human to look. Temp hook in
   `src/graphics/vulkan/command_processor.cpp` (the swap function, where `presenter` is in scope)
   calls `presenter->CaptureGuestOutput()` and writes a PPM: `REX_DUMP_FRAME=<prefix>
   REX_DUMP_FRAME_EVERY=<n>`. ~5–13 fps headless; Choplifter's title screen lands ~frame 1080.
3. **Bisect numerically** — `mean(R) − mean(G)` on the dumped frame is a hard pass/fail signal.
4. Screen-grabbing the xenia *window* does NOT work (Xwayland returns black; Hyprland screencopy
   crashes the compositor). Capture from inside the plugin instead.

## The big fix (2026-07-12): guest setjmp/longjmp
The "spin bug" that blocked BB/SC/GW/SG for weeks: the XDK image decoder longjmps out of its
JPEG-probe error path; recompiled longjmp restored registers but host control flow fell through,
corrupting the guest stack. Fix = two lines per game in `<prefix>_rexglue.toml`:
`setjmp_address` / `longjmp_address` (find by body signature: setjmp = `mfcr`+`stfd f14,0(r3)`;
longjmp = early `lwz r0,312(r3)`). Codegen then redirects them to host setjmp/longjmp.
