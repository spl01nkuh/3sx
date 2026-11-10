#if CRS_PLATFORM_IOS

#import "platform/app/ios/ios_stick_preview.h"

#include "platform/app/ios/ios_options.h"
#include "platform/input/ios/ios_layout.h"
#include "platform/input/ios/ios_touch.h"
#include "platform/input/ios/ios_touch_state.h"
#include "platform/input/sdl/sdl_pad.h"
#include <math.h>

static NSString* directionName(uint16_t directions) {
    BOOL up = (directions & IOS_TOUCH_UP) != 0;
    BOOL down = (directions & IOS_TOUCH_DOWN) != 0;
    BOOL left = (directions & IOS_TOUCH_LEFT) != 0;
    BOOL right = (directions & IOS_TOUCH_RIGHT) != 0;
    if (up && left) return @"↖ Up-left";
    if (up && right) return @"↗ Up-right";
    if (down && left) return @"↙ Down-left";
    if (down && right) return @"↘ Down-right";
    if (up) return @"↑ Up";
    if (down) return @"↓ Down";
    if (left) return @"← Left";
    if (right) return @"→ Right";
    return @"Neutral";
}

static uint16_t buttonDirections(Input_ButtonState state) {
    return (state.dpad_up ? IOS_TOUCH_UP : 0) |
           (state.dpad_down ? IOS_TOUCH_DOWN : 0) |
           (state.dpad_left ? IOS_TOUCH_LEFT : 0) |
           (state.dpad_right ? IOS_TOUCH_RIGHT : 0);
}

static float normalizedAxis(Sint16 axis) {
    return (float)axis / (axis < 0 ? 32768.0f : 32767.0f);
}

@interface ThreeSXStickCircle : UIView
@property(nonatomic) CGPoint rawPoint;
@property(nonatomic) CGPoint tunedPoint;
@property(nonatomic) BOOL acceptsTouch;
@property(nonatomic, copy) void (^changed)(CGPoint point);
- (void)resetTouch;
@end

@implementation ThreeSXStickCircle
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.multipleTouchEnabled = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"Stick position";
    }
    return self;
}
- (void)setRawPoint:(CGPoint)point { _rawPoint = point; [self setNeedsDisplay]; }
- (void)setTunedPoint:(CGPoint)point { _tunedPoint = point; [self setNeedsDisplay]; }
- (CGFloat)circleRadius { return MAX(1.0, MIN(self.bounds.size.width, self.bounds.size.height) / 2.0 - 12.0); }
- (CGPoint)circleCenter { return CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)); }
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat radius = [self circleRadius];
    CGPoint center = [self circleCenter];
    CGRect circle = CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2);
    UIBezierPath* outer = [UIBezierPath bezierPathWithOvalInRect:circle];
    [[UIColor tertiarySystemFillColor] setFill];
    [outer fill];
    [[UIColor secondaryLabelColor] setStroke];
    outer.lineWidth = 1.5;
    [outer stroke];
    UIBezierPath* axes = [UIBezierPath bezierPath];
    [axes moveToPoint:CGPointMake(center.x - radius, center.y)];
    [axes addLineToPoint:CGPointMake(center.x + radius, center.y)];
    [axes moveToPoint:CGPointMake(center.x, center.y - radius)];
    [axes addLineToPoint:CGPointMake(center.x, center.y + radius)];
    [[UIColor separatorColor] setStroke];
    axes.lineWidth = 1;
    [axes stroke];
    // Blue is the physical/finger position, orange is its tuned response.
    CGPoint raw = CGPointMake(center.x + self.rawPoint.x * radius, center.y + self.rawPoint.y * radius);
    CGPoint tuned = CGPointMake(center.x + self.tunedPoint.x * radius, center.y + self.tunedPoint.y * radius);
    [[UIColor systemBlueColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(raw.x - 10, raw.y - 10, 20, 20)] fill];
    [[UIColor systemOrangeColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(tuned.x - 4, tuned.y - 4, 8, 8)] fill];
}
- (void)readTouch:(UITouch*)touch {
    CGPoint point = [touch locationInView:self];
    CGPoint center = [self circleCenter];
    CGFloat radius = [self circleRadius];
    point = CGPointMake((point.x - center.x) / radius, (point.y - center.y) / radius);
    CGFloat length = hypot(point.x, point.y);
    if (length > 1) point = CGPointMake(point.x / length, point.y / length);
    self.rawPoint = point;
    if (self.changed) self.changed(point);
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    if (self.acceptsTouch) [self readTouch:touches.anyObject];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    if (self.acceptsTouch) [self readTouch:touches.anyObject];
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)touches; (void)event;
    if (self.acceptsTouch) [self resetTouch];
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}
- (void)resetTouch {
    self.rawPoint = CGPointZero;
    self.tunedPoint = CGPointZero;
    if (self.changed) self.changed(CGPointZero);
}
@end

