/*
 * Drives the real SDL gamepad -> PS2 pad -> game input conversion pipeline.
 * Build with tools/tests/controller/CMakeLists.txt and a local SDL3 checkout.
 * UIKit is absent; normalized touch positions use the native view's portable
 * response/layout helpers before entering the real game input pipeline.
 */
#include "core/input.h"
#include "main.h"
#include "platform/app/ios/ios_options.h"
#include "platform/input/ios/ios_touch.h"
#include "platform/input/ios/ios_touch_state.h"
#include "platform/input/sdl/sdl_pad.h"
#include "sf33rd/AcrSDK/common/mlPAD.h"
#include "sf33rd/AcrSDK/common/pad.h"
#include "sf33rd/Source/Game/io/ioconv.h"
#include "sf33rd/Source/Game/system/work_sys.h"

#include <SDL3/SDL.h>
#include <assert.h>
#include <stdio.h>

MPP mpp_w;

// No UIKit view exists in a host test. Contacts use the same portable response,
// layout and button helpers as the native view; the controller path is real SDL.
static Input_ButtonState touch_state;
void IOSTouch_GetButtonState(Input_ButtonState* state) {
    if (IOSOptions_Get()->touch_enabled) *state = touch_state;
    else SDL_zerop(state);
}

static SDL_Joystick* virtual_pad;

static void set_sticks(Sint16 left_x, Sint16 left_y, Sint16 right_x, Sint16 right_y) {
    assert(SDL_SetJoystickVirtualAxis(virtual_pad, SDL_GAMEPAD_AXIS_LEFTX, left_x));
    assert(SDL_SetJoystickVirtualAxis(virtual_pad, SDL_GAMEPAD_AXIS_LEFTY, left_y));
    assert(SDL_SetJoystickVirtualAxis(virtual_pad, SDL_GAMEPAD_AXIS_RIGHTX, right_x));
    assert(SDL_SetJoystickVirtualAxis(virtual_pad, SDL_GAMEPAD_AXIS_RIGHTY, right_y));
    SDL_UpdateJoysticks();
}

static void expect_game_directions(u16 expected) {
    flPADGetALL();
    keyConvert();
    const u16 actual = p1sw_buff & SWK_DIRECTIONS;
    if (actual != expected) {
        fprintf(stderr, "Expected game directions 0x%X, received 0x%X\n", expected, actual);
    }
    assert(actual == expected);
}

static void sensitivity(int value, int deadzone) {
    IOSOptions options = IOSOptions_Defaults();
    options.touch_enabled = false;
    options.stick_sensitivity = value;
    options.stick_deadzone = deadzone;
    IOSOptions_Apply(options);
}

static void set_touch_stick(IOSLayout_DirectionStyle style, float x, float y) {
    if (style != IOS_LAYOUT_DPAD) IOSOptions_AdjustTouchStick(&x, &y);
    touch_state = IOSTouchState_Buttons(IOSLayout_Directions(style, x, y));
}

static void test_touch_stick_sensitivity(void) {
    set_sticks(0, 0, 0, 0);
    const IOSLayout_DirectionStyle styles[] = { IOS_LAYOUT_STICK, IOS_LAYOUT_HYBRID };
    for (size_t i = 0; i < SDL_arraysize(styles); ++i) {
        const int values[] = { 1, 50, 100 };
        for (size_t j = 0; j < SDL_arraysize(values); ++j) {
            sensitivity(values[j], 0);
            IOSOptions options = *IOSOptions_Get();
            options.touch_enabled = true;
            IOSOptions_Apply(options);
            // Identical finger position must change actual game movement bits.
            set_touch_stick(styles[i], 0.2f, 0.0f);
            expect_game_directions(values[j] == 100 ? SWK_RIGHT : 0);
        }
        set_touch_stick(styles[i], 0.2f, -0.2f);
        expect_game_directions(SWK_UP | SWK_RIGHT);

        IOSOptions options = *IOSOptions_Get();
        options.stick_deadzone = 35;
        IOSOptions_Apply(options);
        set_touch_stick(styles[i], 0.2f, -0.2f);
        expect_game_directions(0);
    }

    // The fixed touch D-pad, like physical D-pad buttons, ignores stick tuning.
    for (int value = 1; value <= 100; value += 99) {
        sensitivity(value, 35);
        IOSOptions options = *IOSOptions_Get();
        options.touch_enabled = true;
        IOSOptions_Apply(options);
        set_touch_stick(IOS_LAYOUT_DPAD, 0.5f, -0.5f);
        expect_game_directions(SWK_UP | SWK_RIGHT);
    }
    SDL_zero(touch_state);
    expect_game_directions(0);
}

