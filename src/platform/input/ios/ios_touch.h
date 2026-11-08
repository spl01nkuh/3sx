#ifndef IOS_TOUCH_H
#define IOS_TOUCH_H

#include "core/input.h"
#include "platform/input/ios/ios_layout.h"

// These functions run on the UIKit/SDL main thread.
bool IOSTouch_Init(SDL_Window* window);
void IOSTouch_Quit(void);
void IOSTouch_Reset(void);
void IOSTouch_GetButtonState(Input_ButtonState* state);
void IOSTouch_RefreshOptions(void);
void IOSTouch_EditLayout(void);
void IOSTouch_RecordActivity(void);
IOSLayout_DirectionStyle IOSTouch_GetDirectionStyle(void);
void IOSTouch_SetDirectionStyle(IOSLayout_DirectionStyle style);
const char* IOSTouch_DirectionStyleName(int style);

#endif
