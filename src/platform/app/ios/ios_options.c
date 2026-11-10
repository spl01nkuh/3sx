#if CRS_PLATFORM_IOS
#include "platform/app/ios/ios_options.h"
#include <math.h>

#define IOS_DEFAULT_OPTIONS { true, IOS_FILTER_NONE, 75, 100, IOS_ASPECT_4_3, 50, 0, 100, 100 }
static IOSOptions current = IOS_DEFAULT_OPTIONS;

IOSOptions IOSOptions_Defaults(void) {
    return (IOSOptions) IOS_DEFAULT_OPTIONS;
}

const IOSOptions* IOSOptions_Get(void) { return &current; }

void IOSOptions_Apply(IOSOptions options) {
    options.filter = SDL_clamp(options.filter, IOS_FILTER_NONE, IOS_FILTER_COUNT - 1);
    options.filter_strength = SDL_clamp(options.filter_strength, 0, 100);
    options.screen_percent = SDL_clamp(options.screen_percent, 25, 100);
    options.screen_width_percent = SDL_clamp(options.screen_width_percent, 25, 200);
    options.screen_height_percent = SDL_clamp(options.screen_height_percent, 25, 200);
    options.aspect = SDL_clamp(options.aspect, IOS_ASPECT_4_3, IOS_ASPECT_FILL);
    options.stick_sensitivity = SDL_clamp(options.stick_sensitivity, 1, 100);
    options.stick_deadzone = SDL_clamp(options.stick_deadzone, 0, 35);
    current = options;
}

const char* IOSOptions_FilterName(int filter) {
    static const char* names[] = {
        "Off", "Sharp Bilinear", "CRT zfast", "CRT Lottes",
        "CRT Caligari", "CRT EasyMode", "Composite TV",
        "CRT Aperture", "CRT Geom", "CRT Hyllian"
    };
    return names[SDL_clamp(filter, 0, IOS_FILTER_COUNT - 1)];
}

SDL_Rect IOSOptions_Viewport(SDL_Rect available) {
    if (available.w <= 0 || available.h <= 0) return (SDL_Rect) { available.x, available.y, 0, 0 };
    SDL_Rect result = available;
    if (current.aspect != IOS_ASPECT_FILL && available.w > 0 && available.h > 0) {
        const float ratio = current.aspect == IOS_ASPECT_NATIVE ? 384.0f / 224.0f : 4.0f / 3.0f;
        result.h = (int)((float)result.w / ratio);
        if (result.h > available.h) {
            result.h = available.h;
            result.w = (int)((float)result.h * ratio);
        }
    }
    // Independent axes allow stretching, shrinking and centered zoom beyond
    // the fitted aspect ratio. The render target clips zoomed edges naturally.
    result.w = SDL_max(1, (int)((Sint64)result.w * current.screen_percent * current.screen_width_percent / 10000));
    result.h = SDL_max(1, (int)((Sint64)result.h * current.screen_percent * current.screen_height_percent / 10000));
    result.x = available.x + (available.w - result.w) / 2;
    result.y = available.y + (available.h - result.h) / 2;
    return result;
}

static void adjust_normalized_stick(float* x, float* y) {
    const float fx = *x;
    const float fy = *y;
    if (!isfinite(fx) || !isfinite(fy)) {
        *x = *y = 0.0f;
        return;
    }
    const float magnitude = sqrtf(fx * fx + fy * fy);
    const float deadzone = (float)current.stick_deadzone / 100.0f;
    if (magnitude <= deadzone) {
        *x = *y = 0.0f;
        return;
    }
    // Physical directions activate at 50% output: 1% sensitivity needs 90%
    // throw; 100% needs 10%. Touch's 25% output threshold preserves its smaller
    // activation radius. Both share the curve and retain full deflection.
    const float sensitivity = (float)(current.stick_sensitivity - 1) / 99.0f;
    const float threshold = 0.9f - 0.8f * sensitivity;
    const float normalized = SDL_clamp((magnitude - deadzone) / (1.0f - deadzone), 0.0f, 1.0f);
    const float response = normalized <= threshold
        ? 0.5f * normalized / threshold
        : 0.5f + 0.5f * (normalized - threshold) / (1.0f - threshold);
    const float scale = response / magnitude;
    *x = SDL_clamp(fx * scale, -1.0f, 1.0f);
    *y = SDL_clamp(fy * scale, -1.0f, 1.0f);
}

void IOSOptions_AdjustTouchStick(float* x, float* y) {
    adjust_normalized_stick(x, y);
}

void IOSOptions_AdjustStick(Sint16* x, Sint16* y) {
    float fx = (float)*x / (*x < 0 ? 32768.0f : 32767.0f);
    float fy = (float)*y / (*y < 0 ? 32768.0f : 32767.0f);
    adjust_normalized_stick(&fx, &fy);
    const int rx = (int)roundf(fx * 32768.0f);
    const int ry = (int)roundf(fy * 32768.0f);
    *x = (Sint16)SDL_clamp(rx, -32768, 32767);
    *y = (Sint16)SDL_clamp(ry, -32768, 32767);
}
#endif
