#if CRS_PLATFORM_IOS
#include "platform/app/ios/ios_options.h"
#include <math.h>

static IOSOptions current = { true, IOS_FILTER_NONE, 50, 100, IOS_ASPECT_4_3, 100, 0 };

IOSOptions IOSOptions_Defaults(void) {
    return (IOSOptions) { true, IOS_FILTER_NONE, 50, 100, IOS_ASPECT_4_3, 100, 0 };
}

const IOSOptions* IOSOptions_Get(void) { return &current; }

void IOSOptions_Apply(IOSOptions options) {
    options.filter = SDL_clamp(options.filter, IOS_FILTER_NONE, IOS_FILTER_COUNT - 1);
    options.filter_strength = SDL_clamp(options.filter_strength, 0, 100);
    options.screen_percent = SDL_clamp(options.screen_percent, 50, 100);
    options.aspect = SDL_clamp(options.aspect, IOS_ASPECT_4_3, IOS_ASPECT_FILL);
    options.stick_sensitivity = SDL_clamp(options.stick_sensitivity, 50, 200);
    options.stick_deadzone = SDL_clamp(options.stick_deadzone, 0, 35);
    current = options;
}

const char* IOSOptions_FilterName(int filter) {
    static const char* names[] = {
        "Off", "CRT Scanlines", "CRT TV", "CRT TV Slot Mask", "CRT TV Slot Mask Sharp",
        "CRT TV Monitor", "EGA Newer", "EGA Older", "VGA Newer", "VGA Older",
        "VGA Slot Mask Fast", "VGA Trinitron Fast", "Color Controls", "CRT Noise",
        "Adaptive Blend", "Composite"
    };
    return names[SDL_clamp(filter, 0, IOS_FILTER_COUNT - 1)];
}

SDL_Rect IOSOptions_Viewport(SDL_Rect available) {
    SDL_Rect result = available;
    if (current.aspect != IOS_ASPECT_FILL && available.w > 0 && available.h > 0) {
        const float ratio = current.aspect == IOS_ASPECT_NATIVE ? 384.0f / 224.0f : 4.0f / 3.0f;
        result.h = (int)((float)result.w / ratio);
        if (result.h > available.h) {
            result.h = available.h;
            result.w = (int)((float)result.h * ratio);
        }
    }
    result.w = result.w * current.screen_percent / 100;
    result.h = result.h * current.screen_percent / 100;
    result.x = available.x + (available.w - result.w) / 2;
    result.y = available.y + (available.h - result.h) / 2;
    return result;
}

void IOSOptions_AdjustStick(Sint16* x, Sint16* y) {
    if (current.stick_sensitivity == 100 && current.stick_deadzone == 0) return;
    const float fx = (float)*x / 32768.0f;
    const float fy = (float)*y / 32768.0f;
    const float magnitude = sqrtf(fx * fx + fy * fy);
    const float deadzone = (float)current.stick_deadzone / 100.0f;
    if (magnitude <= deadzone) {
        *x = *y = 0;
        return;
    }
    // Shape response while retaining full deflection at every sensitivity.
    const float normalized = SDL_clamp((magnitude - deadzone) / (1.0f - deadzone), 0.0f, 1.0f);
    const float response = powf(normalized, 100.0f / (float)current.stick_sensitivity);
    const float scale = response / magnitude;
    const int rx = (int)roundf(SDL_clamp(fx * scale, -1.0f, 1.0f) * 32768.0f);
    const int ry = (int)roundf(SDL_clamp(fy * scale, -1.0f, 1.0f) * 32768.0f);
    *x = (Sint16)SDL_clamp(rx, -32768, 32767);
    *y = (Sint16)SDL_clamp(ry, -32768, 32767);
}
#endif
