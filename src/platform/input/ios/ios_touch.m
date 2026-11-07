#if CRS_PLATFORM_IOS

#import <UIKit/UIKit.h>

#include "platform/input/ios/ios_touch.h"
#include "platform/input/ios/ios_touch_state.h"
#include "platform/app/ios/ios_options.h"

// Keep UIKit controls above the SDL Metal view. Each finger is tracked separately
// so directions, chords and sliding between attacks work without keyboard events.
@interface ThreeSXTouchView : UIView {
    NSMapTable<UITouch*, NSValue*>* _points;
    CGRect _dpad;
    CGRect _attacks[6];
    CGRect _selectButton;
    CGRect _startButton;
    Input_ButtonState _buttons;
}
- (void)resetTouches;
- (Input_ButtonState)buttonState;
@end

@implementation ThreeSXTouchView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        self.exclusiveTouch = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _points = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    CGFloat scale = MIN(1.25, MIN(CGRectGetWidth(safe) / 740.0, CGRectGetHeight(safe) / 320.0));
    scale = MAX(0.55, scale);
    CGFloat margin = 14.0 * scale;
    CGFloat diameter = 156.0 * scale;
    _dpad = CGRectMake(CGRectGetMinX(safe) + margin,
                       CGRectGetMaxY(safe) - margin - diameter, diameter, diameter);

    CGFloat button = 54.0 * scale;
    CGFloat gap = 10.0 * scale;
    CGFloat attacksX = CGRectGetMaxX(safe) - margin - 3.0 * button - 2.0 * gap;
    CGFloat attacksY = CGRectGetMaxY(safe) - margin - 2.0 * button - gap;
    for (int i = 0; i < 6; i++) {
        _attacks[i] = CGRectMake(attacksX + (i % 3) * (button + gap),
                                 attacksY + (i / 3) * (button + gap), button, button);
    }

    CGFloat menuWidth = 68.0 * scale;
    CGFloat menuHeight = 30.0 * scale;
    CGFloat menuY = CGRectGetMaxY(safe) - margin - menuHeight;
    _selectButton = CGRectMake(CGRectGetMidX(safe) - menuWidth - gap / 2.0,
                               menuY, menuWidth, menuHeight);
    _startButton = CGRectMake(CGRectGetMidX(safe) + gap / 2.0,
                              menuY, menuWidth, menuHeight);
    // UIKit may reposition controls on a rotation. Release held inputs then.
    [self resetTouches];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    (void)event;
    if (!IOSOptions_Get()->touch_enabled || IOSOptions_IsOpen()) return NO;
    if (CGRectContainsPoint(_dpad, point) || CGRectContainsPoint(_selectButton, point) ||
        CGRectContainsPoint(_startButton, point)) {
        return YES;
    }
    for (int i = 0; i < 6; i++) {
        if (CGRectContainsPoint(_attacks[i], point)) {
            return YES;
        }
    }
    return NO;
}

- (void)rebuildState {
    uint16_t controls = 0;
    for (UITouch* touch in _points) {
        CGPoint point = [[_points objectForKey:touch] CGPointValue];
        if (CGRectContainsPoint(_dpad, point)) {
            CGFloat radius = CGRectGetWidth(_dpad) / 2.0;
            CGFloat x = (point.x - CGRectGetMidX(_dpad)) / radius;
            CGFloat y = (point.y - CGRectGetMidY(_dpad)) / radius;
            controls |= IOSTouchState_Directions((float)x, (float)y);
        }
        static const uint16_t attacks[] = {
            IOS_TOUCH_LP, IOS_TOUCH_MP, IOS_TOUCH_HP,
            IOS_TOUCH_LK, IOS_TOUCH_MK, IOS_TOUCH_HK
        };
        for (int i = 0; i < 6; i++) {
            if (CGRectContainsPoint(_attacks[i], point)) controls |= attacks[i];
        }
        if (CGRectContainsPoint(_selectButton, point)) controls |= IOS_TOUCH_SELECT;
        if (CGRectContainsPoint(_startButton, point)) controls |= IOS_TOUCH_START;
    }
    _buttons = IOSTouchState_Buttons(controls);
    [self setNeedsDisplay];
}

- (void)updateTouches:(NSSet<UITouch*>*)touches {
    for (UITouch* touch in touches) {
        [_points setObject:[NSValue valueWithCGPoint:[touch locationInView:self]] forKey:touch];
    }
    [self rebuildState];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self updateTouches:touches];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self updateTouches:touches];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    for (UITouch* touch in touches) {
        [_points removeObjectForKey:touch];
    }
    [self rebuildState];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)resetTouches {
    [_points removeAllObjects];
    SDL_zero(_buttons);
    [self setNeedsDisplay];
}

- (Input_ButtonState)buttonState {
    return _buttons;
}