static void test_physical_preview_and_analog_modes(void) {
    for (int legacy_analog = 0; legacy_analog <= 1; ++legacy_analog) {
        mpp_w.useAnalogStickData = legacy_analog != 0;
        sensitivity(1, 0);
        set_sticks(14000, 0, 0, 0);
        SDLPad_StickPreview preview;
        assert(SDLPad_GetStickPreview(0, &preview));
        assert(preview.name != NULL && preview.has_left_stick && preview.has_right_stick);
        assert(preview.raw.left_stick_x == 14000 && !preview.raw.dpad_right);
        assert(!preview.tuned.dpad_right);
        expect_game_directions(0);

        // The options preview and actual game use the same tuned hardware state.
        sensitivity(100, 0);
        assert(SDLPad_GetStickPreview(0, &preview));
        assert(preview.raw.left_stick_x == 14000 && preview.tuned.dpad_right);
        expect_game_directions(SWK_RIGHT);
        set_sticks(-14000, -14000, 0, 0);
        assert(SDLPad_GetStickPreview(0, &preview));
        assert(preview.tuned.dpad_left && preview.tuned.dpad_up);
        expect_game_directions(SWK_LEFT | SWK_UP);

        set_sticks(0, 0, 0, 0);
        expect_game_directions(0);
    }
    mpp_w.useAnalogStickData = false;
}

static void test_digital_only_controller(void) {
    SDL_VirtualJoystickDesc description;
    SDL_INIT_INTERFACE(&description);
    description.type = SDL_JOYSTICK_TYPE_GAMEPAD;
    description.nbuttons = SDL_GAMEPAD_BUTTON_COUNT;
    description.button_mask = (1u << SDL_GAMEPAD_BUTTON_COUNT) - 1u;
    description.name = "3SX digital-only controller test";
    const SDL_JoystickID id = SDL_AttachVirtualJoystick(&description);
    assert(id != 0 && SDL_IsGamepad(id));
    virtual_pad = SDL_OpenJoystick(id);
    assert(virtual_pad != NULL);
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_EVENT_GAMEPAD_ADDED) SDLPad_HandleGamepadDeviceEvent(&event.gdevice);
    }
    assert(flPADInitialize() != 0);
    mpp_w.useAnalogStickData = false;
    flPADGetALL();
    assert(SDL_SetJoystickVirtualButton(virtual_pad, SDL_GAMEPAD_BUTTON_DPAD_RIGHT, true));
    SDL_UpdateJoysticks();

    for (int value = 1; value <= 100; value += 99) {
        sensitivity(value, 0);
        SDLPad_StickPreview preview;
        assert(SDLPad_GetStickPreview(0, &preview));
        assert(!preview.has_left_stick && !preview.has_right_stick);
        assert(preview.raw.dpad_right && preview.tuned.dpad_right);
        expect_game_directions(SWK_RIGHT);
    }
    SDL_CloseJoystick(virtual_pad);
    assert(SDL_DetachVirtualJoystick(id));
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_EVENT_GAMEPAD_REMOVED) SDLPad_HandleGamepadDeviceEvent(&event.gdevice);
    }
    flPADDestroy();
}

