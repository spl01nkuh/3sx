#ifndef IOS_TOUCH_STATE_H
#define IOS_TOUCH_STATE_H

#include "core/input.h"
#include <stdint.h>

typedef enum IOSTouchControl {
    IOS_TOUCH_UP = 1 << 0,
    IOS_TOUCH_DOWN = 1 << 1,
    IOS_TOUCH_LEFT = 1 << 2,
    IOS_TOUCH_RIGHT = 1 << 3,
    IOS_TOUCH_LP = 1 << 4,
    IOS_TOUCH_MP = 1 << 5,
    IOS_TOUCH_HP = 1 << 6,
    IOS_TOUCH_LK = 1 << 7,
    IOS_TOUCH_MK = 1 << 8,
    IOS_TOUCH_HK = 1 << 9,
    IOS_TOUCH_SELECT = 1 << 10,
    IOS_TOUCH_START = 1 << 11,
} IOSTouchControl;

// Coordinates relative to the D-pad center, with its radius equal to 1.
uint16_t IOSTouchState_Directions(float x, float y);
Input_ButtonState IOSTouchState_Buttons(uint16_t controls);
void IOSTouchState_Merge(Input_ButtonState* destination, const Input_ButtonState* touch);

#endif
