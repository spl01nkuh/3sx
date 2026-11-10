/*
 * Portable motion sequencer -> production touch/button conversion -> SDLPad ->
 * PS2 pad -> game input. Only the UIKit contact source is represented by a
 * cached per-frame fixture; no game direction or attack conversion is replaced.
 */
#include "core/input.h"
#include "main.h"
#include "platform/input/ios/ios_motion.h"
#include "platform/input/ios/ios_touch.h"
#include "platform/input/ios/ios_touch_state.h"
#include "platform/input/sdl/sdl_pad.h"
#include "sf33rd/AcrSDK/common/mlPAD.h"
#include "sf33rd/Source/Game/io/ioconv.h"
#include "sf33rd/Source/Game/system/work_sys.h"

#include <SDL3/SDL.h>
#include <assert.h>
#include <stdio.h>

MPP mpp_w;
static IOSMotion_State motion;
static Input_ButtonState cached_touch;
static u16 previous_game_input;
static unsigned finish_edges;

void IOSTouch_GetButtonState(Input_ButtonState* state) {
    *state = cached_touch;
}

static void read_game_frame(u16 expected) {
    // Extra reads must see the same cached state and must not consume steps.
    Input_ButtonState first, second;
    Input_GetButtonState(0, &first);
    Input_GetButtonState(0, &second);
    assert(first.dpad_up == second.dpad_up && first.dpad_down == second.dpad_down);
    assert(first.dpad_left == second.dpad_left && first.dpad_right == second.dpad_right);
    assert(first.west == second.west && first.north == second.north);
    flPADGetALL();
    keyConvert();
    if (p1sw_buff != expected) fprintf(stderr, "Expected game input 0x%X, received 0x%X\n", expected, p1sw_buff);
    assert(p1sw_buff == expected);
    if ((p1sw_buff & 0x30) && !(previous_game_input & 0x30)) ++finish_edges;
    previous_game_input = p1sw_buff;
    assert(!mpp_w.useAnalogStickData);
}

static void tick_game_frame(u16 expected) {
    cached_touch = IOSTouchState_Buttons(IOSMotion_Tick(&motion));
    read_game_frame(expected);
}

static u16 mirror_direction(u16 direction) {
    // Expected game-direction bits: up1/down2/left4/right8.
    return (direction & 3) | ((direction & 4) << 1) | ((direction & 8) >> 1);
}

static void check_sequence(IOSMotion_ID id, const u16* directions, size_t count, bool mirror) {
    // The actual game punch bits for LP+MP are 0x10+0x20.
    assert(IOSMotion_Start(&motion, id, mirror, IOS_TOUCH_LP | IOS_TOUCH_MP));
    finish_edges = 0;
    for (size_t step = 0; step < count; step++) {
        u16 direction = mirror ? mirror_direction(directions[step]) : directions[step];
        // A standing360 presses on exact Up, three frames after the first
        // up-diagonal, then holds through the tail rather than pressing twice.
        const u16 early_finish = id == IOS_MOTION_FULL360 && step >= 6 ? 0x30 : 0;
        tick_game_frame(direction | early_finish);
        tick_game_frame(direction | early_finish);
        if (step + 1 < count) tick_game_frame(early_finish);
    }
    const u16 last = mirror ? mirror_direction(directions[count - 1]) : directions[count - 1];
    tick_game_frame(last | 0x30);
    tick_game_frame(last | 0x30);
    assert(!motion.active);
    assert(finish_edges == 1);
    // Keeping a shortcut held never restarts it; only an explicit Start can.
    for (int i = 0; i < 12; i++) tick_game_frame(0);
}

int main(void) {
    assert(SDL_Init(SDL_INIT_GAMEPAD));
    SDLPad_Init();
    assert(flPADInitialize() != 0);
    mpp_w.useAnalogStickData = false;
    flPADGetALL();
    read_game_frame(0);

    static const u16 qcf[] = { 2, 10, 8 };
    static const u16 qcb[] = { 2, 6, 4 };
    static const u16 left_down[] = { 4, 6, 2 };
    static const u16 dp_forward[] = { 8, 2, 10 };
    static const u16 dp_backward[] = { 4, 2, 6 };
    static const u16 full_circle[] = { 8, 10, 2, 6, 4, 5, 1, 9 };
    static const u16 half_forward[] = { 4, 6, 2, 10, 8 };
    static const u16 half_backward[] = { 8, 10, 2, 6, 4 };
#define CHECK(id, sequence) check_sequence(id, sequence, SDL_arraysize(sequence), false)
    CHECK(IOS_MOTION_QCF, qcf);
    CHECK(IOS_MOTION_QCB, qcb);
    CHECK(IOS_MOTION_LEFT_DOWN, left_down);
    CHECK(IOS_MOTION_DP_FORWARD, dp_forward);
    CHECK(IOS_MOTION_DP_BACKWARD, dp_backward);
    CHECK(IOS_MOTION_FULL360, full_circle);
    CHECK(IOS_MOTION_HALF_FORWARD, half_forward);
    CHECK(IOS_MOTION_HALF_BACKWARD, half_backward);
#undef CHECK
    check_sequence(IOS_MOTION_QCF, qcf, SDL_arraysize(qcf), true);
    check_sequence(IOS_MOTION_FULL360, full_circle, SDL_arraysize(full_circle), true);

    // Opening options/backgrounding resets the sequencer and cached contacts.
    assert(IOSMotion_Start(&motion, IOS_MOTION_QCF, false, IOS_TOUCH_HP));
    tick_game_frame(2);
    IOSMotion_Cancel(&motion);
    cached_touch = IOSTouchState_Buttons(0);
    read_game_frame(0);
    tick_game_frame(0);

    // A new explicit shortcut replaces an unfinished one without held attacks.
    assert(IOSMotion_Start(&motion, IOS_MOTION_QCF, false, IOS_TOUCH_HP));
    tick_game_frame(2);
    assert(IOSMotion_Start(&motion, IOS_MOTION_DP_BACKWARD, false, 0));
    tick_game_frame(4);
    IOSMotion_Cancel(&motion);
    tick_game_frame(0);

    assert(!IOSMotion_Start(&motion, (IOSMotion_ID)999, false, 0));
    tick_game_frame(0);
    flPADDestroy();
    SDL_Quit();
    puts("iOS motion sequence to game input integration tests passed");
    return 0;
}
