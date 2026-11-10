#ifndef IOS_MOTION_H
#define IOS_MOTION_H

#include <stdbool.h>
#include <stdint.h>

typedef enum IOSMotion_ID {
    IOS_MOTION_NONE,
    IOS_MOTION_QCF,
    IOS_MOTION_QCB,
    IOS_MOTION_LEFT_DOWN,
    IOS_MOTION_DP_FORWARD,
    IOS_MOTION_DP_BACKWARD,
    IOS_MOTION_FULL360,
    IOS_MOTION_HALF_FORWARD,
    IOS_MOTION_HALF_BACKWARD,
    IOS_MOTION_COUNT,
} IOSMotion_ID;

typedef struct IOSMotion_State {
    bool active;
    bool mirror;
    IOSMotion_ID motion;
    uint16_t finish_binding;
    unsigned index;
    unsigned phase;
    unsigned remaining;
} IOSMotion_State;

// Start once on touch-down. Starting again explicitly replaces the old motion.
// Invalid IDs cancel the state and return false.
bool IOSMotion_Start(IOSMotion_State* state, IOSMotion_ID motion, bool mirror, uint16_t finish_binding);
// Call exactly once per game frame. Each direction lasts two frames, separated
// by one neutral frame. The final direction is then held with the finish buttons
// for two frames; all later ticks are neutral until another explicit Start.
// For 360, finish buttons begin on exact Up and stay held through the remainder
// of the rotation, avoiding an extra delay after its four cardinals are entered.
uint16_t IOSMotion_Tick(IOSMotion_State* state);
void IOSMotion_Cancel(IOSMotion_State* state);
const char* IOSMotion_Name(IOSMotion_ID motion);

#endif
