#if CRS_PLATFORM_IOS

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

#include "platform/input/ios/ios_touch.h"
#include "platform/input/ios/ios_touch_state.h"
#include "platform/input/ios/ios_layout.h"
#include "platform/app/ios/ios_options.h"
#include <math.h>

static NSString* const layout_key = @"3sx.ios.touch-layout.v1";
static const NSInteger built_in_count = 9;
static const NSInteger custom_limit = 16;
static const uint16_t binding_mask = IOS_TOUCH_LP | IOS_TOUCH_MP | IOS_TOUCH_HP |
    IOS_TOUCH_LK | IOS_TOUCH_MK | IOS_TOUCH_HK | IOS_TOUCH_START | IOS_TOUCH_SELECT |
    IOS_TOUCH_UP | IOS_TOUCH_DOWN | IOS_TOUCH_LEFT | IOS_TOUCH_RIGHT;
static const uint16_t binding_choices[] = {
    IOS_TOUCH_LP, IOS_TOUCH_MP, IOS_TOUCH_HP, IOS_TOUCH_LK, IOS_TOUCH_MK, IOS_TOUCH_HK,
    IOS_TOUCH_START, IOS_TOUCH_SELECT, IOS_TOUCH_UP, IOS_TOUCH_DOWN, IOS_TOUCH_LEFT, IOS_TOUCH_RIGHT
};
static NSArray<NSString*>* bindingLabels(void) {
    return @[@"LP — light punch", @"MP — medium punch", @"HP — heavy punch",
             @"LK — light kick", @"MK — medium kick", @"HK — heavy kick",
             @"START", @"SELECT", @"Up", @"Down", @"Left", @"Right"];
}
static UIWindow* native_window;
static UIButton* options_button;
static NSTimer* options_timer;
static Uint64 last_touch_ms;
static BOOL editor_open;
static IOSLayout_DirectionStyle direction_style = IOS_LAYOUT_HYBRID;

@interface ThreeSXTouchItem : NSObject
@property(nonatomic, copy) NSString* label;
@property(nonatomic, assign) IOSLayout_Control control;
@end
@implementation ThreeSXTouchItem
@end

static NSMutableArray<ThreeSXTouchItem*>* layout_items;

