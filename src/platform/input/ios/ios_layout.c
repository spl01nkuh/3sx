#if CRS_PLATFORM_IOS

#include "platform/input/ios/ios_layout.h"
#include "platform/input/ios/ios_touch_state.h"

#include <math.h>
#include <stddef.h>

static float clamp(float value, float minimum, float maximum) {
    return value < minimum ? minimum : value > maximum ? maximum : value;
}

static float finite_or(float value, float fallback) {
    return isfinite(value) ? value : fallback;
}

static IOSLayout_Rect sanitized_safe(IOSLayout_Rect safe) {
    safe.x = finite_or(safe.x, 0.0f);
    safe.y = finite_or(safe.y, 0.0f);
    safe.w = fmaxf(0.0f, finite_or(safe.w, 0.0f));
    safe.h = fmaxf(0.0f, finite_or(safe.h, 0.0f));
    return safe;
}

static float responsive_scale(IOSLayout_Rect safe) {
    return clamp(fminf(safe.w / 740.0f, safe.h / 320.0f), 0.55f, 1.25f);
}

IOSLayout_Rect IOSLayout_Frame(IOSLayout_Control control, IOSLayout_Rect safe) {
    safe = sanitized_safe(safe);
    float scale = responsive_scale(safe) * clamp(finite_or(control.size, 1.0f), 0.55f, 2.0f);
    float width = control.dpad ? 156.0f : control.menu ? 68.0f : 54.0f;
    float height = control.dpad ? 156.0f : control.menu ? 30.0f : 54.0f;
    // Preserve the shape if a very small safe area cannot fit the chosen size.
    float fit = fminf(1.0f, fminf(safe.w / (width * scale), safe.h / (height * scale)));
    width *= scale * fit;
    height *= scale * fit;
    float center_x = safe.x + clamp(finite_or(control.center_x, 0.5f), 0.0f, 1.0f) * safe.w;
    float center_y = safe.y + clamp(finite_or(control.center_y, 0.5f), 0.0f, 1.0f) * safe.h;
    return (IOSLayout_Rect) {
        .x = clamp(center_x - width / 2.0f, safe.x, safe.x + safe.w - width),
        .y = clamp(center_y - height / 2.0f, safe.y, safe.y + safe.h - height),
        .w = width,
        .h = height,
    };
}

void IOSLayout_Move(IOSLayout_Control* control, IOSLayout_Rect safe, float center_x_pixels, float center_y_pixels) {
    if (control == NULL) {
        return;
    }
    safe = sanitized_safe(safe);
    control->center_x = safe.w > 0.0f ? (finite_or(center_x_pixels, safe.x + safe.w / 2.0f) - safe.x) / safe.w : 0.5f;
    control->center_y = safe.h > 0.0f ? (finite_or(center_y_pixels, safe.y + safe.h / 2.0f) - safe.y) / safe.h : 0.5f;
    control->size = clamp(finite_or(control->size, 1.0f), 0.55f, 2.0f);
    IOSLayout_Rect frame = IOSLayout_Frame(*control, safe);
    control->center_x = safe.w > 0.0f ? (frame.x + frame.w / 2.0f - safe.x) / safe.w : 0.5f;
    control->center_y = safe.h > 0.0f ? (frame.y + frame.h / 2.0f - safe.y) / safe.h : 0.5f;
}

bool IOSLayout_Hit(IOSLayout_Rect rect, float x, float y) {
    return isfinite(x) && isfinite(y) && rect.w > 0.0f && rect.h > 0.0f &&
           x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h;
}

IOSLayout_Control IOSLayout_Default(int index, IOSLayout_Rect safe) {
    safe = sanitized_safe(safe);
    IOSLayout_Control control = { .center_x = 0.5f, .center_y = 0.5f, .size = 1.0f };
    float scale = responsive_scale(safe);
    float margin = 14.0f * scale;
    float center_x = safe.x + safe.w / 2.0f;
    float center_y = safe.y + safe.h / 2.0f;
    if (index == 0) {
        control.dpad = true;
        center_x = safe.x + margin + 78.0f * scale;
        center_y = safe.y + safe.h - margin - 78.0f * scale;
    } else if (index >= 1 && index <= 6) {
        static const uint16_t bindings[] = {
            IOS_TOUCH_LP, IOS_TOUCH_MP, IOS_TOUCH_HP,
            IOS_TOUCH_LK, IOS_TOUCH_MK, IOS_TOUCH_HK
        };
        control.binding = bindings[index - 1];
        int column = (index - 1) % 3;
        int row = (index - 1) / 3;
        float diameter = 54.0f * scale;
        float gap = 10.0f * scale;
        center_x = safe.x + safe.w - margin - 3.0f * diameter - 2.0f * gap + column * (diameter + gap) + diameter / 2.0f;
        center_y = safe.y + safe.h - margin - 2.0f * diameter - gap + row * (diameter + gap) + diameter / 2.0f;
    } else if (index == 7 || index == 8) {
        control.menu = true;
        control.binding = index == 7 ? IOS_TOUCH_SELECT : IOS_TOUCH_START;
        float offset = 39.0f * scale; // Half a 68pt button plus half a 10pt gap.
        center_x += index == 7 ? -offset : offset;
        center_y = safe.y + safe.h - margin - 15.0f * scale;
    }
    IOSLayout_Move(&control, safe, center_x, center_y);
    return control;
}

uint16_t IOSLayout_Directions(IOSLayout_DirectionStyle style, float x, float y) {
    if (!isfinite(x) || !isfinite(y)) return 0;
    uint16_t controls = 0;
    if (style == IOS_LAYOUT_STICK) {
        if (hypotf(x, y) <= 0.25f) return 0;
        // tan(22.5 degrees): eight equal sectors, including diagonals.
        const float slope = 0.41421356237f;
        if (fabsf(x) >= fabsf(y) * slope) controls |= x < 0 ? IOS_TOUCH_LEFT : IOS_TOUCH_RIGHT;
        if (fabsf(y) >= fabsf(x) * slope) controls |= y < 0 ? IOS_TOUCH_UP : IOS_TOUCH_DOWN;
    } else {
        const float threshold = style == IOS_LAYOUT_DPAD ? 1.0f / 3.0f : 0.25f;
        if (x < -threshold) controls |= IOS_TOUCH_LEFT;
        if (x > threshold) controls |= IOS_TOUCH_RIGHT;
        if (y < -threshold) controls |= IOS_TOUCH_UP;
        if (y > threshold) controls |= IOS_TOUCH_DOWN;
    }
    return controls;
}

#endif
