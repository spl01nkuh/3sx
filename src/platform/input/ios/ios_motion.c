#if CRS_PLATFORM_IOS

#include "platform/input/ios/ios_motion.h"
#include "platform/input/ios/ios_touch_state.h"

#include <stddef.h>

#define UP IOS_TOUCH_UP
#define DOWN IOS_TOUCH_DOWN
#define LEFT IOS_TOUCH_LEFT
#define RIGHT IOS_TOUCH_RIGHT

// Screen-relative defaults. Mirror swaps left/right for the entire sequence;
// it never changes the final attack binding.
static const uint16_t qcf[] = { DOWN, DOWN | RIGHT, RIGHT };
static const uint16_t qcb[] = { DOWN, DOWN | LEFT, LEFT };
static const uint16_t left_down[] = { LEFT, LEFT | DOWN, DOWN };
static const uint16_t dp_forward[] = { RIGHT, DOWN, DOWN | RIGHT };
static const uint16_t dp_backward[] = { LEFT, DOWN, DOWN | LEFT };
static const uint16_t full360[] = {
    RIGHT, DOWN | RIGHT, DOWN, DOWN | LEFT, LEFT, UP | LEFT, UP, UP | RIGHT
};
static const uint16_t half_forward[] = { LEFT, DOWN | LEFT, DOWN, DOWN | RIGHT, RIGHT };
static const uint16_t half_backward[] = { RIGHT, DOWN | RIGHT, DOWN, DOWN | LEFT, LEFT };

typedef struct MotionSequence {
    const uint16_t* directions;
    unsigned count;
    const char* name;
} MotionSequence;

#define SEQUENCE(directions_, name_) { directions_, sizeof(directions_) / sizeof((directions_)[0]), name_ }
static const MotionSequence sequences[IOS_MOTION_COUNT] = {
    [IOS_MOTION_NONE] = { NULL, 0, "None" },
    [IOS_MOTION_QCF] = SEQUENCE(qcf, "Quarter circle forward (↓ ↘ →)"),
    [IOS_MOTION_QCB] = SEQUENCE(qcb, "Quarter circle back (↓ ↙ ←)"),
    [IOS_MOTION_LEFT_DOWN] = SEQUENCE(left_down, "Left to down (← ↙ ↓)"),
    [IOS_MOTION_DP_FORWARD] = SEQUENCE(dp_forward, "Dragon punch forward (→ ↓ ↘)"),
    [IOS_MOTION_DP_BACKWARD] = SEQUENCE(dp_backward, "Dragon punch back (← ↓ ↙)"),
    [IOS_MOTION_FULL360] = SEQUENCE(full360, "Full circle (360°)"),
    [IOS_MOTION_HALF_FORWARD] = SEQUENCE(half_forward, "Half circle forward (← ↙ ↓ ↘ →)"),
    [IOS_MOTION_HALF_BACKWARD] = SEQUENCE(half_backward, "Half circle back (→ ↘ ↓ ↙ ←)"),
};

#undef SEQUENCE
#undef UP
#undef DOWN
#undef LEFT
#undef RIGHT

enum MotionPhase { MOTION_DIRECTION, MOTION_GAP, MOTION_FINISH };
enum { DIRECTION_FRAMES = 2, NEUTRAL_FRAMES = 1, FINISH_FRAMES = 2 };

static bool valid_motion(IOSMotion_ID motion) {
    return motion > IOS_MOTION_NONE && motion < IOS_MOTION_COUNT;
}

void IOSMotion_Cancel(IOSMotion_State* state) {
    if (state != NULL) {
        *state = (IOSMotion_State) { 0 };
    }
}

bool IOSMotion_Start(IOSMotion_State* state, IOSMotion_ID motion, bool mirror, uint16_t finish_binding) {
    if (state == NULL) {
        return false;
    }
    IOSMotion_Cancel(state);
    if (!valid_motion(motion)) {
        return false;
    }
    // A finish binding can contain any attack chord, Select or Start. Ignore
    // stray direction bits from damaged preferences instead of holding them.
    const uint16_t buttons = IOS_TOUCH_LP | IOS_TOUCH_MP | IOS_TOUCH_HP |
                             IOS_TOUCH_LK | IOS_TOUCH_MK | IOS_TOUCH_HK |
                             IOS_TOUCH_SELECT | IOS_TOUCH_START;
    *state = (IOSMotion_State) {
        .active = true,
        .mirror = mirror,
        .motion = motion,
        .finish_binding = finish_binding & buttons,
        .phase = MOTION_DIRECTION,
        .remaining = DIRECTION_FRAMES,
    };
    return true;
}

static uint16_t mirrored(uint16_t direction) {
    uint16_t result = direction & ~(IOS_TOUCH_LEFT | IOS_TOUCH_RIGHT);
    if (direction & IOS_TOUCH_LEFT) result |= IOS_TOUCH_RIGHT;
    if (direction & IOS_TOUCH_RIGHT) result |= IOS_TOUCH_LEFT;
    return result;
}

uint16_t IOSMotion_Tick(IOSMotion_State* state) {
    if (state == NULL || !state->active) {
        return 0;
    }
    if (!valid_motion(state->motion) || state->phase > MOTION_FINISH || state->remaining == 0) {
        IOSMotion_Cancel(state);
        return 0;
    }
    const MotionSequence* sequence = &sequences[state->motion];
    if (state->index >= sequence->count) {
        IOSMotion_Cancel(state);
        return 0;
    }
    uint16_t result = 0;
    if (state->phase != MOTION_GAP) {
        result = sequence->directions[state->index];
        if (state->mirror) result = mirrored(result);
        if (state->phase == MOTION_FINISH) result |= state->finish_binding;
    }
    // The 360 parser has collected all four cardinals on the exact Up step.
    // Press there and hold through the rest of the rotation to reduce the delay
    // after Up starts a jump, without introducing a second press edge.
    if (state->motion == IOS_MOTION_FULL360 && state->index >= 6) result |= state->finish_binding;
    state->remaining--;
    if (state->remaining == 0) {
        if (state->phase == MOTION_FINISH) {
            IOSMotion_Cancel(state);
        } else if (state->phase == MOTION_GAP) {
            state->index++;
            state->phase = MOTION_DIRECTION;
            state->remaining = DIRECTION_FRAMES;
        } else if (state->index + 1 == sequence->count) {
            state->phase = MOTION_FINISH;
            state->remaining = FINISH_FRAMES;
        } else {
            state->phase = MOTION_GAP;
            state->remaining = NEUTRAL_FRAMES;
        }
    }
    return result;
}

const char* IOSMotion_Name(IOSMotion_ID motion) {
    if (motion < IOS_MOTION_NONE || motion >= IOS_MOTION_COUNT) {
        return sequences[IOS_MOTION_NONE].name;
    }
    return sequences[motion].name;
}

#endif
