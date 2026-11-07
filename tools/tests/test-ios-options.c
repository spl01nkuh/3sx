#include "platform/app/ios/ios_options.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    IOSOptions options = IOSOptions_Defaults();
    IOSOptions_Apply(options);
    Sint16 x = -32768, y = 32767;
    IOSOptions_AdjustStick(&x, &y);
    assert(x == -32768 && y == 32767);
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
    options.stick_deadzone = 0; options.stick_sensitivity = 200;
    IOSOptions_Apply(options); x = 12000; y = -12000;
    IOSOptions_AdjustStick(&x, &y); assert(x > 12000 && y == -x);
    x = 0; y = -32768;
    IOSOptions_AdjustStick(&x, &y); assert(x == 0 && y == -32768);
    options.stick_sensitivity = 50;
    IOSOptions_Apply(options); x = -32768; y = 0;
    IOSOptions_AdjustStick(&x, &y); assert(x == -32768 && y == 0);
    x = 16000; y = 0;
    IOSOptions_AdjustStick(&x, &y); assert(x > 0 && x < 16000);
    options.screen_percent = -100; options.stick_sensitivity = 999; options.stick_deadzone = -1;
    options.filter = 999; options.aspect = 999;
    IOSOptions_Apply(options);
    assert(IOSOptions_Get()->screen_percent == 50 && IOSOptions_Get()->stick_sensitivity == 200);
    assert(IOSOptions_Get()->stick_deadzone == 0 && IOSOptions_Get()->filter == IOS_FILTER_COUNT - 1);
    assert(IOSOptions_Get()->aspect == IOS_ASPECT_FILL);
    for (int i = 0; i < IOS_FILTER_COUNT; ++i) assert(IOSOptions_FilterName(i) != NULL);
    puts("iOS options viewport, controller response and bounds tests passed");
}
