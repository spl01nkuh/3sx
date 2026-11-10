#if CRS_PLATFORM_IOS
#import "platform/app/ios/ios_filter_preview.h"
#include "platform/app/ios/ios_filter_frame.h"
#include "platform/app/ios/ios_options.h"

typedef struct PreviewUniforms {
    float controls[4];
    float source[4];
} PreviewUniforms;
_Static_assert(sizeof(PreviewUniforms) == 32, "Preview uses production Metal uniforms");

@interface ThreeSXFilterPreview ()
@property(nonatomic, readwrite, copy) NSString* previewError;
@property(nonatomic, strong) id<MTLCommandQueue> previewQueue;
@property(nonatomic, strong) id<MTLRenderPipelineState> previewPipeline;
@property(nonatomic, strong) id<MTLTexture> gameFrame;
@property(nonatomic, strong) id<MTLSamplerState> sourceSampler;
@property(nonatomic, assign) unsigned int previewFrame;
@end

@implementation ThreeSXFilterPreview
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    if (!self) return nil;
    self.delegate = self;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.clearColor = MTLClearColorMake(0, 0, 0, 1);
    self.preferredFramesPerSecond = 15;
    self.layer.cornerRadius = 8;
    self.clipsToBounds = YES;
    self.accessibilityLabel = @"Filter preview of the paused game";
    self.isAccessibilityElement = YES;
    self.paused = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationStateChanged:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationStateChanged:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    if (!self.device) { self.previewError = @"Preview is unavailable on this device."; return self; }
    self.previewQueue = [self.device newCommandQueue];
    const char* base = SDL_GetBasePath();
    NSString* path = base ? [[NSString stringWithUTF8String:base] stringByAppendingPathComponent:@"shaders/sdlgpu/msl/ios_crt.frag"] : nil;
    NSError* error = nil;
    NSString* fragment = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error] : nil;
    if (!fragment) { self.previewError = @"The filter preview shader could not be loaded."; return self; }
    NSString* vertex = @"\nstruct PreviewVertex { float4 position [[position]]; float2 uv [[user(locn0)]]; };\n"
        "vertex PreviewVertex ios_preview_vertex(uint index [[vertex_id]]) {\n"
        " const float2 positions[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};\n"
        " PreviewVertex out; out.position=float4(positions[index],0,1);\n"
        " out.uv=positions[index]*float2(0.5,-0.5)+0.5; return out; }\n";
    MTLCompileOptions* compile = [[MTLCompileOptions alloc] init];
    compile.languageVersion = MTLLanguageVersion2_4;
    id<MTLLibrary> library = [self.device newLibraryWithSource:[fragment stringByAppendingString:vertex] options:compile error:&error];
    if (!library) { self.previewError = @"The filter preview could not initialize."; SDL_Log("Filter preview: %s", error.description.UTF8String); return self; }
    MTLRenderPipelineDescriptor* pipeline = [[MTLRenderPipelineDescriptor alloc] init];
    pipeline.vertexFunction = [library newFunctionWithName:@"ios_preview_vertex"];
    pipeline.fragmentFunction = [library newFunctionWithName:@"main0"];
    pipeline.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    self.previewPipeline = [self.device newRenderPipelineStateWithDescriptor:pipeline error:&error];
    if (!self.previewPipeline || !self.previewQueue) {
        self.previewError = @"The filter preview could not initialize.";
        SDL_Log("Filter preview pipeline: %s", error.description.UTF8String); return self;
    }
    SDL_Surface* surface = IOSFilter_CopyGameFrame();
    if (!surface) { self.previewError = @"The current game frame could not be copied for preview."; return self; }
    MTLTextureDescriptor* texture = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:(NSUInteger)surface->w height:(NSUInteger)surface->h mipmapped:NO];
    texture.usage = MTLTextureUsageShaderRead;
    texture.storageMode = MTLStorageModeShared;
    self.gameFrame = [self.device newTextureWithDescriptor:texture];
    if (self.gameFrame) [self.gameFrame replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)surface->w, (NSUInteger)surface->h)
        mipmapLevel:0 withBytes:surface->pixels bytesPerRow:(NSUInteger)surface->pitch];
    SDL_DestroySurface(surface);
    MTLSamplerDescriptor* sampler = [[MTLSamplerDescriptor alloc] init];
    sampler.minFilter = MTLSamplerMinMagFilterNearest;
    sampler.magFilter = MTLSamplerMinMagFilterNearest;
    sampler.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sampler.tAddressMode = MTLSamplerAddressModeClampToEdge;
    self.sourceSampler = [self.device newSamplerStateWithDescriptor:sampler];
    if (!self.gameFrame || !self.sourceSampler) self.previewError = @"Preview image memory could not be allocated.";
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    self.paused = self.window == nil || self.previewError != nil;
}
- (void)applicationStateChanged:(NSNotification*)notification {
    self.paused = ![notification.name isEqualToString:UIApplicationDidBecomeActiveNotification] ||
        self.window == nil || self.previewError != nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh { [self draw]; }
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size { (void)view; (void)size; }
- (void)drawInMTKView:(MTKView*)view {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        self.previewError || !self.gameFrame || view.drawableSize.width < 1 || view.drawableSize.height < 1) return;
    MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!pass || !drawable) return;
    SDL_Rect viewport = IOSOptions_Viewport((SDL_Rect) { 0, 0, (int)view.drawableSize.width, (int)view.drawableSize.height });
    const IOSOptions* options = IOSOptions_Get();
    PreviewUniforms uniforms = {
        .controls = { (float)options->filter_strength / 100, self.showOriginal ? 0 : (float)options->filter,
                      (float)viewport.w, (float)viewport.h },
        .source = { (float)self.gameFrame.width, (float)self.gameFrame.height, (float)(self.previewFrame++ % 3600), 0 }
    };
    id<MTLCommandBuffer> command = [self.previewQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
    [encoder setViewport:(MTLViewport) { viewport.x, viewport.y, viewport.w, viewport.h, 0, 1 }];
    [encoder setRenderPipelineState:self.previewPipeline];
    [encoder setFragmentTexture:self.gameFrame atIndex:0];
    [encoder setFragmentSamplerState:self.sourceSampler atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [command presentDrawable:drawable];
    [command commit];
}
@end
#endif
