#if CRS_INPUT_DRIVER_SDL

#ifndef SDL_PAD_H
#define SDL_PAD_H

#include "core/input.h"

#include <SDL3/SDL.h>

#include <stdbool.h>

// Internal

void SDLPad_Init();
void SDLPad_HandleGamepadDeviceEvent(const SDL_GamepadDeviceEvent* event);

// Public

bool SDLPad_IsGamepadConnected(int id);
void SDLPad_GetButtonState(int id, Input_ButtonState* state);
Input_PadType SDLPad_GetPadType(int id);
void SDLPad_RumblePad(int id, bool low_freq_enabled, Uint8 high_freq_rumble);

#if CRS_PLATFORM_IOS
typedef struct SDLPad_StickPreview {
    const char* name; // Owned by SDL, valid while this controller remains open.
    bool has_left_stick;
    bool has_right_stick;
    Input_ButtonState raw;
    Input_ButtonState tuned;
} SDLPad_StickPreview;

// Poll a connected physical controller while the game is paused in options.
// Touch and keyboard input are excluded so hardware mappings remain visible.
bool SDLPad_GetStickPreview(int id, SDLPad_StickPreview* preview);
#endif

#endif

#endif // CRS_INPUT_DRIVER_SDL