static IOSLayout_Rect layoutRect(CGRect rect) {
    return (IOSLayout_Rect){ (float)rect.origin.x, (float)rect.origin.y,
                             (float)rect.size.width, (float)rect.size.height };
}
static CGRect nativeRect(IOSLayout_Rect rect) {
    return CGRectMake(rect.x, rect.y, rect.w, rect.h);
}
static CGRect safeRect(UIView* view) {
    return UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets);
}
static float savedNumber(NSDictionary* values, NSString* key, float fallback, float minimum, float maximum) {
    id value = values[key];
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    float number = [value floatValue];
    return isfinite(number) ? fminf(maximum, fmaxf(minimum, number)) : fallback;
}
static NSString* cleanLabel(NSString* label) {
    NSString* result = [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!result.length) return @"CUSTOM";
    __block NSUInteger count = 0, end = 0;
    [result enumerateSubstringsInRange:NSMakeRange(0, result.length)
        options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString* substring, NSRange range, NSRange enclosingRange, BOOL* stop) {
            (void)substring; (void)enclosingRange;
            end = NSMaxRange(range);
            if (++count == 10) *stop = YES;
        }];
    return [result substringToIndex:end];
}
static void saveLayout(void) {
    NSMutableArray* values = [NSMutableArray arrayWithCapacity:layout_items.count];
    for (ThreeSXTouchItem* item in layout_items) {
        IOSLayout_Control c = item.control;
        [values addObject:@{ @"x": @(c.center_x), @"y": @(c.center_y), @"size": @(c.size),
                             @"label": item.label, @"binding": @(c.binding) }];
    }
    [NSUserDefaults.standardUserDefaults setObject:@{ @"version": @1, @"items": values, @"directionStyle": @(direction_style) } forKey:layout_key];
}
static void defaultLayout(CGRect safe) {
    direction_style = IOS_LAYOUT_HYBRID;
    layout_items = [NSMutableArray array];
    NSArray<NSString*>* labels = @[@"Hybrid", @"LP", @"MP", @"HP", @"LK", @"MK", @"HK", @"SELECT", @"START"];
    for (NSInteger i = 0; i < built_in_count; i++) {
        ThreeSXTouchItem* item = [[ThreeSXTouchItem alloc] init];
        item.label = labels[i];
        item.control = IOSLayout_Default((int)i, layoutRect(safe));
        [layout_items addObject:item];
    }
}
static void loadLayout(CGRect safe) {
    defaultLayout(safe);
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:layout_key];
    if (![saved isKindOfClass:NSDictionary.class] || ![saved[@"version"] isEqual:@1]) return;
    direction_style = (IOSLayout_DirectionStyle)(int)savedNumber(saved, @"directionStyle", IOS_LAYOUT_HYBRID, 0,
        IOS_LAYOUT_DIRECTION_STYLE_COUNT - 1);
    layout_items[0].label = [NSString stringWithUTF8String:IOSTouch_DirectionStyleName(direction_style)];
    id values = saved[@"items"];
    if (![values isKindOfClass:NSArray.class]) return;
    NSInteger count = MIN((NSInteger)[values count], built_in_count + custom_limit);
    for (NSInteger i = 0; i < count; i++) {
        id value = values[i];
        if (![value isKindOfClass:NSDictionary.class]) continue;
        ThreeSXTouchItem* item;
        if (i < built_in_count) item = layout_items[i];
        else {
            id binding = value[@"binding"];
            if (![binding isKindOfClass:NSNumber.class] || !([binding unsignedIntValue] & binding_mask)) continue;
            item = [[ThreeSXTouchItem alloc] init];
            item.label = [value[@"label"] isKindOfClass:NSString.class] ? cleanLabel(value[@"label"]) : @"CUSTOM";
            item.control = (IOSLayout_Control){ .center_x = 0.5f, .center_y = 0.5f, .size = 1,
                .binding = (uint16_t)([binding unsignedIntValue] & binding_mask) };
            [layout_items addObject:item];
        }
        IOSLayout_Control c = item.control;
        c.center_x = savedNumber(value, @"x", c.center_x, 0, 1);
        c.center_y = savedNumber(value, @"y", c.center_y, 0, 1);
        c.size = savedNumber(value, @"size", 1, 0.55f, 2.0f);
        item.control = c;
    }
}

@class ThreeSXTouchView;
static ThreeSXTouchView* touch_view;
static void layoutChanged(void);

// This recognizer observes the window without taking ownership of gameplay or
// UIKit button gestures. It also sees touches when the overlay is disabled.
@interface ThreeSXActivityObserver : UIGestureRecognizer
@property(nonatomic, strong) NSHashTable<UITouch*>* contacts;
@end
@implementation ThreeSXActivityObserver
- (instancetype)init {
    self = [super initWithTarget:nil action:nil];
    if (self) {
        self.contacts = [NSHashTable weakObjectsHashTable];
        self.cancelsTouchesInView = NO;
        self.delaysTouchesBegan = NO;
        self.delaysTouchesEnded = NO;
        self.requiresExclusiveTouchType = NO;
    }
    return self;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer*)other { (void)other; return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer*)other { (void)other; return NO; }
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    for (UITouch* touch in touches) [self.contacts addObject:touch];
    IOSTouch_RecordActivity();
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)touches; (void)event; IOSTouch_RecordActivity();
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    for (UITouch* touch in touches) [self.contacts removeObject:touch];
    IOSTouch_RecordActivity();
    if (!self.contacts.count) self.state = UIGestureRecognizerStateFailed;
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}
- (void)reset { [super reset]; [self.contacts removeAllObjects]; }
@end
static ThreeSXActivityObserver* activity_observer;

