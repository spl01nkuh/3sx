#if CRS_PLATFORM_IOS
#import <UIKit/UIKit.h>
#include <math.h>
#include "platform/app/ios/ios_options.h"
#include "platform/input/ios/ios_touch.h"

static NSString* const preferenceKey = @"3sx-ios-options-v1";
static bool optionsOpen;

static int number(NSDictionary* values, NSString* key, int fallback) {
    id value = values[key];
    return [value isKindOfClass:NSNumber.class] ? [value intValue] : fallback;
}

void IOSOptions_Load(void) {
    NSDictionary* values = [NSUserDefaults.standardUserDefaults dictionaryForKey:preferenceKey];
    IOSOptions options = IOSOptions_Defaults();
    if (values) {
        options.touch_enabled = number(values, @"touch", options.touch_enabled) != 0;
        options.filter = number(values, @"filter", options.filter);
        options.filter_strength = number(values, @"strength", options.filter_strength);
        options.screen_percent = number(values, @"size", options.screen_percent);
        options.screen_width_percent = number(values, @"width", options.screen_width_percent);
        options.screen_height_percent = number(values, @"height", options.screen_height_percent);
        options.aspect = number(values, @"aspect", options.aspect);
        options.stick_sensitivity = number(values, @"sensitivity", options.stick_sensitivity);
        options.stick_deadzone = number(values, @"deadzone", options.stick_deadzone);
        if (number(values, @"schema", 1) < 2) {
            // v0.2 used a 50–200% curve slider and many similar preset IDs.
            if ([values[@"sensitivity"] isKindOfClass:NSNumber.class])
                options.stick_sensitivity = (options.stick_sensitivity + 1) / 2;
            static const int oldFilters[] = { 0, 5, 5, 5, 5, 5, 5, 5, 2, 2, 2, 2, 1, 6, 6, 6 };
            options.filter = options.filter >= 0 && options.filter < (int)(sizeof(oldFilters) / sizeof(oldFilters[0]))
                ? oldFilters[options.filter] : IOS_FILTER_NONE;
        }
    }
    IOSOptions_Apply(options);
}

static void saveOptions(void) {
    const IOSOptions* o = IOSOptions_Get();
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"schema": @2,
        @"touch": @(o->touch_enabled), @"filter": @(o->filter), @"strength": @(o->filter_strength),
        @"size": @(o->screen_percent), @"aspect": @(o->aspect),
        @"width": @(o->screen_width_percent), @"height": @(o->screen_height_percent),
        @"sensitivity": @(o->stick_sensitivity), @"deadzone": @(o->stick_deadzone)
    } forKey:preferenceKey];
    IOSTouch_RefreshOptions();
}

@interface ThreeSXFilterController : UITableViewController
@end
@implementation ThreeSXFilterController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Display Filter";
}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return IOS_FILTER_COUNT;
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    (void)tableView;
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = [NSString stringWithUTF8String:IOSOptions_FilterName((int)path.row)];
    cell.accessoryType = IOSOptions_Get()->filter == path.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (path.row != IOS_FILTER_NONE && IOSOptions_FilterError() != NULL) {
        cell.textLabel.enabled = NO;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    const char* error = IOSOptions_FilterError();
    return error ? [NSString stringWithFormat:@"Filters could not initialize: %s", error]
                 : @"Distinct CRT shader families. Close iOS Options to see the selected effect.";
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    if (path.row != IOS_FILTER_NONE && IOSOptions_FilterError() != NULL) return;
    IOSOptions options = *IOSOptions_Get();
    options.filter = (int)path.row;
    IOSOptions_Apply(options);
    saveOptions();
    [tableView reloadData];
}
@end

@interface ThreeSXOptionsController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@end
@implementation ThreeSXOptionsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iOS Options";
    self.tableView.rowHeight = 78;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(done)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}
