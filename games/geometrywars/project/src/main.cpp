// Geometry Wars: Retro Evolved (XBLA) - ReXGlue Static Recompilation
// Title ID: 584107ED
#include "geometrywars_init.h"
#include "keyboard_driver.h"
#include <rex/rex_app.h>
#include <rex/input/input_system.h>
#include <rex/system/xthread.h>
#include <memory>

class GeometryWarsApp : public rex::ReXApp {
public:
    using rex::ReXApp::ReXApp;
    static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
        return std::unique_ptr<GeometryWarsApp>(
            new GeometryWarsApp(ctx, "geometrywars", PPCImageConfig));
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
REX_DEFINE_APP(geometrywars, GeometryWarsApp::Create)
