# Per-title status (as of last full test pass)

Tested against ReXGlue SDK `daytonaxbla` @ `82a88a3`.

All five titles **compile and link** and **boot through** XEX load, the Vulkan
swapchain, audio, and shader-storage init. They diverge at / after the graphics
device-init handshake (`VdSetGraphicsInterruptCallback`):

| Game | Title ID | xex | Extra work needed | Result |
|------|----------|-----|-------------------|--------|
| **Daytona** | 58410B1D | large | full bespoke port (841-line stubs, 7935-line codegen patch, GPU cvars) | **Plays**, with Vulkan texture flicker |
| **Geometry Wars** | 584107ED | 0.44 MB | 1 function boundary | **Crash** `call 0x00000000` |
| **Space Giraffe** | 5841080C | 1.6 MB | 5 function boundaries | **Crash** `call 0x00000000` |
| **Jetpac Refuelled** | 584107FB | 1.5 MB | 7 XUsbcam stubs + 8 thunks + 3 boundaries | **Boots + renders a frame**, then stalls |
| **OutRun** | 58410968 | 2.3 MB | none (clean) | **Boots**, hangs during shader-pipeline creation |

## Root-cause findings (so a future ReXGlue version can be judged against them)

- **Not graphics-API related.** The renderer is Xenia's Vulkan backend, byte-for-byte.
  OpenGL is not an option and would not help; the GW/SG crash is CPU-side, pre-render.
- **Not the HLE/kernel layer.** ReXGlue's `xboxkrnl_*`, `graphics_system`, interrupt
  dispatch, and even the `0xBE` stack-poison are byte-identical to (working) Xenia.
- **The GW/SG crash is a recompiler (codegen) correctness bug** — the one component
  ReXGlue wrote itself (no Xenia equivalent). Traced with Xenia gdb as ground truth to
  an argument divergence into `sub_82047398`: a heap pointer that Xenia produces ends
  up null / in the wrong register in ReXGlue, cascading into an uninitialised object
  whose virtual `Release` calls through a null vtable slot. Full trace in
  `games/geometrywars/NOTES.md` and `games/spacegiraffe/NOTES.md`.
- **Jetpac** needs only missing-function declarations + camera stubs; it reaches
  rendering. The post-frame stall is the next thing to investigate.
- **OutRun** hangs in shader/pipeline setup — likely async-shader or a guest thread
  spin; no crash.

## What "fixed" would look like on a new ReXGlue release

Run `./retest.sh`. Signs of progress:
- GW/SG move off `CRASH-NULL-CALL` → the recompiler arg bug was fixed.
- Jetpac/OutRun reach `RENDERS (N frames)` with N growing → real gameplay.
- Daytona flicker is a separate renderer issue; judged by eye, not the harness.