- (void)done {
    [self dismissViewControllerAnimated:YES completion:^{ optionsOpen = false; IOSTouch_Reset(); }];
}
- (void)presentationControllerDidDismiss:(UIPresentationController*)controller {
    (void)controller;
    optionsOpen = false;
    IOSTouch_Reset();
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.navigationController.presentingViewController) {
        optionsOpen = false;
        IOSTouch_Reset();
    }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView { (void)tableView; return 4; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 3 : section == 1 ? 6 : section == 2 ? 2 : 1;
}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return @[@"Touch Controls", @"Display", @"Controller", @"Defaults"][section];
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Choose a direction control, move and resize controls, or create custom button combinations. The gear fades after five seconds without touch; touch the screen to show it again.";
    if (section == 1) return @"Changes apply when you close this menu. Screen size scales both axes together. Width and height stretch each axis separately, relative to the chosen aspect ratio. Values above 100% zoom in and may crop the picture; 100% on all three restores the fitted size.";
    if (section == 2) return @"Higher sensitivity activates directions with less stick movement, up to 100%. The game's legacy analog toggle does not affect this setting. The D-pad is unchanged.";
    return @"Settings save automatically on this device. Game data is kept separately.";
}
- (void)toggleTouch:(UISwitch*)control {
    IOSOptions options = *IOSOptions_Get();
    options.touch_enabled = control.on;
    IOSOptions_Apply(options); saveOptions();
}
- (void)changeAspect:(UISegmentedControl*)control {
    IOSOptions options = *IOSOptions_Get();
    options.aspect = (int)control.selectedSegmentIndex;
    IOSOptions_Apply(options); saveOptions();
}
- (void)changeDirectionStyle:(UISegmentedControl*)control {
    IOSTouch_SetDirectionStyle((IOSLayout_DirectionStyle)control.selectedSegmentIndex);
}
- (void)changeSlider:(UISlider*)control {
    IOSOptions options = *IOSOptions_Get();
    const int value = (int)lroundf(control.value);
    control.value = (float)value;
    NSString* title;
    switch (control.tag) {
    case 1: options.filter_strength = value; title = @"Filter strength"; break;
    case 2: options.screen_percent = value; title = @"Screen size"; break;
    case 3: options.stick_sensitivity = value; title = @"Stick sensitivity"; break;
    case 5: options.screen_width_percent = value; title = @"Screen width"; break;
    case 6: options.screen_height_percent = value; title = @"Screen height"; break;
    default: options.stick_deadzone = value; title = @"Stick dead zone"; break;
    }
    UIStackView* stack = (UIStackView*)control.superview;
    UILabel* label = (UILabel*)stack.arrangedSubviews.firstObject;
    label.text = [NSString stringWithFormat:@"%@: %d%%", title, value];
    control.accessibilityValue = [NSString stringWithFormat:@"%d percent", value];
    IOSOptions_Apply(options); saveOptions();
}
- (UITableViewCell*)sliderCell:(NSString*)title value:(int)value min:(int)minimum max:(int)maximum tag:(NSInteger)tag {
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel* label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"%@: %d%%", title, value];
    UISlider* slider = [[UISlider alloc] init];
    slider.minimumValue = (float)minimum; slider.maximumValue = (float)maximum; slider.value = (float)value;
    slider.tag = tag; slider.accessibilityLabel = title;
    slider.accessibilityValue = [NSString stringWithFormat:@"%d percent", value];
    [slider addTarget:self action:@selector(changeSlider:) forControlEvents:UIControlEventValueChanged];
    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, slider]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    UILayoutGuide* margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
    ]];
    return cell;
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    (void)tableView;
    const IOSOptions* o = IOSOptions_Get();
    if (path.section == 1 && path.row == 1) return [self sliderCell:@"Filter strength" value:o->filter_strength min:0 max:100 tag:1];
    if (path.section == 1 && path.row == 3) return [self sliderCell:@"Screen size" value:o->screen_percent min:25 max:100 tag:2];
    if (path.section == 1 && path.row == 4) return [self sliderCell:@"Screen width" value:o->screen_width_percent min:25 max:200 tag:5];
    if (path.section == 1 && path.row == 5) return [self sliderCell:@"Screen height" value:o->screen_height_percent min:25 max:200 tag:6];
    if (path.section == 2 && path.row == 0) return [self sliderCell:@"Stick sensitivity" value:o->stick_sensitivity min:1 max:100 tag:3];
    if (path.section == 2 && path.row == 1) return [self sliderCell:@"Stick dead zone" value:o->stick_deadzone min:0 max:35 tag:4];
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (path.section == 0 && path.row == 0) {
        cell.textLabel.text = @"Show touch controls";
        UISwitch* toggle = [[UISwitch alloc] init]; toggle.on = o->touch_enabled;
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self action:@selector(toggleTouch:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == 0 && path.row == 1) {
        cell.textLabel.text = @"Direction control";
        UISegmentedControl* style = [[UISegmentedControl alloc] initWithItems:@[@"Hybrid", @"Stick", @"D-pad"]];
        style.selectedSegmentIndex = IOSTouch_GetDirectionStyle();
        style.accessibilityLabel = @"Direction control style";
        [style addTarget:self action:@selector(changeDirectionStyle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = style; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == 0) {
        cell.textLabel.text = @"Edit controls & custom buttons";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (path.section == 1 && path.row == 0) {
        cell.textLabel.text = @"Filter";
        cell.detailTextLabel.text = [NSString stringWithUTF8String:IOSOptions_FilterName(o->filter)];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (path.section == 1) {
        cell.textLabel.text = @"Aspect ratio";
        UISegmentedControl* aspect = [[UISegmentedControl alloc] initWithItems:@[@"4:3", @"Original", @"Fill"]];
        aspect.selectedSegmentIndex = o->aspect;
        aspect.accessibilityLabel = @"Aspect ratio";
        [aspect addTarget:self action:@selector(changeAspect:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = aspect; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = @"Reset iOS options"; cell.textLabel.textColor = UIColor.systemRedColor;
    }
    return cell;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 2) {
        IOSTouch_EditLayout();
    } else if (path.section == 1 && path.row == 0) {
        [self.navigationController pushViewController:[[ThreeSXFilterController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    } else if (path.section == 3) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Reset iOS options?"
            message:@"Restore touch, display and controller defaults." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            (void)action; IOSOptions_Apply(IOSOptions_Defaults());
            IOSTouch_SetDirectionStyle(IOS_LAYOUT_HYBRID); saveOptions(); [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

bool IOSOptions_IsOpen(void) { return optionsOpen; }
void IOSOptions_Present(SDL_Window* window) {
    if (optionsOpen) return;
    UIWindow* native = (__bridge UIWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
    UIViewController* root = native.rootViewController;
    if (!root || root.presentedViewController) return;
    IOSTouch_Reset();
    ThreeSXOptionsController* controller = [[ThreeSXOptionsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.presentationController.delegate = controller;
    optionsOpen = true;
    [root presentViewController:navigation animated:YES completion:^{
        navigation.presentationController.delegate = controller;
    }];
}
#endif
