#ifndef IOS_FILTER_FRAME_H
#define IOS_FILTER_FRAME_H

#include <SDL3/SDL.h>

// Main thread only, while the options menu has paused simulation. Returns the
// last rendered game canvas in RGBA32; the caller owns and destroys the surface.
SDL_Surface* IOSFilter_CopyGameFrame(void);

#endif
