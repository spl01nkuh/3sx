#include "platform/app/ios/ios_options.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>

static void expect_viewport(SDL_Rect available, SDL_Rect expected) {
    SDL_Rect actual = IOSOptions_Viewport(available);
    assert(actual.x == expected.x && actual.y == expected.y);
    assert(actual.w == expected.w && actual.h == expected.h);
}

static void test_viewport_controls(void) {
    const SDL_Rect area = { 20, 10, 1920, 1080 };
    IOSOptions options = IOSOptions_Defaults();
    assert(options.screen_percent == 100);
    assert(options.screen_width_percent == 100 && options.screen_height_percent == 100);
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { 260, 10, 1440, 1080 });

    // Changing one axis preserves the other dimension and keeps the image centered.
    options.screen_width_percent = 50;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { 620, 10, 720, 1080 });
    options.screen_width_percent = 100;
    options.screen_height_percent = 50;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { 260, 280, 1440, 540 });

    // Axes can stretch independently beyond the aspect-fitted area. Negative
    // origins deliberately crop a centered zoom at the render target boundary.
    options.screen_width_percent = 150;
    options.screen_height_percent = 75;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { -100, 145, 2160, 810 });
    options.screen_width_percent = options.screen_height_percent = 200;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { -460, -530, 2880, 2160 });

    // Overall size and independent axes compose multiplicatively.
    options.screen_percent = 50;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { 260, 10, 1440, 1080 });
    options.screen_percent = 25;
    options.screen_width_percent = options.screen_height_percent = 100;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { 800, 415, 360, 270 });
    options.screen_width_percent = 25;
    options.screen_height_percent = 200;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { 935, 280, 90, 540 });

    options.aspect = IOS_ASPECT_FILL;
    options.screen_percent = 100;
    options.screen_width_percent = 200;
    options.screen_height_percent = 25;
    IOSOptions_Apply(options);
    expect_viewport(area, (SDL_Rect) { -940, 415, 3840, 270 });

    // Original pixel aspect is fitted first, then scaled with integer rounding.
    options.aspect = IOS_ASPECT_NATIVE;
    options.screen_width_percent = 25;
    options.screen_height_percent = 200;
    IOSOptions_Apply(options);
    expect_viewport((SDL_Rect) { 0, 0, 1920, 1080 }, (SDL_Rect) { 729, -540, 462, 2160 });

    options.screen_percent = -100;
    options.screen_width_percent = -1;
    options.screen_height_percent = 999;
    IOSOptions_Apply(options);
    assert(IOSOptions_Get()->screen_percent == 25);
    assert(IOSOptions_Get()->screen_width_percent == 25 && IOSOptions_Get()->screen_height_percent == 200);
    options.screen_percent = 999;
    options.screen_width_percent = 999;
    options.screen_height_percent = -100;
    IOSOptions_Apply(options);
    assert(IOSOptions_Get()->screen_percent == 100);
    assert(IOSOptions_Get()->screen_width_percent == 200 && IOSOptions_Get()->screen_height_percent == 25);

    options = IOSOptions_Defaults();
    options.screen_percent = options.screen_width_percent = options.screen_height_percent = 25;
    IOSOptions_Apply(options);
    expect_viewport((SDL_Rect) { 7, 9, 1, 1 }, (SDL_Rect) { 7, 9, 1, 1 });
    expect_viewport((SDL_Rect) { 7, 9, 0, 20 }, (SDL_Rect) { 7, 9, 0, 0 });
    expect_viewport((SDL_Rect) { 7, 9, 20, 0 }, (SDL_Rect) { 7, 9, 0, 0 });
    expect_viewport((SDL_Rect) { 7, 9, -1, 20 }, (SDL_Rect) { 7, 9, 0, 0 });
}

int main(void) {
    test_viewport_controls();
    IOSOptions options = IOSOptions_Defaults();
    assert(options.stick_sensitivity == 50 && options.filter_strength == 75);
    IOSOptions_Apply(options);
    Sint16 x = -32768, y = 0;
    IOSOptions_AdjustStick(&x, &y);
    assert(x == -32768 && y == 0);
    SDL_Rect viewport = IOSOptions_Viewport((SDL_Rect) { 20, 10, 1920, 1080 });
    assert(viewport.x == 260 && viewport.y == 10 && viewport.w == 1440 && viewport.h == 1080);
    options.aspect = IOS_ASPECT_FILL; options.screen_percent = 50;
    IOSOptions_Apply(options);
    viewport = IOSOptions_Viewport((SDL_Rect) { 20, 10, 1920, 1080 });
    assert(viewport.x == 500 && viewport.y == 280 && viewport.w == 960 && viewport.h == 540);
    options.aspect = IOS_ASPECT_NATIVE; options.screen_percent = 100;
    IOSOptions_Apply(options);
    viewport = IOSOptions_Viewport((SDL_Rect) { 0, 0, 1920, 1080 });
    assert(viewport.w == 1851 && viewport.h == 1080);
    options.stick_deadzone = 20;
    IOSOptions_Apply(options); x = 1000; y = -2000;
    IOSOptions_AdjustStick(&x, &y); assert(x == 0 && y == 0);
    options.stick_deadzone = 0;
    // One physical position must cross the gameplay activation threshold as the
    // setting changes. Greater sensitivity always means less required travel.
    Sint16 previous = 0;
    for (int sensitivity = 1; sensitivity <= 100; ++sensitivity) {
        options.stick_sensitivity = sensitivity;
        IOSOptions_Apply(options);
        x = 14000; y = 0;
        IOSOptions_AdjustStick(&x, &y);
        assert(x >= previous && y == 0);
        previous = x;
        if (sensitivity == 1 || sensitivity == 50) assert(x < 16384);
        if (sensitivity == 100) assert(x > 16384);

        // Full throw must still reach either signed endpoint at every setting.
        x = 32767; y = 0;
        IOSOptions_AdjustStick(&x, &y); assert(x == 32767 && y == 0);
        x = 0; y = -32768;
        IOSOptions_AdjustStick(&x, &y); assert(x == 0 && y == -32768);
        x = 0; y = 0;
        IOSOptions_AdjustStick(&x, &y); assert(x == 0 && y == 0);
    }
    options.stick_sensitivity = 100;
    IOSOptions_Apply(options); x = 5000; y = -5000;
    IOSOptions_AdjustStick(&x, &y);
    assert((int)x * x + (int)y * y > 16384 * 16384 && abs(y + x) <= 1);
    // A dead zone raises the activation travel without suppressing full throw.
    options.stick_deadzone = 20;
    IOSOptions_Apply(options); x = 5000; y = 0;
    IOSOptions_AdjustStick(&x, &y); assert(x == 0 && y == 0);
    options.screen_percent = -100; options.stick_sensitivity = 999; options.stick_deadzone = -1;
    options.filter = 999; options.aspect = 999;
    IOSOptions_Apply(options);
    assert(IOSOptions_Get()->screen_percent == 25 && IOSOptions_Get()->stick_sensitivity == 100);
    assert(IOSOptions_Get()->stick_deadzone == 0 && IOSOptions_Get()->filter == IOS_FILTER_COUNT - 1);
    assert(IOSOptions_Get()->aspect == IOS_ASPECT_FILL);
    options.stick_sensitivity = -1;
    IOSOptions_Apply(options);
    assert(IOSOptions_Get()->stick_sensitivity == 1);
    for (int i = 0; i < IOS_FILTER_COUNT; ++i) assert(IOSOptions_FilterName(i) != NULL);
    puts("iOS options viewport, controller response and bounds tests passed");
}
