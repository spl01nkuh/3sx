#ifndef IOS_TOUCH_H
#define IOS_TOUCH_H

#include "core/input.h"

// These functions run on the UIKit/SDL main thread.
bool IOSTouch_Init(SDL_Window* window);
void IOSTouch_Quit(void);
void IOSTouch_Reset(void);
void IOSTouch_GetButtonState(Input_ButtonState* state);
void IOSTouch_RefreshOptions(void);

#endif
