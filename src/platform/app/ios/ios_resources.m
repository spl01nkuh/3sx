#if CRS_PLATFORM_IOS

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "platform/app/ios/ios_resources.h"
#include "port/resources.h"

#include <SDL3/SDL.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

static SDL_Window* import_window;
static bool import_finished;

@interface ThreeSXImportController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIButton* importButton;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UIActivityIndicatorView* activity;
@end

@implementation ThreeSXImportController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:1];

    UILabel* title = [[UILabel alloc] init];
    title.text = @"Welcome to 3SX";
    title.font = [UIFont boldSystemFontOfSize:28];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;

    UILabel* instructions = [[UILabel alloc] init];
    instructions.text = @"Import SF33RD.AFS from your copy of the PlayStation 2 game.\n"
                         "Extract THIRD/SF33RD.AFS from the disc image first, then choose it in Files.\n"
                         "Play with the touch controls or connect a compatible game controller.";
    instructions.numberOfLines = 0;
    instructions.textAlignment = NSTextAlignmentCenter;
    instructions.textColor = UIColor.whiteColor;

    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.importButton setTitle:@"Import SF33RD.AFS" forState:UIControlStateNormal];
    self.importButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.importButton addTarget:self action:@selector(chooseArchive) forControlEvents:UIControlEventTouchUpInside];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = UIColor.lightGrayColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"Game data is kept on this device in 3SX/resources.";

    self.activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activity.color = UIColor.whiteColor;
    self.activity.hidesWhenStopped = YES;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[title, instructions, self.importButton, self.activity, self.statusLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:680],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];
}

- (void)chooseArchive {
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
    (void)controller;
    self.statusLabel.text = @"Choose Import SF33RD.AFS when your file is ready.";
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    (void)controller;
    NSURL* source = urls.firstObject;
    if (source == nil) {
        return;
    }

    self.importButton.enabled = NO;
    self.statusLabel.text = @"Copying and verifying game data…";
    [self.activity startAnimating];

    // Disc data is large. Keep UIKit and SDL responsive while copying and hashing.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            BOOL scoped = [source startAccessingSecurityScopedResource];
            NSString* destination = [NSString stringWithUTF8String:Resources_GetAFSPath()];
            NSString* temporary = [destination stringByAppendingString:@".importing"];
            NSFileManager* manager = [[NSFileManager alloc] init];
            NSError* error = nil;
            __block NSString* failure = nil;

            if (![manager createDirectoryAtPath:destination.stringByDeletingLastPathComponent
                   withIntermediateDirectories:YES attributes:nil error:&error]) {
                failure = error.localizedDescription;
            }

            if (failure == nil) {
                [manager removeItemAtPath:temporary error:nil];
                // Coordinate with Files providers so iCloud items are downloaded
                // and other applications cannot change the source during copy.
                NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                [coordinator coordinateReadingItemAtURL:source options:NSFileCoordinatorReadingWithoutChanges
                    error:&error byAccessor:^(NSURL* readableURL) {
                        NSError* copyError = nil;
                        if (![manager copyItemAtURL:readableURL toURL:[NSURL fileURLWithPath:temporary] error:&copyError]) {
                            failure = copyError.localizedDescription;
                        }
                    }];
                if (error != nil) {
                    failure = error.localizedDescription;
                }

                if (failure == nil && !Resources_ValidateAFS(temporary.fileSystemRepresentation)) {
                    failure = @"This is not the supported SF33RD.AFS archive. Choose THIRD/SF33RD.AFS "
                               "from the PlayStation 2 version of the game.";
                } else if (failure == nil && rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) != 0) {
                    failure = [NSString stringWithFormat:@"Could not save the archive: %s", strerror(errno)];
                }
            }

            [manager removeItemAtPath:temporary error:nil];
            if (scoped) {
                [source stopAccessingSecurityScopedResource];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.activity stopAnimating];
                self.importButton.enabled = YES;
                if (failure != nil) {
                    self.statusLabel.text = failure;
                    return;
                }
                self.statusLabel.text = @"Game data is ready.";
                [self dismissViewControllerAnimated:NO completion:^{ import_finished = true; }];
            });
        }
    });
}

@end

static ThreeSXImportController* importer;

const char* IOSResources_GetDocumentsPath(void) {
    static char* documents;
    if (documents == NULL) {
        NSString* directory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        documents = SDL_strdup([[directory stringByAppendingString:@"/"] UTF8String]);
    }
    return documents;
}

bool IOSResources_RunImportFlow(void) {
    if (import_finished) {
        importer = nil;
        SDL_DestroyWindow(import_window);
        import_window = NULL;
        return true;
    }

    if (import_window == NULL) {
        import_window = SDL_CreateWindow("3SX", 960, 540, SDL_WINDOW_FULLSCREEN | SDL_WINDOW_HIGH_PIXEL_DENSITY);
        if (import_window == NULL) {
            SDL_Log("Could not create the resource import window: %s", SDL_GetError());
            return false;
        }
    }

    if (importer == nil) {
        UIWindow* native = (__bridge UIWindow*)SDL_GetPointerProperty(
            SDL_GetWindowProperties(import_window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
        UIViewController* root = native.rootViewController;
        if (root.view.window == nil || root.presentedViewController != nil) {
            return false;
        }
        importer = [[ThreeSXImportController alloc] init];
        importer.modalPresentationStyle = UIModalPresentationFullScreen;
        [root presentViewController:importer animated:NO completion:nil];
    }
    return false;
}

#endif
