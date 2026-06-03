// Space Giraffe (XBLA) - ReXGlue Static Recompilation
// Title ID: 5841080C
//
// Minimal host shell: registers the recompiled image with the ReXGlue runtime
// and wires up the keyboard input driver. Game-specific tuning (cvars, hooks,
// overlays) can be layered on later — this is the compile/link/boot baseline.

#include "spacegiraffe_init.h"
#include "keyboard_driver.h"

#include <rex/rex_app.h>
#include <rex/input/input_system.h>
#include <rex/system/xthread.h>

#include <memory>

class SpaceGiraffeApp : public rex::ReXApp {
public:
    using rex::ReXApp::ReXApp;

    static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
        return std::unique_ptr<SpaceGiraffeApp>(
            new SpaceGiraffeApp(ctx, "spacegiraffe", PPCImageConfig));
    }

protected:
    void OnPostSetup() override {
        if (!window() || !runtime() || !runtime()->input_system()) return;
        auto* input_sys = static_cast<rex::input::InputSystem*>(runtime()->input_system());
        auto kbd = std::make_unique<KeyboardInputDriver>(window());
        kbd->Setup();
        input_sys->AddDriver(std::move(kbd));
    }
};

REX_DEFINE_APP(spacegiraffe, SpaceGiraffeApp::Create)
