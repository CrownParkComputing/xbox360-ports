# Geometry Wars: Retro Evolved (XBLA) — ReXGlue recompilation scaffold

Title ID `584107ED`, media XA-2029. Scaffolded from `daytona-xbla-recomp` (shared
ReXGlue SDK via symlink). Inner `default.xex` is only **440 KB**.

## Status

- **Compiles + links** → `project/out/build/linux-amd64/Release/geometrywars` (4.4 MB).
- Codegen was the cleanest of any title tried: **1 unresolved function**
  (`0x82075438`, added to `config/gw_rexglue.toml`), 10 generated .cpp, all 144
  imports satisfied by the runtime.
- **Boots** through XEX load, 3,376 functions, SDL input, **Vulkan swapchain**,
  shader storage — then crashes.

## The crash is SYSTEMIC, not per-game

Geometry Wars and Space Giraffe — two unrelated titles — crash with the
**identical signature**, in the **same shared Xbox D3D/XDK init code**:

```
SetInterruptCallback(<cb>, <ctx>)
[FATAL] Call to invalid or unregistered function at guest address 0x00000000
```

Both are a COM-style `Release` doing `held = *(obj+4); if (held) held->vtbl[+40]()`
where `obj+4` holds garbage instead of 0. Backtraces sit entirely in the shared
graphics-init code (GW: `0x8204xxxx`/`0x820Cxxxx`).

Diagnosed values of `obj+4` (should be 0 or a valid object):
- SG: `0x40001600` (a heap addr pointing at uninitialized `0xFF` memory)
- GW: `0xBEBEBEBE` — the **thread-stack poison fill** (`xthread.cpp:298`,
  `Fill(stack, 0xBE)`). i.e. an uninitialized stack field read as non-zero.

### Tested fix (DISPROVED): zero-fill stacks

Changed `xthread.cpp` stack fill `0xBE -> 0x00` and re-ran GW. The poison went
away but the crash remained — `obj+4` then read `0x18280086`, a *computed* wrong
value (below image base, not a fill pattern). So `obj+4` is being actively
written with a bad value by recompiled guest code: a **recompilation-correctness
/ runtime-state-divergence bug**, not merely uninitialized memory. Reverted the
change (Daytona was tuned against `0xBE` stacks).

## Conclusion

This ReXGlue build is effectively a **Daytona-specific port**. Daytona is the
only title that reaches gameplay, and only via heavy bespoke work (841-line
game-specific `stubs.cpp`, a 7,935-line codegen patch, GPU-workaround cvars, and
custom hooks like the `WAITPROBE`/symbol instrumentation visible in its logs).
The *shared* D3D device-init path is not robustly supported, so every untouched
title hits the same wall right after `VdSetGraphicsInterruptCallback`.

Bringing up Geometry Wars (or any new title) to gameplay therefore means solving
this shared-code crash — real RE on the recompiled D3D-init path — which would
benefit all titles at once but is not a quick win.

## Build / run

```sh
cmake --preset linux-amd64 -S project
cmake --build project/out/build/linux-amd64 --config Release --target geometrywars
# boots to the documented crash:
env DISPLAY=:1 GDK_BACKEND=x11 \
  LD_LIBRARY_PATH="$PWD/thirdparty/rexglue-sdk/out/linux-amd64/Release" \
  ./project/out/build/linux-amd64/Release/geometrywars --game_data_root="$PWD/extracted"
```

## BREAKTHROUGH: divergence confirmed via Xenia ground truth

Built a store-watch toolchain (instrumented `REX_STORE_U*` in `generated/geometrywars_init.h`,
gated by env `REX_WATCH_ADDR`, dladdr-resolved) and traced the crash:

- Crash = Release `sub_820639E0` reads uninitialized `obj+4`.
- `obj+4` is never written (proven by all-width store watch) because its constructor
  `sub_82059648` (which does `stw r30,4(r31)` to zero it) is **skipped**.
- Skipped because `sub_82047398` bails to its error path when its arg `r5 == 0`
  (`cmplwi r5,0; beq` at guest `0x820473B8`).
