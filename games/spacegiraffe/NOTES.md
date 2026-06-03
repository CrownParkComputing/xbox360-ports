# Space Giraffe (XBLA) — ReXGlue recompilation scaffold

Title ID `5841080C`, media XA-2060. Scaffolded from the `daytona-xbla-recomp`
template, reusing the same (symlinked) ReXGlue SDK build.

## Status

- **Compiles + links** → `project/out/build/linux-amd64/Release/spacegiraffe` (14 MB).
- **Boots** through: XEX load, 7,409 recompiled functions registered, SDL input,
  XAudio render driver, **Vulkan swapchain created (1266×683)**, shader storage init.
- **Current failure:** a worker thread calls through a null function pointer
  (`[FATAL] Call to invalid or unregistered function at guest address 0x00000000`)
  while the audio worker thread runs normally. This is a runtime init issue, not a
  missing recompiled function — declaring addresses won't fix it.

## How it was built

1. Extracted inner `default.xex` from the STFS package with
   `daytona-xbla-recomp/scripts/extract_game.py` → `assets/`, `extracted/`.
2. Minimal manifest `config/sg_manifest.toml` + analysis config `config/sg_rexglue.toml`.
3. Codegen produced `generated/` (26 .cpp, ~1.7M LOC). Re-run with:
   `cd config && rexglue --force codegen sg_manifest.toml`
   (it segfaults *after* printing `Done` — harmless, files are valid).
4. `[functions]` in `sg_rexglue.toml` holds the 5 function boundaries the static
   analyzer missed (4 found at analysis time + `0x8210FFD8` found at runtime).
5. Host shell: `project/src/main.cpp` (app registration + keyboard driver) and an
   empty `project/src/stubs.cpp` — the runtime already provides all 157 imports.

## Build / run

```sh
cmake --preset linux-amd64 -S project
cmake --build project/out/build/linux-amd64 --config Release --target spacegiraffe
./run.sh
```

## Root cause of the current crash (diagnosed)

Used a guest-stack backtrace (see `patches/sg_invalid_function_backtrace.patch`,
temporarily applied to the runtime's `InvalidFunctionTrap`) to locate the fault:

- **Faulting instruction:** `bctrl` at guest `0x820F4018`, inside `sub_820F3FF0`.
- **`sub_820F3FF0` is a COM-style `Release`:**
  ```
  r31 = obj
  r11 = *(obj + 4)          // held interface pointer
  if (r11 == 0) goto done   // null-check PASSES → r11 is non-null
  r11 = *(r11 + 40)         // vtable slot +40 (the release/destroy method)  ← == 0
  ctr = r11; bctrl          // call through null → FATAL
  done: *(obj + 4) = 0
  ```
- The held object's **vtable release slot at +40 is null**. The guest does NOT
  null-check that slot — on real hardware it is always populated — so this is a
  genuine recomp-correctness bug, not a missing host import.
- **Call chain (leaf→root):** `sub_820F3FF0` ← `sub_820D6D80` (via `sub_820E9FD0`,
  a stack-object destructor) ← `sub_820D88D8` ← `sub_820D43C0` ← `sub_820D4BF0`
  ← `sub_820D4C78` ← `sub_820AE4D8` ← `sub_820B2F40` (thread entry). It fires
  during object-array construction/teardown early in boot, on a worker thread,
  while the audio worker runs normally.

### Update: XMP hypothesis tested and DISPROVED

`XMPCaptureOutput` (XMP msg 0x0007003D) is unimplemented in the runtime and
returns `X_E_FAIL`. Space Giraffe is music-reactive and calls it during init, so
this looked like the trigger. Patched it to return `X_E_SUCCESS` with a zeroed
buffer (see `patches/sg_xmp_capture_output_success.patch`), rebuilt, re-ran:
**the crash is byte-for-byte identical.** So the XMP failure is NOT the cause.
(The XMP fix is still a legitimate improvement and is kept as a reference patch;
it was reverted from the shared SDK to keep the Daytona build pristine.)

Also ruled out: the GPU interrupt callback `SetInterruptCallback(0x820C2008,
0x40001600)` is registered but never fired, yet the whole crash sequence is
synchronous on one thread in ~28 ms — so the game is not blocked waiting on an
interrupt either.

Remaining concrete lead: `obj+4` holds `0x40001600` (the GPU interrupt context),
whose memory has a valid-looking tail (floats at +48) but an invalid vtable
region (`+0 == 0xFFFFFFFF`) and a null method pointer at `+40`. Either the stack
field `obj+4` should be 0 here (and the recomp left stale data), or the object at
`0x40001600` should have had `+40` populated by an init step that didn't run.
Next step would be to instrument the *write* to `obj+4` (or to `0x40001628`) to
find which routine sets the bad value — several more build/run iterations.

### Verdict: not a one-line fix

This is the "boot → gameplay" RE work, not a missing stub. Next steps, in order:
1. Re-apply the backtrace patch and also dump the object: `obj=r3`,
   `held=*(obj+4)`, and the 64 bytes of the vtable at `held` — to see whether
   `held` points into the guest image (.data vtable) or into garbage.
2. If the vtable is real but +40 is 0 → find the init routine that should fill
   that slot (likely a `__imp__` whose generic stub returns 0 / a no-op where the
   title needs real behavior, or a guest registrar that didn't run).
3. If `held` is garbage → the object was mis-constructed earlier; bisect back up
   the chain (`sub_820D43C0` / `sub_820AE4D8`) for the mistranslation or bad
   import return value.

Daytona needed an 841-line game-specific `stubs.cpp` plus a 7,935-line codegen
patch for this class of issue. Space Giraffe's analysis was far cleaner (5
function-boundary entries, 0 codegen patches so far), so its glue layer should be
much smaller — but reaching gameplay is still days of iterative RE, not hours.
