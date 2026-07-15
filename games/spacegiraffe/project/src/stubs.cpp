// Space Giraffe (XBLA) -- Game-specific Xbox 360 API stubs
//
// Intentionally empty for the baseline build: the ReXGlue runtime already
// provides host implementations for every Xbox 360 import Space Giraffe uses
// (verified: 0 of 157 imports unresolved against librexruntime). Add
// REX_HOOK / REX_FUNC overrides here only when a specific guest call needs
// game-specific behavior.

#include "spacegiraffe_init.h"

#include <rex/memory.h>

// Workaround hook for the boot-time COM-style Release at 0x820F3FF0.
// ReXGlue passes an uninitialised/invalid held object (0x40001600, the GPU
// interrupt context) whose vtable slot +40 is null. On real hardware / Xenia
// the matching call either has held==0 or a valid vtable; treating a null
// method slot as "nothing to release" lets init continue.
REX_HOOK_RAW(sub_820F3FF0) {
  uint32_t obj = ctx.r3.u32;
  uint32_t held = rex::memory::load_and_swap<uint32_t>(base + obj + 4);

  if (held) {
    uint32_t method = rex::memory::load_and_swap<uint32_t>(base + held + 40);
    if (method == 0) {
      REXLOG_ERROR("[SG-WA] sub_820F3FF0: held={:08X} has null method slot; "
                   "skipping release for obj={:08X}", held, obj);
      return;
    }
  }

  // Otherwise behave exactly like the generated function.
  __imp__sub_820F3FF0(ctx, base);
}

// Diagnostic hook for sub_820D6D80: it constructs a stack object at r1+96 whose
// held pointer (offset 4) is ending up as the GPU interrupt context pointer
// (0x40001600) in ReXGlue. Log the object after the generated constructor runs
// so we can see exactly what value is being placed there and compare with
// Xenia.
REX_HOOK_RAW(sub_820D6D80) {
  uint32_t saved_r3 = ctx.r3.u32;
  uint32_t saved_r4 = ctx.r4.u32;
  uint32_t saved_r5 = ctx.r5.u32;

  __imp__sub_820D6D80(ctx, base);

  // The object is at r1+96 after the function returns. The held pointer/vtable
  // is at offset 4 (r1+100). The original function stored r4/r5 on its stack at
  // r1+2140/r1+2148 before decrementing r1, but after it returns r1 is back
  // to the caller's value and the object at r1+96 is gone. So instead log
  // using the saved r1 from before the call.
  //
  // Actually we need the stack frame *during* construction; hooking after the
  // call is too late. Use a temporary hook inside sub_820E9EB0 below instead.
  (void)saved_r3;
  (void)saved_r4;
  (void)saved_r5;
}
