#ifndef IOS_FILTER_PREVIEW_H
#define IOS_FILTER_PREVIEW_H

#ifdef __OBJC__
#import <MetalKit/MetalKit.h>

// Uses a copy of the paused game canvas and the production Metal shader.
@interface ThreeSXFilterPreview : MTKView <MTKViewDelegate>
@property(nonatomic, readonly, copy) NSString* previewError;
@property(nonatomic, assign) BOOL showOriginal;
- (void)refresh;
@end
#endif

#endif