// One shared model drives both the gameplay overlay and a paused layout canvas.
// Gameplay tracks every finger separately; editing never emits game input.
@interface ThreeSXTouchView : UIView {
    NSMapTable<UITouch*, NSValue*>* _points;
    NSHashTable<UITouch*>* _stickContacts;
    float _stickX, _stickY;
    Input_ButtonState _buttons;
    uint16_t _activeMask;
    NSInteger _dragIndex;
    IOSLayout_Control _dragStart;
}
@property(nonatomic, assign) BOOL editing;
@property(nonatomic, assign) NSInteger selected;
@property(nonatomic, copy) void (^openDetails)(NSInteger index);
- (void)resetTouches;
- (Input_ButtonState)buttonState;
- (void)refreshLayout;
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
        self.selected = NSNotFound;
        _dragIndex = NSNotFound;
        _points = [NSMapTable strongToStrongObjectsMapTable];
        _stickContacts = [NSHashTable weakObjectsHashTable];
    }
    return self;
}
- (void)setEditing:(BOOL)editing {
    _editing = editing;
    if (editing) {
        UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragControl:)];
        pan.maximumNumberOfTouches = 1;
        UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapControl:)];
        [tap requireGestureRecognizerToFail:pan];
        [self addGestureRecognizer:pan]; [self addGestureRecognizer:tap];
    }
}
- (CGRect)frameAtIndex:(NSInteger)index {
    return nativeRect(IOSLayout_Frame(layout_items[index].control, layoutRect(safeRect(self))));
}
- (NSInteger)indexAtPoint:(CGPoint)point {
    // Last drawn control wins when layouts overlap, matching the visual order.
    for (NSInteger i = (NSInteger)layout_items.count - 1; i >= 0; i--) {
        if (CGRectContainsPoint([self frameAtIndex:i], point)) return i;
    }
    return NSNotFound;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self resetTouches];
}
- (void)refreshLayout { [self resetTouches]; [self setNeedsDisplay]; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    (void)event;
    if (self.editing) return CGRectContainsPoint(self.bounds, point);
    if (!IOSOptions_Get()->touch_enabled || IOSOptions_IsOpen() || editor_open) return NO;
    return [self indexAtPoint:point] != NSNotFound;
}
- (void)rebuildState {
    uint16_t controls = 0;
    _stickX = _stickY = 0;
    for (UITouch* touch in _points) {
        CGPoint point = [[_points objectForKey:touch] CGPointValue];
        NSInteger index = direction_style == IOS_LAYOUT_STICK && [_stickContacts containsObject:touch]
            ? 0 : [self indexAtPoint:point];
        if (index == NSNotFound) continue;
        ThreeSXTouchItem* item = layout_items[index];
        if (item.control.dpad) {
            CGRect frame = [self frameAtIndex:index];
            CGFloat radius = CGRectGetWidth(frame) / 2.0;
            float x = (float)((point.x - CGRectGetMidX(frame)) / radius);
            float y = (float)((point.y - CGRectGetMidY(frame)) / radius);
            controls |= IOSLayout_Directions(direction_style, x, y);
            float length = fmaxf(1, hypotf(x, y));
            _stickX = x / length; _stickY = y / length;
        } else controls |= item.control.binding;
    }
    _activeMask = controls;
    _buttons = IOSTouchState_Buttons(controls);
    [self setNeedsDisplay];
}
- (void)updateTouches:(NSSet<UITouch*>*)touches {
    IOSTouch_RecordActivity();
    if (self.editing || IOSOptions_IsOpen() || editor_open) { [self resetTouches]; return; }
    for (UITouch* touch in touches) [_points setObject:[NSValue valueWithCGPoint:[touch locationInView:self]] forKey:touch];
    [self rebuildState];
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    if (!self.editing && direction_style == IOS_LAYOUT_STICK) {
        for (UITouch* touch in touches) {
            if ([self indexAtPoint:[touch locationInView:self]] == 0) [_stickContacts addObject:touch];
        }
    }
    [self updateTouches:touches];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { (void)event; [self updateTouches:touches]; }
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event; IOSTouch_RecordActivity();
    for (UITouch* touch in touches) { [_points removeObjectForKey:touch]; [_stickContacts removeObject:touch]; }
    [self rebuildState];
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self touchesEnded:touches withEvent:event]; }
- (void)resetTouches {
    [_points removeAllObjects]; [_stickContacts removeAllObjects];
    _stickX = _stickY = 0; SDL_zero(_buttons); _activeMask = 0; [self setNeedsDisplay];
}
- (Input_ButtonState)buttonState { return _buttons; }
- (void)tapControl:(UITapGestureRecognizer*)gesture {
    self.selected = [self indexAtPoint:[gesture locationInView:self]];
    [self setNeedsDisplay];
    if (self.selected != NSNotFound && self.openDetails) self.openDetails(self.selected);
}
- (void)dragControl:(UIPanGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint current = [gesture locationInView:self];
        CGPoint translation = [gesture translationInView:self];
        _dragIndex = [self indexAtPoint:CGPointMake(current.x - translation.x, current.y - translation.y)];
        self.selected = _dragIndex;
        if (_dragIndex != NSNotFound) _dragStart = layout_items[_dragIndex].control;
    }
    if (_dragIndex == NSNotFound) return;
    ThreeSXTouchItem* item = layout_items[_dragIndex];
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        CGPoint delta = [gesture translationInView:self];
        IOSLayout_Rect safe = layoutRect(safeRect(self));
        IOSLayout_Rect original = IOSLayout_Frame(_dragStart, safe);
        IOSLayout_Control moved = _dragStart;
        IOSLayout_Move(&moved, safe, original.x + original.w / 2 + (float)delta.x,
                       original.y + original.h / 2 + (float)delta.y);
        item.control = moved;
    } else if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        item.control = _dragStart;
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        _dragIndex = NSNotFound; saveLayout(); layoutChanged();
    }
    [self setNeedsDisplay];
}
- (void)drawControl:(CGRect)rect label:(NSString*)label pressed:(BOOL)pressed rounded:(BOOL)rounded selected:(BOOL)selected {
    UIBezierPath* path = rounded ? [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:CGRectGetHeight(rect) / 2.0]
        : [UIBezierPath bezierPathWithOvalInRect:rect];
    UIColor* fill = pressed ? [UIColor colorWithRed:0.25 green:0.7 blue:1 alpha:0.65]
        : [UIColor colorWithWhite:0.08 alpha:self.editing ? 0.8 : 0.45];
    [fill setFill]; [path fill];
    [(selected ? UIColor.systemYellowColor : [UIColor colorWithWhite:1 alpha:0.65]) setStroke];
    path.lineWidth = selected ? 3 : 1.5; [path stroke];
    CGFloat fontSize = MIN(18.0, CGRectGetHeight(rect) * 0.28);
    UIFont* font = [UIFont boldSystemFontOfSize:fontSize];
    CGFloat textWidth = [label sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    if (textWidth > rect.size.width - 6) font = [UIFont boldSystemFontOfSize:MAX(7, fontSize * (rect.size.width - 6) / textWidth)];
    NSDictionary* attributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.whiteColor };
    CGSize textSize = [label sizeWithAttributes:attributes];
    [label drawAtPoint:CGPointMake(CGRectGetMidX(rect) - textSize.width / 2, CGRectGetMidY(rect) - textSize.height / 2)
        withAttributes:attributes];
}
- (void)drawArrow:(NSString*)arrow inRect:(CGRect)rect pressed:(BOOL)pressed {
    if (pressed) {
        [[UIColor colorWithRed:0.25 green:0.7 blue:1 alpha:0.65] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 2, 2) cornerRadius:4] fill];
    }
    NSDictionary* attributes = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:MIN(18, rect.size.width * 0.34)],
        NSForegroundColorAttributeName: UIColor.whiteColor };
    CGSize size = [arrow sizeWithAttributes:attributes];
    [arrow drawAtPoint:CGPointMake(CGRectGetMidX(rect) - size.width / 2, CGRectGetMidY(rect) - size.height / 2)
        withAttributes:attributes];
}
- (void)drawDirectionControl:(CGRect)frame selected:(BOOL)selected {
    CGFloat cell = frame.size.width / 3;
    CGRect up = CGRectMake(frame.origin.x + cell, frame.origin.y, cell, cell);
    if (direction_style == IOS_LAYOUT_STICK) {
        [self drawControl:frame label:@"" pressed:NO rounded:NO selected:selected];
        UIBezierPath* ring = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(frame, frame.size.width * 0.14, frame.size.height * 0.14)];
        [[UIColor colorWithWhite:1 alpha:0.25] setStroke]; ring.lineWidth = 1; [ring stroke];
        CGFloat diameter = frame.size.width * 0.36;
        CGRect thumb = CGRectMake(CGRectGetMidX(frame) - diameter / 2 + _stickX * frame.size.width * 0.31,
                                  CGRectGetMidY(frame) - diameter / 2 + _stickY * frame.size.height * 0.31,
                                  diameter, diameter);
        BOOL pressed = _buttons.dpad_up || _buttons.dpad_down || _buttons.dpad_left || _buttons.dpad_right;
        [self drawControl:thumb label:@"" pressed:pressed rounded:NO selected:NO];
    } else if (direction_style == IOS_LAYOUT_DPAD) {
        CGFloat x = frame.origin.x, y = frame.origin.y;
        UIBezierPath* cross = [UIBezierPath bezierPath];
        [cross moveToPoint:CGPointMake(x + cell, y)];
        [cross addLineToPoint:CGPointMake(x + 2 * cell, y)];
        [cross addLineToPoint:CGPointMake(x + 2 * cell, y + cell)];
        [cross addLineToPoint:CGPointMake(x + 3 * cell, y + cell)];
        [cross addLineToPoint:CGPointMake(x + 3 * cell, y + 2 * cell)];
        [cross addLineToPoint:CGPointMake(x + 2 * cell, y + 2 * cell)];
        [cross addLineToPoint:CGPointMake(x + 2 * cell, y + 3 * cell)];
        [cross addLineToPoint:CGPointMake(x + cell, y + 3 * cell)];
        [cross addLineToPoint:CGPointMake(x + cell, y + 2 * cell)];
        [cross addLineToPoint:CGPointMake(x, y + 2 * cell)];
        [cross addLineToPoint:CGPointMake(x, y + cell)];
        [cross addLineToPoint:CGPointMake(x + cell, y + cell)]; [cross closePath];
        [[UIColor colorWithWhite:0.08 alpha:self.editing ? 0.8 : 0.55] setFill]; [cross fill];
        [(selected ? UIColor.systemYellowColor : [UIColor colorWithWhite:1 alpha:0.65]) setStroke];
        cross.lineWidth = selected ? 3 : 1.5; [cross stroke];
        [self drawArrow:@"▲" inRect:up pressed:_buttons.dpad_up];
        [self drawArrow:@"▼" inRect:CGRectOffset(up, 0, 2 * cell) pressed:_buttons.dpad_down];
        [self drawArrow:@"◀" inRect:CGRectOffset(up, -cell, cell) pressed:_buttons.dpad_left];
        [self drawArrow:@"▶" inRect:CGRectOffset(up, cell, cell) pressed:_buttons.dpad_right];
    } else {
        // Preserve the original hybrid circle with separate D-pad arrows.
        [self drawControl:frame label:@"" pressed:NO rounded:NO selected:selected];
        [self drawControl:up label:@"▲" pressed:_buttons.dpad_up rounded:NO selected:NO];
        [self drawControl:CGRectOffset(up, 0, 2 * cell) label:@"▼" pressed:_buttons.dpad_down rounded:NO selected:NO];
        [self drawControl:CGRectOffset(up, -cell, cell) label:@"◀" pressed:_buttons.dpad_left rounded:NO selected:NO];
        [self drawControl:CGRectOffset(up, cell, cell) label:@"▶" pressed:_buttons.dpad_right rounded:NO selected:NO];
    }
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    for (NSInteger i = 0; i < (NSInteger)layout_items.count; i++) {
        ThreeSXTouchItem* item = layout_items[i]; CGRect frame = [self frameAtIndex:i];
        BOOL selected = self.editing && self.selected == i;
        if (!item.control.dpad) {
            BOOL pressed = item.control.binding && (_activeMask & item.control.binding) == item.control.binding;
            [self drawControl:frame label:item.label pressed:pressed rounded:item.control.menu selected:selected];
        } else [self drawDirectionControl:frame selected:selected];
    }
}
@end