int main(void) {
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    assert(SDL_Init(SDL_INIT_GAMEPAD));
    SDLPad_Init();

    SDL_VirtualJoystickDesc description;
    SDL_INIT_INTERFACE(&description);
    description.type = SDL_JOYSTICK_TYPE_GAMEPAD;
    description.naxes = SDL_GAMEPAD_AXIS_COUNT;
    description.nbuttons = SDL_GAMEPAD_BUTTON_COUNT;
    description.axis_mask = (1u << SDL_GAMEPAD_AXIS_COUNT) - 1u;
    description.button_mask = (1u << SDL_GAMEPAD_BUTTON_COUNT) - 1u;
    description.name = "3SX controller integration test";
    const SDL_JoystickID id = SDL_AttachVirtualJoystick(&description);
    assert(id != 0 && SDL_IsGamepad(id));
    virtual_pad = SDL_OpenJoystick(id);
    assert(virtual_pad != NULL);

    bool delivered = false;
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_EVENT_GAMEPAD_ADDED || event.type == SDL_EVENT_GAMEPAD_REMOVED) {
            SDLPad_HandleGamepadDeviceEvent(&event.gdevice);
            if (event.type == SDL_EVENT_GAMEPAD_ADDED && event.gdevice.which == id) delivered = true;
        }
    }
    assert(delivered);
    assert(flPADInitialize() != 0);
    mpp_w.useAnalogStickData = false;
    set_sticks(0, 0, 0, 0);
    // The original PS2 driver identifies a pad on its first read.
    flPADGetALL();
    expect_game_directions(0);

    // The same physical throw must activate at high sensitivity and remain idle
    // at lower settings, even when the game's Analog Stick option is disabled.
    sensitivity(1, 0); set_sticks(14000, 0, 0, 0); expect_game_directions(0);
    sensitivity(50, 0); expect_game_directions(0);
    sensitivity(100, 0); expect_game_directions(SWK_RIGHT);
    set_sticks(0, 0, 0, 0); expect_game_directions(0);

    test_touch_stick_sensitivity();
    test_physical_preview_and_analog_modes();

    sensitivity(1, 0); set_sticks(32767, 0, 0, 0); expect_game_directions(SWK_RIGHT);
    set_sticks(-32768, 0, 0, 0); expect_game_directions(SWK_LEFT);
    sensitivity(50, 0); set_sticks(22000, 22000, 0, 0); expect_game_directions(SWK_DOWN | SWK_RIGHT);
    set_sticks(0, 0, 0, -32768); expect_game_directions(SWK_UP);

    // Left-stick priority and physical D-pad priority must not produce opposing
    // directions when multiple sources disagree.
    set_sticks(0, -32768, 32767, 0); expect_game_directions(SWK_UP);
    set_sticks(32767, 0, 0, 0);
    assert(SDL_SetJoystickVirtualButton(virtual_pad, SDL_GAMEPAD_BUTTON_DPAD_LEFT, true));
    SDL_UpdateJoysticks(); expect_game_directions(SWK_LEFT);
    assert(SDL_SetJoystickVirtualButton(virtual_pad, SDL_GAMEPAD_BUTTON_DPAD_LEFT, false));
    SDL_UpdateJoysticks(); expect_game_directions(SWK_RIGHT);

    // Dead-zone drift must not become a direction at maximum sensitivity.
    sensitivity(100, 35); set_sticks(6000, -6000, 0, 0); expect_game_directions(0);
    sensitivity(100, 0); set_sticks(6000, 0, 0, 0); expect_game_directions(SWK_RIGHT);
    set_sticks(0, 0, 0, 0); expect_game_directions(0);

    SDL_CloseJoystick(virtual_pad);
    assert(SDL_DetachVirtualJoystick(id));
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_EVENT_GAMEPAD_REMOVED) SDLPad_HandleGamepadDeviceEvent(&event.gdevice);
    }
    flPADDestroy();
    test_digital_only_controller();
    SDL_Quit();
    puts("iOS physical-controller and touch-stick to game-direction integration tests passed");
    return 0;
}
