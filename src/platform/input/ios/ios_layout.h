#ifndef IOS_LAYOUT_H
#define IOS_LAYOUT_H

#include <stdbool.h>
#include <stdint.h>

typedef enum IOSLayout_DirectionStyle {
    IOS_LAYOUT_HYBRID = 0,
    IOS_LAYOUT_STICK,
    IOS_LAYOUT_DPAD,
    IOS_LAYOUT_DIRECTION_STYLE_COUNT,
} IOSLayout_DirectionStyle;

typedef struct IOSLayout_Rect {
    float x;
    float y;
    float w;
    float h;
} IOSLayout_Rect;

typedef struct IOSLayout_Control {
    float center_x; // Normalized within the current safe area, 0 through 1.
    float center_y;
    float size; // Multiplier, 0.55 through 2.0.
    uint16_t binding;
    bool dpad;
    bool menu;
} IOSLayout_Control;

// Frames remain entirely within the safe area, including after size changes.
IOSLayout_Rect IOSLayout_Frame(IOSLayout_Control control, IOSLayout_Rect safe);
void IOSLayout_Move(IOSLayout_Control* control, IOSLayout_Rect safe, float center_x_pixels, float center_y_pixels);
bool IOSLayout_Hit(IOSLayout_Rect rect, float x, float y);
// Built-ins: D-pad, LP/MP/HP/LK/MK/HK, Select, Start (indices 0 through 8).
IOSLayout_Control IOSLayout_Default(int index, IOSLayout_Rect safe);
// All styles produce the game's digital eight-way input. The stick uses a
// radial dead zone and angular sectors; pad styles use their visible grid.
uint16_t IOSLayout_Directions(IOSLayout_DirectionStyle style, float x, float y);

#endif