static void layoutChanged(void) { [touch_view refreshLayout]; }

@class ThreeSXLayoutController;
@interface ThreeSXControlDetails : UITableViewController
@property(nonatomic, strong) ThreeSXTouchItem* item;
@property(nonatomic, assign) BOOL custom;
@property(nonatomic, weak) ThreeSXLayoutController* editor;
@end
@interface ThreeSXControlList : UITableViewController
@property(nonatomic, weak) ThreeSXLayoutController* editor;
@end
@interface ThreeSXLayoutController : UIViewController
@property(nonatomic, strong) ThreeSXTouchView* canvas;
- (void)editIndex:(NSInteger)index;
- (void)refresh;
@end

@implementation ThreeSXControlDetails
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = self.item.label;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(done)];
}
- (void)done { [self.view endEditing:YES]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView { (void)tableView; return self.custom ? 3 : 1; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? (self.custom ? 4 : 3) : section == 1 ? 12 : 1;
}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"Control" : section == 1 ? @"Button binding" : nil;
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Drag in the layout editor, or use the position sliders to move a control hidden behind another. Changes save automatically.";
    if (section == 1) return @"Choose one button or a simultaneous combination. LP + MP + HP makes PPP; LK + MK + HK makes KKK. Attack labels use the game's default assignments.";
    return nil;
}
- (void)labelChanged:(UITextField*)field {
    self.item.label = cleanLabel(field.text); self.title = self.item.label; saveLayout(); [self.editor refresh];
}
- (void)controlChanged:(UISlider*)slider {
    IOSLayout_Control control = self.item.control;
    if (slider.tag == 0) control.size = slider.value;
    else if (slider.tag == 1) control.center_x = slider.value;
    else control.center_y = slider.value;
    self.item.control = control; saveLayout(); [self.editor refresh];
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    (void)tableView;
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (path.section == 0 && self.custom && path.row == 0) {
        cell.textLabel.text = @"Label";
        UITextField* label = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 160, 44)];
        label.text = self.item.label; label.textAlignment = NSTextAlignmentRight; label.placeholder = @"CUSTOM";
        label.autocorrectionType = UITextAutocorrectionTypeNo; label.clearButtonMode = UITextFieldViewModeWhileEditing;
        label.accessibilityLabel = @"Custom button label";
        [label addTarget:self action:@selector(labelChanged:) forControlEvents:UIControlEventEditingChanged];
        cell.accessoryView = label;
    } else if (path.section == 0) {
        NSInteger property = path.row - (self.custom ? 1 : 0);
        NSArray<NSString*>* names = @[@"Size", @"Horizontal position", @"Vertical position"];
        cell.textLabel.text = names[property]; cell.textLabel.numberOfLines = 2;
        UISlider* slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 180, 44)]; slider.tag = property;
        slider.minimumValue = property == 0 ? 0.55f : 0; slider.maximumValue = property == 0 ? 2 : 1;
        IOSLayout_Control c = self.item.control;
        slider.value = property == 0 ? c.size : property == 1 ? c.center_x : c.center_y;
        slider.accessibilityLabel = names[property];
        [slider addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
    } else if (path.section == 1) {
        cell.textLabel.text = bindingLabels()[path.row];
        cell.accessoryType = (self.item.control.binding & binding_choices[path.row]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else { cell.textLabel.text = @"Remove custom button"; cell.textLabel.textColor = UIColor.systemRedColor; }
    return cell;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) {
        IOSLayout_Control c = self.item.control; uint16_t changed = c.binding ^ binding_choices[path.row];
        if (!changed) {
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Choose at least one button"
                message:@"A custom button needs a button binding or a combination." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil]; return;
        }
        c.binding = changed; self.item.control = c; saveLayout(); [self.editor refresh]; [tableView reloadData];
    } else if (path.section == 2) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Remove this button?"
            message:self.item.label preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            (void)action; [layout_items removeObjectIdenticalTo:self.item]; saveLayout(); [self.editor refresh];
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

