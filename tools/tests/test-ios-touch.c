/* Run on a host with SDL3 headers (also run by the iOS build workflow):
   cc -std=c2x -DCRS_PLATFORM_IOS=1 -Isrc -I/path/to/SDL/include \
     tools/tests/test-ios-touch.c src/platform/input/ios/ios_touch_state.c -o test-ios-touch
*/
#include "platform/input/ios/ios_touch_state.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
    // A down-to-forward motion must preserve the diagonal, then release down.
    assert(IOSTouchState_Directions(0.0f, 0.8f) == IOS_TOUCH_DOWN);
    assert(IOSTouchState_Directions(0.8f, 0.8f) == (IOS_TOUCH_DOWN | IOS_TOUCH_RIGHT));
    assert(IOSTouchState_Directions(0.8f, 0.0f) == IOS_TOUCH_RIGHT);
    assert(IOSTouchState_Directions(-0.8f, -0.8f) == (IOS_TOUCH_UP | IOS_TOUCH_LEFT));
    assert(IOSTouchState_Directions(0.2f, -0.2f) == 0);

    Input_ButtonState chord = IOSTouchState_Buttons(
        IOS_TOUCH_RIGHT | IOS_TOUCH_DOWN | IOS_TOUCH_LP | IOS_TOUCH_MP | IOS_TOUCH_START);
    assert(chord.dpad_right && chord.dpad_down && chord.west && chord.north && chord.start);
    assert(!chord.south && !chord.east && !chord.right_shoulder && chord.right_trigger == 0);

    Input_ButtonState attacks = IOSTouchState_Buttons(
        IOS_TOUCH_LP | IOS_TOUCH_MP | IOS_TOUCH_HP | IOS_TOUCH_LK | IOS_TOUCH_MK | IOS_TOUCH_HK | IOS_TOUCH_SELECT);
    assert(attacks.west && attacks.north && attacks.right_shoulder);
    assert(attacks.south && attacks.east && attacks.right_trigger == SDL_MAX_SINT16 && attacks.back);

    // A touch press must add to physical input without erasing its axes/buttons.
    Input_ButtonState physical = { .left_stick_x = 12345, .left_shoulder = true, .south = true };
    IOSTouchState_Merge(&physical, &chord);
    assert(physical.left_stick_x == 12345 && physical.left_shoulder && physical.south);
    assert(physical.dpad_down && physical.dpad_right && physical.west && physical.north && physical.start);

    // Rebuilding from an empty contact set must release every touch control.
    Input_ButtonState released = IOSTouchState_Buttons(0);
    assert(!released.dpad_up && !released.dpad_down && !released.dpad_left && !released.dpad_right);
    assert(!released.west && !released.north && !released.right_shoulder && !released.south && !released.east);
    assert(released.right_trigger == 0 && !released.back && !released.start);
    puts("iOS touch state tests passed");
    return 0;
}
