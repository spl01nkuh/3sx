/* Host test (also suitable for the iOS workflow):
   cc -std=c2x -Wall -Werror -DCRS_PLATFORM_IOS=1 -Isrc -I/path/to/SDL/include \
     tools/tests/test-ios-motion.c src/platform/input/ios/ios_motion.c -o test-ios-motion
*/
#include "platform/input/ios/ios_motion.h"
#include "platform/input/ios/ios_touch_state.h"

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define U IOS_TOUCH_UP
#define D IOS_TOUCH_DOWN
#define L IOS_TOUCH_LEFT
#define R IOS_TOUCH_RIGHT
#define PPP (IOS_TOUCH_LP | IOS_TOUCH_MP | IOS_TOUCH_HP)
#define KKK (IOS_TOUCH_LK | IOS_TOUCH_MK | IOS_TOUCH_HK)

static uint16_t mirror(uint16_t value) {
    uint16_t result = value & ~(L | R);
    if (value & L) result |= R;
    if (value & R) result |= L;
    return result;
}

static void check_sequence(IOSMotion_ID motion, const uint16_t* directions, size_t count, bool mirrored) {
    IOSMotion_State state = { 0 };
    assert(IOSMotion_Start(&state, motion, mirrored, PPP));
    unsigned frames = 0;
    for (size_t index = 0; index < count; index++) {
        uint16_t expected = mirrored ? mirror(directions[index]) : directions[index];
        bool finishing360 = motion == IOS_MOTION_FULL360 && index >= 6;
        if (finishing360) expected |= PPP;
        for (unsigned hold = 0; hold < 2; hold++) {
            assert(state.active);
            assert(IOSMotion_Tick(&state) == expected);
            frames++;
        }
        if (index + 1 < count) {
            assert(IOSMotion_Tick(&state) == (finishing360 ? PPP : 0));
            frames++;
        }
    }
    uint16_t final_direction = mirrored ? mirror(directions[count - 1]) : directions[count - 1];
    assert(IOSMotion_Tick(&state) == (final_direction | PPP));
    assert(state.active);
    assert(IOSMotion_Tick(&state) == (final_direction | PPP));
    assert(!state.active);
    frames += 2;
    assert(frames == count * 2 + (count - 1) + 2);
    assert(frames <= 25);
    for (unsigned frame = 0; frame < 120; frame++) {
        assert(IOSMotion_Tick(&state) == 0);
    }
}

int main(void) {
    static const uint16_t qcf[] = { D, D | R, R };
    static const uint16_t qcb[] = { D, D | L, L };
    static const uint16_t left_down[] = { L, L | D, D };
    static const uint16_t dp_forward[] = { R, D, D | R };
    static const uint16_t dp_backward[] = { L, D, D | L };
    static const uint16_t full360[] = { R, R | D, D, D | L, L, L | U, U, U | R };
    static const uint16_t half_forward[] = { L, D | L, D, D | R, R };
    static const uint16_t half_backward[] = { R, D | R, D, D | L, L };
    for (int mirrored = 0; mirrored <= 1; mirrored++) {
        check_sequence(IOS_MOTION_QCF, qcf, 3, mirrored);
        check_sequence(IOS_MOTION_QCB, qcb, 3, mirrored);
        check_sequence(IOS_MOTION_LEFT_DOWN, left_down, 3, mirrored);
        check_sequence(IOS_MOTION_DP_FORWARD, dp_forward, 3, mirrored);
        check_sequence(IOS_MOTION_DP_BACKWARD, dp_backward, 3, mirrored);
        check_sequence(IOS_MOTION_FULL360, full360, 8, mirrored);
        check_sequence(IOS_MOTION_HALF_FORWARD, half_forward, 5, mirrored);
        check_sequence(IOS_MOTION_HALF_BACKWARD, half_backward, 5, mirrored);
    }

    IOSMotion_State state = { 0 };
    assert(IOSMotion_Tick(&state) == 0);
    // A motion-only custom button must never add an attack or menu button.
    assert(IOSMotion_Start(&state, IOS_MOTION_QCF, false, 0));
    const uint16_t motion_only[] = { D, D, 0, D | R, D | R, 0, R, R, R, R };
    for (size_t frame = 0; frame < sizeof(motion_only) / sizeof(motion_only[0]); frame++) {
        assert(IOSMotion_Tick(&state) == motion_only[frame]);
    }
    assert(!state.active && IOSMotion_Tick(&state) == 0);
    assert(IOSMotion_Start(&state, IOS_MOTION_QCF, false, PPP));
    assert(IOSMotion_Tick(&state) == D);
    IOSMotion_Cancel(&state);
    assert(!state.active && IOSMotion_Tick(&state) == 0);
    // An explicit second press restarts at the beginning with its own binding.
    assert(IOSMotion_Start(&state, IOS_MOTION_DP_FORWARD, false, IOS_TOUCH_LP));
    assert(IOSMotion_Tick(&state) == R);
    assert(IOSMotion_Start(&state, IOS_MOTION_QCB, true, KKK));
    assert(IOSMotion_Tick(&state) == D);
    for (unsigned frame = 1; frame < 8; frame++) IOSMotion_Tick(&state);
    assert(IOSMotion_Tick(&state) == (R | KKK));
    assert(IOSMotion_Tick(&state) == (R | KKK));
    assert(IOSMotion_Tick(&state) == 0);

    // Invalid/missing states and corrupted serialized IDs never start a loop.
    assert(!IOSMotion_Start(&state, IOS_MOTION_NONE, false, 0));
    assert(!IOSMotion_Start(&state, (IOSMotion_ID)-1, false, 0));
    assert(!IOSMotion_Start(&state, IOS_MOTION_COUNT, false, 0));
    assert(!IOSMotion_Start(NULL, IOS_MOTION_QCF, false, 0));
    assert(IOSMotion_Tick(NULL) == 0);
    IOSMotion_Cancel(NULL);
    state = (IOSMotion_State) { .active = true, .motion = IOS_MOTION_QCF, .remaining = 0 };
    assert(IOSMotion_Tick(&state) == 0 && !state.active);
    state = (IOSMotion_State) { .active = true, .motion = IOS_MOTION_QCF, .remaining = 2, .index = 500 };
    assert(IOSMotion_Tick(&state) == 0 && !state.active);
    assert(strcmp(IOSMotion_Name(IOS_MOTION_NONE), "None") == 0);
    assert(strcmp(IOSMotion_Name((IOSMotion_ID)900), "None") == 0);
    for (int motion = 1; motion < IOS_MOTION_COUNT; motion++) {
        assert(strlen(IOSMotion_Name((IOSMotion_ID)motion)) > 4);
    }
    puts("iOS motion shortcut tests passed");
    return 0;
}
