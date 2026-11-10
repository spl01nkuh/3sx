#ifndef IOS_STICK_PREVIEW_H
#define IOS_STICK_PREVIEW_H

#ifdef __OBJC__
#import <UIKit/UIKit.h>

// Push on the existing options navigation controller. This view reads input
// while the game stays paused; its touch tester never creates game input.
@interface ThreeSXStickPreviewController : UIViewController
@end
#endif

#endif