- `r5` is threaded *down* the call chain (all confirmed via backtrace addresses):
  `sub_820449C8`(r30) → `sub_82048ED0`(r5) → `sub_82047398`(r5).

### Xenia comparison (the decisive step)

Ran `xenia_canary` under gdb with `break_on_instruction = 0x82047398`. Xenia x64
backend keeps the PPC context in `rsi`; GPRs at `+0x20` (`r5` = `[rsi+0x48]`).
At the trap:

```
Xenia:    r3=0x20000000  r4=0x7018f2f0  r5=0x40007270   (valid heap pointer)
ReXGlue:  r5 = 0                                          (null)
```

**Root cause class:** `r5` should be a `0x40000000`-region heap pointer but is null
in ReXGlue — i.e. an allocation/computation that yields a valid pointer in Xenia
returns null here, then threads down into the constructor guard. NOT an HLE bug
(kernel functions are byte-identical to Xenia), NOT graphics/Vulkan. It is a
recompiler correctness bug.

### Resumable next step

Binary-search the origin: move `break_on_instruction` up the chain
(`0x820449C8`, then its caller at bt saved_lr `0x82045274`, etc.), reading `r5`/the
pointer at each in Xenia, and instrument the matching ReXGlue frame, until the
frame where Xenia has the pointer and ReXGlue has 0 — that frame's translated
code (vs Xenia's `ppc_emit_*` semantics) contains the bug. Likely an allocation
in the `0x40000000` title heap.

## CORRECTION + verified findings (2nd pass)

Important methodology note: edits to generated `.cpp` files only take effect if the
build is verified (`grep error:` AND confirm the probe string via `strings` on the
binary). Several earlier `.cpp` probes silently failed to compile and ran stale
binaries — those "0 calls" results were invalid. The header `[WATCH]` macro also
had a `do{}while` -inside-comma bug (all-width version never compiled; only the
U32 watch ran). All findings below are from probes verified present in the binary.

### Verified causal chain (ReXGlue)

- Crash: `[REL] sub_820639E0 lr=82047668 obj=7018EE10 held=*(obj+4)=BEBEBEBE`
  (Release reads poison `obj+4`; real caller is `sub_82047398` — backtrace was
  correct after all).
- `[R5] sub_82047398 entry r3=7018F3A0 r4=40007270 r5=00001012` — r4,r5 both
  nonzero, so the construction block IS entered; the constructor is skipped by the
  inner guard.
- `[GUARD] sub_82099830 *(0x82107BA8)=00000000` → guard returns nonzero → constructor
  `sub_82059648` (which zeroes `obj+4`) is skipped → poison → crash.

### Xenia comparison (gdb, context in rsi, r[N] at rsi+0x20+8N)

- At `sub_82099830` (0x82099838): Xenia ALSO has `*(0x82107BA8)=0`. So the guard /
  constructor-skip is **identical in both** — NOT the divergence.
- At `sub_82047398` entry, args DIFFER:
  - Xenia:   r3=0x20000000        r4=0x7018f2f0(stack)  r5=0x40007270(heap)
  - ReXGlue: r3=0x7018F3A0(stack) r4=0x40007270(heap)   r5=0x1012(size)
  The heap pointer 0x40007270 is in both but one register apart; Xenia's r3 isn't a
  stack addr, so Xenia's *first* call to `sub_82047398` has a different caller than
  ReXGlue's crashing call (from `sub_82048ED0`, which sets r3=r1+160).

### Current conclusion

The divergence is in the **arguments passed to `sub_82047398`** (argument
computation/marshaling upstream), NOT the constructor guard. To pin it, the
remaining work is to match the *corresponding* Xenia call (use Xenia
`break_condition_gpr`/`break_condition_value` to break `sub_82047398` when
r4==0x40007270, or break at `sub_82048ED0`/`sub_820449C8` and compare first-call
args) and walk up until inputs match but the passed-down args differ — that frame's
translated code vs Xenia's `ppc_emit_*` is the bug. Methodology (verified probe +
Xenia gdb break reading rsi+0x20+8N) is proven and resumable.