@interface ThreeSXPreviewScrollView : UIScrollView
@end
@implementation ThreeSXPreviewScrollView
- (BOOL)touchesShouldCancelInContentView:(UIView*)view {
    // A vertical stick motion must remain a test input instead of becoming a
    // scroll gesture. Scrolling still works when started elsewhere on the page.
    if ([view isKindOfClass:ThreeSXStickCircle.class]) return NO;
    return [super touchesShouldCancelInContentView:view];
}
@end

@interface ThreeSXStickPreviewController () {
    NSTimer* _timer;
    UILabel* _sensitivityLabel;
    UILabel* _controllerName;
    UILabel* _physicalAxes;
    UILabel* _physicalDirection;
    UILabel* _touchValues;
    UILabel* _touchDirection;
    ThreeSXStickCircle* _leftCircle;
    ThreeSXStickCircle* _rightCircle;
    ThreeSXStickCircle* _touchCircle;
    UISegmentedControl* _touchStyle;
    CGPoint _touchRaw;
}
@end

@implementation ThreeSXStickPreviewController

- (UILabel*)label:(NSString*)text style:(UIFontTextStyle)style {
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    return label;
}
- (UIStackView*)verticalStack {
    UIStackView* stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    return stack;
}
- (UIView*)panelWithContent:(UIStackView*)content {
    UIView* panel = [[UIView alloc] init];
    panel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    panel.layer.cornerRadius = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [content.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [content.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [content.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12]
    ]];
    return panel;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Test Sticks";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UIScrollView* scroll = [[ThreeSXPreviewScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.delaysContentTouches = NO;
    [self.view addSubview:scroll];
    UIStackView* content = [self verticalStack];
    content.spacing = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:12],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-12],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-24]
    ]];
    _sensitivityLabel = [self label:@"" style:UIFontTextStyleHeadline];
    [content addArrangedSubview:_sensitivityLabel];
    UISlider* sensitivity = [[UISlider alloc] init];
    sensitivity.minimumValue = 1;
    sensitivity.maximumValue = 100;
    sensitivity.value = IOSOptions_Get()->stick_sensitivity;
    sensitivity.accessibilityLabel = @"Stick sensitivity";
    sensitivity.accessibilityValue = [NSString stringWithFormat:@"%d of 100", IOSOptions_Get()->stick_sensitivity];
    [sensitivity addTarget:self action:@selector(sensitivityChanged:) forControlEvents:UIControlEventValueChanged];
    [content addArrangedSubview:sensitivity];
    [content addArrangedSubview:[self label:
        @"Full throw always gives the game's fixed digital movement speed. Sensitivity changes how far you move the stick before a direction activates."
        style:UIFontTextStyleFootnote]];

    UIStackView* panels = [[UIStackView alloc] init];
    panels.axis = UILayoutConstraintAxisHorizontal;
    panels.alignment = UIStackViewAlignmentTop;
    panels.distribution = UIStackViewDistributionFillEqually;
    panels.spacing = 12;
    [content addArrangedSubview:panels];

    UIStackView* hardware = [self verticalStack];
    [hardware addArrangedSubview:[self label:@"Physical controller" style:UIFontTextStyleHeadline]];
    _controllerName = [self label:@"No controller connected" style:UIFontTextStyleSubheadline];
    [hardware addArrangedSubview:_controllerName];
    UIStackView* sticks = [[UIStackView alloc] init];
    sticks.axis = UILayoutConstraintAxisHorizontal;
    sticks.distribution = UIStackViewDistributionFillEqually;
    sticks.spacing = 4;
    [hardware addArrangedSubview:sticks];
    NSArray<NSString*>* names = @[ @"Left stick", @"Right stick" ];
    for (NSUInteger index = 0; index < names.count; index++) {
        UIStackView* column = [self verticalStack];
        UILabel* title = [self label:names[index] style:UIFontTextStyleCaption1];
        title.textAlignment = NSTextAlignmentCenter;
        [column addArrangedSubview:title];
        ThreeSXStickCircle* circle = [[ThreeSXStickCircle alloc] initWithFrame:CGRectZero];
        circle.userInteractionEnabled = NO;
        circle.accessibilityLabel = names[index];
        [column addArrangedSubview:circle];
        [circle.heightAnchor constraintEqualToAnchor:circle.widthAnchor].active = YES;
        if (index == 0) _leftCircle = circle; else _rightCircle = circle;
        [sticks addArrangedSubview:column];
    }
    _physicalAxes = [self label:@"" style:UIFontTextStyleCaption1];
    _physicalAxes.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    [hardware addArrangedSubview:_physicalAxes];
    _physicalDirection = [self label:@"Game direction: Neutral" style:UIFontTextStyleSubheadline];
    [hardware addArrangedSubview:_physicalDirection];
    [hardware addArrangedSubview:[self label:@"Blue: raw position · Orange: tuned response. D-pad takes priority, then left stick, then right stick."
                                        style:UIFontTextStyleCaption1]];
    [panels addArrangedSubview:[self panelWithContent:hardware]];

    UIStackView* touch = [self verticalStack];
    [touch addArrangedSubview:[self label:@"Touch test" style:UIFontTextStyleHeadline]];
    [touch addArrangedSubview:[self label:@"Drag the blue thumb. This preview never controls the game." style:UIFontTextStyleCaption1]];
    _touchStyle = [[UISegmentedControl alloc] initWithItems:@[ @"Normal", @"Hybrid", @"D-pad" ]];
    IOSLayout_DirectionStyle style = IOSTouch_GetDirectionStyle();
    _touchStyle.selectedSegmentIndex = style == IOS_LAYOUT_STICK ? 0 : style == IOS_LAYOUT_HYBRID ? 1 : 2;
    _touchStyle.accessibilityLabel = @"Touch preview style";
    [_touchStyle addTarget:self action:@selector(touchStyleChanged:) forControlEvents:UIControlEventValueChanged];
    [touch addArrangedSubview:_touchStyle];
    _touchCircle = [[ThreeSXStickCircle alloc] initWithFrame:CGRectZero];
    _touchCircle.acceptsTouch = YES;
    _touchCircle.accessibilityLabel = @"Touch stick test. Drag to test direction activation.";
    [touch addArrangedSubview:_touchCircle];
    [_touchCircle.heightAnchor constraintEqualToConstant:160].active = YES;
    __weak ThreeSXStickPreviewController* weakSelf = self;
    _touchCircle.changed = ^(CGPoint point) {
        ThreeSXStickPreviewController* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_touchRaw = point;
        [strongSelf refreshTouch];
    };
    _touchValues = [self label:@"" style:UIFontTextStyleCaption1];
    _touchValues.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    [touch addArrangedSubview:_touchValues];
    _touchDirection = [self label:@"Direction: Neutral" style:UIFontTextStyleSubheadline];
    [touch addArrangedSubview:_touchDirection];
    [touch addArrangedSubview:[self label:@"Normal and Hybrid use your sensitivity and dead zone. D-pad uses a fixed grid and ignores both settings. Preview style does not change your layout."
                                     style:UIFontTextStyleCaption1]];
    [panels addArrangedSubview:[self panelWithContent:touch]];
    [self refreshLabels];
    [self refreshTouch];
    [self pollController];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    __weak ThreeSXStickPreviewController* weakSelf = self;
    [_timer invalidate];
    _timer = [NSTimer timerWithTimeInterval:1.0 / 15.0 repeats:YES block:^(NSTimer* timer) {
        (void)timer;
        [weakSelf pollController];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
    [_touchCircle resetTouch];
}
- (void)dealloc {
    [_timer invalidate];
}
- (void)refreshLabels {
    const IOSOptions* options = IOSOptions_Get();
    _sensitivityLabel.text = [NSString stringWithFormat:@"Sensitivity: %d / 100 · Dead zone: %d%%",
        options->stick_sensitivity, options->stick_deadzone];
}
- (void)sensitivityChanged:(UISlider*)slider {
    IOSOptions options = *IOSOptions_Get();
    options.stick_sensitivity = (int)lroundf(slider.value);
    slider.value = options.stick_sensitivity;
    slider.accessibilityValue = [NSString stringWithFormat:@"%d of 100", options.stick_sensitivity];
    IOSOptions_Apply(options);
    IOSOptions_Save();
    [self refreshLabels];
    [self refreshTouch];
    [self pollController];
}
- (void)touchStyleChanged:(UISegmentedControl*)control {
    (void)control;
    [self refreshTouch];
}
- (void)refreshTouch {
    IOSLayout_DirectionStyle style = _touchStyle.selectedSegmentIndex == 0 ? IOS_LAYOUT_STICK
        : _touchStyle.selectedSegmentIndex == 1 ? IOS_LAYOUT_HYBRID : IOS_LAYOUT_DPAD;
    float x = (float)_touchRaw.x;
    float y = (float)_touchRaw.y;
    if (style != IOS_LAYOUT_DPAD) IOSOptions_AdjustTouchStick(&x, &y);
    uint16_t directions = IOSLayout_Directions(style, x, y);
    _touchCircle.tunedPoint = CGPointMake(x, y);
    _touchValues.text = [NSString stringWithFormat:@"Raw:   X %+.2f  Y %+.2f\nTuned: X %+.2f  Y %+.2f",
        _touchRaw.x, _touchRaw.y, x, y];
    _touchDirection.text = [@"Direction: " stringByAppendingString:directionName(directions)];
    _touchCircle.accessibilityValue = [NSString stringWithFormat:@"Raw X %.2f Y %.2f. %@",
        _touchRaw.x, _touchRaw.y, directionName(directions)];
}
- (void)pollController {
    SDLPad_StickPreview preview;
    BOOL connected = SDLPad_GetStickPreview(0, &preview) || SDLPad_GetStickPreview(1, &preview);
    if (!connected) {
        _controllerName.text = @"No controller connected";
        _physicalAxes.text = @"Pair a controller to see its raw axes.";
        _physicalDirection.text = @"Game direction: Neutral";
        _leftCircle.rawPoint = _leftCircle.tunedPoint = CGPointZero;
        _rightCircle.rawPoint = _rightCircle.tunedPoint = CGPointZero;
        _leftCircle.accessibilityValue = _rightCircle.accessibilityValue = @"No controller connected";
        return;
    }
    _controllerName.text = preview.name ? [NSString stringWithUTF8String:preview.name] : @"Connected controller";
    _leftCircle.rawPoint = CGPointMake(normalizedAxis(preview.raw.left_stick_x), normalizedAxis(preview.raw.left_stick_y));
    _leftCircle.tunedPoint = CGPointMake(normalizedAxis(preview.tuned.left_stick_x), normalizedAxis(preview.tuned.left_stick_y));
    _rightCircle.rawPoint = CGPointMake(normalizedAxis(preview.raw.right_stick_x), normalizedAxis(preview.raw.right_stick_y));
    _rightCircle.tunedPoint = CGPointMake(normalizedAxis(preview.tuned.right_stick_x), normalizedAxis(preview.tuned.right_stick_y));
    _physicalAxes.text = [NSString stringWithFormat:@"Raw L: X %+6d Y %+6d%@\nRaw R: X %+6d Y %+6d%@\nTuned L: %+.2f %+.2f\nTuned R: %+.2f %+.2f",
        (int)preview.raw.left_stick_x, (int)preview.raw.left_stick_y, preview.has_left_stick ? @"" : @" (unavailable)",
        (int)preview.raw.right_stick_x, (int)preview.raw.right_stick_y, preview.has_right_stick ? @"" : @" (unavailable)",
        _leftCircle.tunedPoint.x, _leftCircle.tunedPoint.y, _rightCircle.tunedPoint.x, _rightCircle.tunedPoint.y];
    NSString* direction = directionName(buttonDirections(preview.tuned));
    _physicalDirection.text = [@"Game direction: " stringByAppendingString:direction];
    _leftCircle.accessibilityValue = [NSString stringWithFormat:@"Raw X %d Y %d. Game direction %@",
        (int)preview.raw.left_stick_x, (int)preview.raw.left_stick_y, direction];
    _rightCircle.accessibilityValue = [NSString stringWithFormat:@"Raw X %d Y %d. Game direction %@",
        (int)preview.raw.right_stick_x, (int)preview.raw.right_stick_y, direction];
}
@end

#endif