@implementation ThreeSXControlList
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Choose a control";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return (NSInteger)layout_items.count;
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    (void)tableView;
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = layout_items[path.row].label; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    ThreeSXControlDetails* details = [[ThreeSXControlDetails alloc] initWithStyle:UITableViewStyleInsetGrouped];
    details.item = layout_items[path.row]; details.custom = path.row >= built_in_count; details.editor = self.editor;
    [self.navigationController pushViewController:details animated:YES];
}
@end

@implementation ThreeSXLayoutController
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:1];
    self.canvas = [[ThreeSXTouchView alloc] initWithFrame:self.view.bounds]; self.canvas.editing = YES;
    __weak ThreeSXLayoutController* weakSelf = self;
    self.canvas.openDetails = ^(NSInteger index) { [weakSelf editIndex:index]; };
    [self.view addSubview:self.canvas];
    UIStackView* toolbar = [[UIStackView alloc] init]; toolbar.axis = UILayoutConstraintAxisHorizontal;
    toolbar.spacing = 8; toolbar.distribution = UIStackViewDistributionFillEqually; toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray<NSString*>* titles = @[@"Done", @"Add", @"Controls", @"Style", @"Reset"];
    NSArray<NSString*>* actions = @[@"done", @"addControl", @"showControls", @"chooseStyle", @"resetLayout"];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal]; button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        button.titleLabel.adjustsFontSizeToFitWidth = YES; button.titleLabel.minimumScaleFactor = 0.75;
        button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95]; button.layer.cornerRadius = 8;
        [button addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        [toolbar addArrangedSubview:button];
    }
    [self.view addSubview:toolbar];
    UILabel* instructions = [[UILabel alloc] init]; instructions.text = @"Drag to move • Tap to resize or edit • Changes save automatically";
    instructions.textColor = UIColor.whiteColor; instructions.textAlignment = NSTextAlignmentCenter;
    instructions.font = [UIFont systemFontOfSize:12]; instructions.adjustsFontSizeToFitWidth = YES;
    instructions.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:instructions];
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [toolbar.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toolbar.widthAnchor constraintLessThanOrEqualToConstant:440],
        [toolbar.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:60],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-60],
        [toolbar.heightAnchor constraintEqualToConstant:40],
        [instructions.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:4],
        [instructions.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [instructions.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12]
    ]];
    // A width preference expands the toolbar on tablets without requiring it on
    // smaller landscape phones; its hit area remains above the canvas.
    NSLayoutConstraint* width = [toolbar.widthAnchor constraintEqualToConstant:440]; width.priority = UILayoutPriorityDefaultHigh; width.active = YES;
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.presentingViewController) { editor_open = NO; IOSTouch_Reset(); IOSTouch_RecordActivity(); }
}
- (void)refresh { self.canvas.selected = NSNotFound; [self.canvas refreshLayout]; layoutChanged(); }
- (void)done {
    saveLayout(); [self.canvas resetTouches];
    [self dismissViewControllerAnimated:YES completion:^{ editor_open = NO; layoutChanged(); IOSTouch_RecordActivity(); }];
}
- (void)editIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)layout_items.count || self.presentedViewController) return;
    ThreeSXControlDetails* details = [[ThreeSXControlDetails alloc] initWithStyle:UITableViewStyleInsetGrouped];
    details.item = layout_items[index]; details.custom = index >= built_in_count; details.editor = self;
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:details];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet; [self presentViewController:navigation animated:YES completion:nil];
}
- (void)addControl {
    if (layout_items.count >= (NSUInteger)(built_in_count + custom_limit)) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Custom button limit"
            message:@"You can have up to 16 custom buttons. Remove one to add another." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    ThreeSXTouchItem* item = [[ThreeSXTouchItem alloc] init]; item.label = @"CUSTOM";
    item.control = (IOSLayout_Control){ .center_x = 0.5f, .center_y = 0.45f, .size = 1, .binding = IOS_TOUCH_LP };
    [layout_items addObject:item]; saveLayout(); [self refresh]; [self editIndex:(NSInteger)layout_items.count - 1];
}
- (void)showControls {
    ThreeSXControlList* list = [[ThreeSXControlList alloc] initWithStyle:UITableViewStyleInsetGrouped]; list.editor = self;
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:list];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet; [self presentViewController:navigation animated:YES completion:nil];
}
- (void)chooseStyle {
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:@"Direction control style"
        message:@"All styles support eight directions. The normal stick has a movable thumb; the D-pad is a cross; Hybrid keeps the original circular arrows."
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (int i = 0; i < IOS_LAYOUT_DIRECTION_STYLE_COUNT; i++) {
        IOSLayout_DirectionStyle style = (IOSLayout_DirectionStyle)i;
        NSString* name = [NSString stringWithUTF8String:IOSTouch_DirectionStyleName(i)];
        if (style == direction_style) name = [name stringByAppendingString:@" ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            (void)action; IOSTouch_SetDirectionStyle(style); [self refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), self.view.safeAreaInsets.top + 45, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)resetLayout {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Reset touch layout?"
        message:@"Restore the Hybrid style, original positions and sizes, and remove custom buttons. Other iOS options stay unchanged."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
        (void)action; defaultLayout(safeRect(self.canvas)); saveLayout(); [self refresh];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

bool IOSTouch_Init(SDL_Window* window) {
    UIWindow* native = (__bridge UIWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
    UIView* parent = native.rootViewController.view;
    if (!parent) return SDL_SetError("Could not find the iOS game view for touch controls");
    IOSTouch_Quit(); native_window = native;
    loadLayout(safeRect(parent));
    touch_view = [[ThreeSXTouchView alloc] initWithFrame:parent.bounds]; [parent addSubview:touch_view];
    [touch_view setNeedsLayout]; [touch_view layoutIfNeeded];
    options_button = [UIButton buttonWithType:UIButtonTypeSystem];
    [options_button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    options_button.tintColor = UIColor.whiteColor; options_button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    options_button.layer.cornerRadius = 22; options_button.accessibilityLabel = @"iOS options";
    options_button.translatesAutoresizingMaskIntoConstraints = NO;
    [options_button addAction:[UIAction actionWithHandler:^(UIAction* action) { (void)action; IOSOptions_Present(window); }]
        forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:options_button];
    [NSLayoutConstraint activateConstraints:@[
        [options_button.topAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.topAnchor constant:8],
        [options_button.trailingAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [options_button.widthAnchor constraintEqualToConstant:44], [options_button.heightAnchor constraintEqualToConstant:44]
    ]];
    activity_observer = [[ThreeSXActivityObserver alloc] init]; [native_window addGestureRecognizer:activity_observer];
    IOSTouch_RecordActivity();
    options_timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer* timer) {
        (void)timer;
        if (IOSOptions_IsOpen() || editor_open || activity_observer.contacts.count) options_button.hidden = NO;
        else options_button.hidden = SDL_GetTicks() - last_touch_ms >= 5000;
    }];
    [NSRunLoop.mainRunLoop addTimer:options_timer forMode:NSRunLoopCommonModes];
    IOSTouch_RefreshOptions(); return true;
}
void IOSTouch_Quit(void) {
    [options_timer invalidate]; options_timer = nil;
    if (activity_observer) [native_window removeGestureRecognizer:activity_observer]; activity_observer = nil;
    [options_button removeFromSuperview]; options_button = nil;
    [touch_view resetTouches]; [touch_view removeFromSuperview]; touch_view = nil;
    native_window = nil; layout_items = nil; editor_open = NO;
}
void IOSTouch_Reset(void) {
    [touch_view resetTouches]; [activity_observer.contacts removeAllObjects];
}
void IOSTouch_RecordActivity(void) { last_touch_ms = SDL_GetTicks(); options_button.hidden = NO; }
void IOSTouch_GetButtonState(Input_ButtonState* state) {
    if (!state) return; SDL_zerop(state);
    if (touch_view && IOSOptions_Get()->touch_enabled && !IOSOptions_IsOpen() && !editor_open) *state = [touch_view buttonState];
}
void IOSTouch_RefreshOptions(void) {
    [touch_view resetTouches]; touch_view.hidden = !IOSOptions_Get()->touch_enabled;
}
IOSLayout_DirectionStyle IOSTouch_GetDirectionStyle(void) { return direction_style; }
const char* IOSTouch_DirectionStyleName(int style) {
    switch (style) {
    case IOS_LAYOUT_STICK: return "Normal stick";
    case IOS_LAYOUT_DPAD: return "D-pad";
    default: return "Hybrid";
    }
}
void IOSTouch_SetDirectionStyle(IOSLayout_DirectionStyle style) {
    direction_style = style >= IOS_LAYOUT_HYBRID && style < IOS_LAYOUT_DIRECTION_STYLE_COUNT ? style : IOS_LAYOUT_HYBRID;
    if (layout_items.count) {
        layout_items[0].label = [NSString stringWithUTF8String:IOSTouch_DirectionStyleName(direction_style)];
        saveLayout();
    }
    layoutChanged();
}
void IOSTouch_EditLayout(void) {
    if (!native_window || editor_open || !IOSOptions_IsOpen()) return;
    UIViewController* presenter = native_window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter) return;
    IOSTouch_Reset(); editor_open = YES;
    ThreeSXLayoutController* editor = [[ThreeSXLayoutController alloc] init];
    editor.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:editor animated:YES completion:nil];
}

#endif
