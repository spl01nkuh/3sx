#ifndef IOS_OPTIONS_H
#define IOS_OPTIONS_H

#include <SDL3/SDL.h>

typedef enum IOSFilter {
    IOS_FILTER_NONE, IOS_FILTER_SCANLINES, IOS_FILTER_CRT,
    IOS_FILTER_SLOT, IOS_FILTER_SHARP_SLOT, IOS_FILTER_MONITOR,
    IOS_FILTER_EGA, IOS_FILTER_EGA_OLD, IOS_FILTER_VGA, IOS_FILTER_VGA_OLD,
    IOS_FILTER_FAST_SLOT, IOS_FILTER_FAST_GRILLE, IOS_FILTER_COLOR,
    IOS_FILTER_NOISE, IOS_FILTER_ADAPTIVE, IOS_FILTER_COMPOSITE, IOS_FILTER_COUNT
} IOSFilter;
typedef enum IOSAspect { IOS_ASPECT_4_3, IOS_ASPECT_NATIVE, IOS_ASPECT_FILL } IOSAspect;
typedef struct IOSOptions {
    bool touch_enabled;
    int filter;
    int filter_strength;
    int screen_percent;
    int aspect;
    int stick_sensitivity;
    int stick_deadzone;
} IOSOptions;

IOSOptions IOSOptions_Defaults(void);
const IOSOptions* IOSOptions_Get(void);
void IOSOptions_Apply(IOSOptions options);
SDL_Rect IOSOptions_Viewport(SDL_Rect available);
void IOSOptions_AdjustStick(Sint16* x, Sint16* y);
const char* IOSOptions_FilterName(int filter);

// UIKit persistence and presentation, called on the SDL main thread.
void IOSOptions_Load(void);
void IOSOptions_Present(SDL_Window* window);
bool IOSOptions_IsOpen(void);

#endif