- (void)drawControl:(CGRect)rect label:(NSString*)label pressed:(BOOL)pressed rounded:(BOOL)rounded {
    UIBezierPath* path = rounded
        ? [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:CGRectGetHeight(rect) / 2.0]
        : [UIBezierPath bezierPathWithOvalInRect:rect];
    UIColor* fill = pressed
        ? [UIColor colorWithRed:0.25 green:0.7 blue:1.0 alpha:0.65]
        : [UIColor colorWithWhite:0.08 alpha:0.45];
    [fill setFill];
    [path fill];
    [[UIColor colorWithWhite:1.0 alpha:0.55] setStroke];
    path.lineWidth = 1.5;
    [path stroke];

    CGFloat fontSize = MIN(18.0, CGRectGetHeight(rect) * 0.28);
    NSDictionary* attributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.9]
    };
    CGSize textSize = [label sizeWithAttributes:attributes];
    CGPoint textPoint = CGPointMake(CGRectGetMidX(rect) - textSize.width / 2.0,
                                    CGRectGetMidY(rect) - textSize.height / 2.0);
    [label drawAtPoint:textPoint withAttributes:attributes];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    [self drawControl:_dpad label:@"" pressed:NO rounded:NO];
    CGFloat cell = CGRectGetWidth(_dpad) / 3.0;
    CGRect up = CGRectMake(CGRectGetMinX(_dpad) + cell, CGRectGetMinY(_dpad), cell, cell);
    CGRect down = CGRectOffset(up, 0, 2.0 * cell);
    CGRect left = CGRectOffset(up, -cell, cell);
    CGRect right = CGRectOffset(up, cell, cell);
    [self drawControl:up label:@"▲" pressed:_buttons.dpad_up rounded:NO];
    [self drawControl:down label:@"▼" pressed:_buttons.dpad_down rounded:NO];
    [self drawControl:left label:@"◀" pressed:_buttons.dpad_left rounded:NO];
    [self drawControl:right label:@"▶" pressed:_buttons.dpad_right rounded:NO];

    NSString* labels[] = { @"LP", @"MP", @"HP", @"LK", @"MK", @"HK" };
    BOOL pressed[] = { _buttons.west, _buttons.north, _buttons.right_shoulder,
                       _buttons.south, _buttons.east, _buttons.right_trigger != 0 };
    for (int i = 0; i < 6; i++) {
        [self drawControl:_attacks[i] label:labels[i] pressed:pressed[i] rounded:NO];
    }
    [self drawControl:_selectButton label:@"SELECT" pressed:_buttons.back rounded:YES];
    [self drawControl:_startButton label:@"START" pressed:_buttons.start rounded:YES];
}
@end

static ThreeSXTouchView* touch_view;
static UIButton* options_button;

bool IOSTouch_Init(SDL_Window* window) {
    UIWindow* nativeWindow = (__bridge UIWindow*)SDL_GetPointerProperty(
        SDL_GetWindowProperties(window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
    UIView* parent = nativeWindow.rootViewController.view;
    if (!parent) {
        return SDL_SetError("Could not find the iOS game view for touch controls");
    }
    IOSTouch_Quit();
    touch_view = [[ThreeSXTouchView alloc] initWithFrame:parent.bounds];
    [parent addSubview:touch_view];
    [touch_view setNeedsLayout];
    [touch_view layoutIfNeeded];
    options_button = [UIButton buttonWithType:UIButtonTypeSystem];
    [options_button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    options_button.tintColor = UIColor.whiteColor;
    options_button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    options_button.layer.cornerRadius = 22;
    options_button.accessibilityLabel = @"iOS options";
    options_button.translatesAutoresizingMaskIntoConstraints = NO;
    [options_button addAction:[UIAction actionWithHandler:^(UIAction* action) {
        (void)action; IOSOptions_Present(window);
    }] forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:options_button];
    [NSLayoutConstraint activateConstraints:@[
        [options_button.topAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.topAnchor constant:8],
        [options_button.trailingAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [options_button.widthAnchor constraintEqualToConstant:44],
        [options_button.heightAnchor constraintEqualToConstant:44]
    ]];
    IOSTouch_RefreshOptions();
    return true;
}

void IOSTouch_Quit(void) {
    [options_button removeFromSuperview];
    options_button = nil;
    [touch_view resetTouches];
    [touch_view removeFromSuperview];
    touch_view = nil;
}

void IOSTouch_Reset(void) {
    [touch_view resetTouches];
}

void IOSTouch_GetButtonState(Input_ButtonState* state) {
    if (!state) {
        return;
    }
    SDL_zerop(state);
    if (touch_view && IOSOptions_Get()->touch_enabled && !IOSOptions_IsOpen()) {
        *state = [touch_view buttonState];
    }
}

void IOSTouch_RefreshOptions(void) {
    [touch_view resetTouches];
    touch_view.hidden = !IOSOptions_Get()->touch_enabled;
}

#endif
