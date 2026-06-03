// Jetpac Refuelled (XBLA) -- game-specific stubs
// XUsbcam* (Xbox camera/vision) APIs are not provided by the runtime. Jetpac
// references them but the camera feature is optional; stub them to no-op/fail.
#include "jetpac_init.h"
#include <rex/ppc/context.h>

#define JP_STUB_RETURN(name, val) extern "C" REX_FUNC(name) { (void)base; ctx.r3.u64 = (val); }
#define JP_STUB(name) JP_STUB_RETURN(name, 0)

JP_STUB_RETURN(__imp__XUsbcamCreate, 0x80004005)        // E_FAIL: no camera
JP_STUB(__imp__XUsbcamDestroy)
JP_STUB_RETURN(__imp__XUsbcamGetState, 0)               // state 0 = not present
JP_STUB_RETURN(__imp__XUsbcamReadFrame, 0x80004005)
JP_STUB(__imp__XUsbcamSetCaptureMode)
JP_STUB(__imp__XUsbcamSetConfig)
JP_STUB(__imp__XUsbcamSetView)
