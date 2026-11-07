#if CRS_PLATFORM_IOS

#include "platform/input/ios/ios_touch_state.h"

uint16_t IOSTouchState_Directions(float x, float y) {
    uint16_t controls = 0;
    // A square dead zone supports diagonal motions without lifting the finger.
    if (x < -0.25f) controls |= IOS_TOUCH_LEFT;
    if (x > 0.25f) controls |= IOS_TOUCH_RIGHT;
    if (y < -0.25f) controls |= IOS_TOUCH_UP;
    if (y > 0.25f) controls |= IOS_TOUCH_DOWN;
    return controls;
}

Input_ButtonState IOSTouchState_Buttons(uint16_t controls) {
    // Default PS2 layout: square/triangle/R1, cross/circle/R2.
    return (Input_ButtonState) {
        .dpad_up = (controls & IOS_TOUCH_UP) != 0,
        .dpad_down = (controls & IOS_TOUCH_DOWN) != 0,
        .dpad_left = (controls & IOS_TOUCH_LEFT) != 0,
        .dpad_right = (controls & IOS_TOUCH_RIGHT) != 0,
        .west = (controls & IOS_TOUCH_LP) != 0,
        .north = (controls & IOS_TOUCH_MP) != 0,
        .right_shoulder = (controls & IOS_TOUCH_HP) != 0,
        .south = (controls & IOS_TOUCH_LK) != 0,
        .east = (controls & IOS_TOUCH_MK) != 0,
        .right_trigger = (controls & IOS_TOUCH_HK) ? SDL_MAX_SINT16 : 0,
        .back = (controls & IOS_TOUCH_SELECT) != 0,
        .start = (controls & IOS_TOUCH_START) != 0,
    };
}

void IOSTouchState_Merge(Input_ButtonState* destination, const Input_ButtonState* touch) {
    destination->dpad_up |= touch->dpad_up;
    destination->dpad_down |= touch->dpad_down;
    destination->dpad_left |= touch->dpad_left;
    destination->dpad_right |= touch->dpad_right;
    destination->west |= touch->west;
    destination->north |= touch->north;
    destination->right_shoulder |= touch->right_shoulder;
    destination->south |= touch->south;
    destination->east |= touch->east;
    destination->right_trigger = SDL_max(destination->right_trigger, touch->right_trigger);
    destination->back |= touch->back;
    destination->start |= touch->start;
}

#endif
