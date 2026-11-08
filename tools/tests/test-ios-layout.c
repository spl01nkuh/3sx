/* Run on a host with SDL3 headers:
   cc -std=c2x -DCRS_PLATFORM_IOS=1 -Isrc -I/path/to/SDL/include \
     tools/tests/test-ios-layout.c src/platform/input/ios/ios_layout.c -lm -o test-ios-layout
*/
#include "platform/input/ios/ios_layout.h"
#include "platform/input/ios/ios_touch_state.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>

static void assert_near(float value, float expected) {
    assert(fabsf(value - expected) < 0.001f);
}

static void assert_inside(IOSLayout_Rect frame, IOSLayout_Rect safe) {
    assert(isfinite(frame.x) && isfinite(frame.y) && isfinite(frame.w) && isfinite(frame.h));
    assert(frame.x >= safe.x - 0.001f && frame.y >= safe.y - 0.001f);
    assert(frame.x + frame.w <= safe.x + safe.w + 0.001f);
    assert(frame.y + frame.h <= safe.y + safe.h + 0.001f);
    assert(frame.w >= 0.0f && frame.h >= 0.0f);
}

int main(void) {
    // The original hybrid keeps its square dead zone and corner diagonals.
    assert(IOSLayout_Directions(IOS_LAYOUT_HYBRID, 0.2f, 0.2f) == 0);
    assert(IOSLayout_Directions(IOS_LAYOUT_HYBRID, 0.3f, 0.3f) == (IOS_TOUCH_RIGHT | IOS_TOUCH_DOWN));
    // A normal stick uses a circular dead zone and eight angular sectors.
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, 0.1f, 0.1f) == 0);
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, 0.2f, 0.2f) == (IOS_TOUCH_RIGHT | IOS_TOUCH_DOWN));
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, 0.8f, 0.3f) == IOS_TOUCH_RIGHT);
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, -0.8f, -0.8f) == (IOS_TOUCH_LEFT | IOS_TOUCH_UP));
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, 0, -0.8f) == IOS_TOUCH_UP);
    // Dragging beyond the stick's base keeps a stable direction until release.
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, 4, 0.1f) == IOS_TOUCH_RIGHT);
    // The classic D-pad's center occupies the middle cell of its cross.
    assert(IOSLayout_Directions(IOS_LAYOUT_DPAD, 0.3f, 0.3f) == 0);
    assert(IOSLayout_Directions(IOS_LAYOUT_DPAD, -0.8f, 0.8f) == (IOS_TOUCH_LEFT | IOS_TOUCH_DOWN));
    assert(IOSLayout_Directions(IOS_LAYOUT_DPAD, 0, 0.8f) == IOS_TOUCH_DOWN);
    assert(IOSLayout_Directions(IOS_LAYOUT_STICK, NAN, 0) == 0);
    assert(IOSLayout_Directions(IOS_LAYOUT_DPAD, INFINITY, 0) == 0);
    assert(IOSLayout_Directions((IOSLayout_DirectionStyle)999, 0.3f, 0) == IOS_TOUCH_RIGHT);

    IOSLayout_Rect phone = { .x = 44, .y = 0, .w = 740, .h = 320 };
    IOSLayout_Control dpad = IOSLayout_Default(0, phone);
    IOSLayout_Rect frame = IOSLayout_Frame(dpad, phone);
    assert(dpad.dpad && !dpad.menu);
    assert_near(frame.x, 58.0f);
    assert_near(frame.y, 150.0f);
    assert_near(frame.w, 156.0f);
    assert_near(frame.h, 156.0f);

    const uint16_t bindings[] = { IOS_TOUCH_LP, IOS_TOUCH_MP, IOS_TOUCH_HP,
                                  IOS_TOUCH_LK, IOS_TOUCH_MK, IOS_TOUCH_HK };
    for (int i = 1; i <= 6; i++) {
        IOSLayout_Control attack = IOSLayout_Default(i, phone);
        assert(attack.binding == bindings[i - 1] && !attack.dpad && !attack.menu);
        assert_inside(IOSLayout_Frame(attack, phone), phone);
    }
    assert(IOSLayout_Default(7, phone).binding == IOS_TOUCH_SELECT);
    assert(IOSLayout_Default(8, phone).binding == IOS_TOUCH_START);
    assert(IOSLayout_Default(7, phone).menu && IOSLayout_Default(8, phone).menu);

    // Dragging and resizing at an edge must retain the whole hit target on-screen.
    dpad.size = 2.0f;
    IOSLayout_Move(&dpad, phone, -1000, 9000);
    frame = IOSLayout_Frame(dpad, phone);
    assert_inside(frame, phone);
    assert_near(frame.x, phone.x);
    assert_near(frame.y + frame.h, phone.y + phone.h);

    // Saved normalized centers adapt to an iPad safe area without escaping it.
    IOSLayout_Rect tablet = { .x = 20, .y = 24, .w = 1326, .h = 980 };
    for (int i = 0; i < 9; i++) {
        IOSLayout_Control control = IOSLayout_Default(i, phone);
        assert_inside(IOSLayout_Frame(control, tablet), tablet);
    }
    IOSLayout_Control attack = IOSLayout_Default(1, phone);
    IOSLayout_Move(&attack, phone, phone.x + phone.w * 0.6f, phone.y + phone.h * 0.3f);
    frame = IOSLayout_Frame(attack, tablet);
    assert_near(frame.x + frame.w / 2, tablet.x + tablet.w * 0.6f);
    assert_near(frame.y + frame.h / 2, tablet.y + tablet.h * 0.3f);

    // Hit testing follows edited frames; the old location no longer presses it.
    frame = IOSLayout_Frame(attack, phone);
    assert(IOSLayout_Hit(frame, frame.x + frame.w / 2, frame.y + frame.h / 2));
    assert(!IOSLayout_Hit(frame, frame.x - 1, frame.y + frame.h / 2));
    assert(!IOSLayout_Hit(frame, frame.x + frame.w, frame.y + frame.h / 2));
    assert(!IOSLayout_Hit(frame, NAN, 0));

    // Corrupted preferences, zero-size layouts and tiny split views remain finite.
    IOSLayout_Control invalid = { .center_x = NAN, .center_y = INFINITY, .size = NAN, .dpad = true };
    assert_inside(IOSLayout_Frame(invalid, phone), phone);
    IOSLayout_Move(&invalid, phone, NAN, INFINITY);
    assert(isfinite(invalid.center_x) && isfinite(invalid.center_y) && isfinite(invalid.size));
    IOSLayout_Rect tiny = { .x = 4, .y = 8, .w = 2, .h = 1 };
    assert_inside(IOSLayout_Frame(dpad, tiny), tiny);
    IOSLayout_Rect empty = { 0 };
    IOSLayout_Move(&invalid, empty, 20, 30);
    assert_near(invalid.center_x, 0.5f);
    assert_near(invalid.center_y, 0.5f);
    frame = IOSLayout_Frame(invalid, empty);
    assert_near(frame.w, 0);
    assert_near(frame.h, 0);
    assert(!IOSLayout_Hit(frame, 0, 0));

    puts("iOS touch layout tests passed");
    return 0;
}
