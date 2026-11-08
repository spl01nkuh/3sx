// Native offscreen regression test for the production iOS CRT Metal shader.
// Build on macOS:
//   clang -O2 -fobjc-arc -framework Metal -framework Foundation \
//     tools/tests/test-ios-crt-metal.m -o /tmp/test-ios-crt-metal
// Run: /tmp/test-ios-crt-metal path/to/ios_crt.frag output-directory
// Exit 77 explicitly means no Metal device was available; it is not a pass.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const NSUInteger sourceWidth = 384, sourceHeight = 224;
static const NSUInteger outputWidth = 1152, outputHeight = 672;

typedef struct CRTTestOptions {
    float controls[4]; // strength, preset, output width, output height
    float source[4];   // source width, source height, frame, reserved
} CRTTestOptions;
_Static_assert(sizeof(CRTTestOptions) == 32, "Production CRT uniforms must remain 32 bytes");
_Static_assert(offsetof(CRTTestOptions, source) == 16, "MSL float4 source offset must be 16");

static const char* filterNames[] = {
    "Off", "Sharp Bilinear", "Zfast CRT", "Lottes Arcade",
    "Caligari Phosphor", "Carlos EasyMode", "Composite"
};
static const char* fileNames[] = {
    "00-off.ppm", "01-sharp-bilinear.ppm", "02-zfast-crt.ppm", "03-lottes-arcade.ppm",
    "04-caligari-phosphor.ppm", "05-carlos-easymode.ppm", "06-composite.ppm"
};

// Original synthetic fixture: color bars, single-pixel detail, ramps, diagonals,
// and two block characters on an arena-like background. No game assets needed.
static NSData* diagnosticImage(void) {
    NSMutableData* image = [NSMutableData dataWithLength:sourceWidth * sourceHeight * 4];
    uint8_t* pixels = image.mutableBytes;
    const uint8_t bars[8][3] = {
        {235,235,235}, {235,235,24}, {24,235,235}, {24,235,24},
        {235,24,235}, {235,24,24}, {24,24,235}, {12,12,12}
    };
    for (NSUInteger y = 0; y < sourceHeight; y++) {
        for (NSUInteger x = 0; x < sourceWidth; x++) {
            int r = 22 + (int)(x * 36 / sourceWidth);
            int g = 25 + (int)(y * 34 / sourceHeight);
            int b = 60 + (int)(x * 45 / sourceWidth);
            if (y < 28) {
                NSUInteger bar = x * 8 / sourceWidth;
                r = bars[bar][0]; g = bars[bar][1]; b = bars[bar][2];
            } else if (y < 60) {
                NSUInteger period = 1 + x / 96;
                int value = ((x / period + y / period) & 1) ? 224 : 24;
                r = g = b = value;
            } else if (y < 90) {
                int value = (int)(255 * x / (sourceWidth - 1));
                r = value; g = value; b = value;
                if (y > 77) { r = (x & 1) ? 255 : 0; g = (x % 3) ? 0 : 255; b = (x % 5) ? 0 : 255; }
            } else {
                if (y > 174) {
                    int line = ((int)y % 9 == 0) || (((int)x + ((int)y - 174) * 2) % 29 < 2);
                    r = line ? 115 : 52; g = line ? 92 : 42; b = line ? 95 : 60;
                }
                if (y > 100 && y < 109 && ((x > 14 && x < 163) || (x > 221 && x < 370))) {
                    r = 220; g = 194; b = 54;
                }
                if ((int)x > 45 && (int)x < 337 && ((int)x + 2 * (int)y) % 71 < 2) {
                    r += 35; g += 35; b += 35;
                }
                for (int fighter = 0; fighter < 2; fighter++) {
                    int cx = fighter ? 276 : 108;
                    int dx = (int)x - cx, dy = (int)y - 145;
                    if (dx * dx + (dy + 12) * (dy + 12) < 70) { r = 235; g = 174; b = 120; }
                    if (abs(dx) < 11 && dy > -4 && dy < 23) {
                        r = fighter ? 205 : 34; g = fighter ? 40 : 122; b = fighter ? 40 : 224;
                    }
                    if (dy >= 19 && dy < 42 && ((dx > -14 && dx < -4) || (dx > 4 && dx < 14))) {
                        r = fighter ? 180 : 31; g = fighter ? 31 : 96; b = fighter ? 30 : 191;
                    }
                    int arm = fighter ? -dx : dx;
                    if (dy > 1 && dy < 9 && arm > 8 && arm < 31) { r = 230; g = 164; b = 111; }
                }
                int dx = (int)x - 192, dy = (int)y - 148;
                int radius = dx * dx + dy * dy;
                if (radius > 132 && radius < 224) { r = 250; g = 228; b = 137; }
            }
            NSUInteger index = (y * sourceWidth + x) * 4;
            pixels[index] = (uint8_t)MIN(255, MAX(0, r));
            pixels[index + 1] = (uint8_t)MIN(255, MAX(0, g));
            pixels[index + 2] = (uint8_t)MIN(255, MAX(0, b));
            pixels[index + 3] = 255;
        }
    }
    return image;
}

@interface CRTMetalHarness : NSObject
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic, strong) id<MTLTexture> input;
@property(nonatomic, strong) id<MTLSamplerState> sampler;
- (instancetype)initWithDevice:(id<MTLDevice>)device shader:(NSString*)shader fixture:(NSData*)fixture;
- (NSData*)renderPreset:(int)preset strength:(float)strength;
@end

@implementation CRTMetalHarness
- (instancetype)initWithDevice:(id<MTLDevice>)device shader:(NSString*)shader fixture:(NSData*)fixture {
    self = [super init];
    if (!self) return nil;
    self.device = device;
    self.queue = [device newCommandQueue];
    // Append a fullscreen vertex shader to the actual production fragment source.
    NSString* vertex = @"\nstruct CRTTestVertexOut { float4 position [[position]]; float2 uv [[user(locn0)]]; };\n"
        "vertex CRTTestVertexOut crt_test_vertex(uint index [[vertex_id]]) {\n"
        "  const float2 positions[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};\n"
        "  CRTTestVertexOut out; out.position=float4(positions[index],0,1);\n"
        "  out.uv=positions[index]*float2(0.5,-0.5)+0.5; return out; }\n";
    NSError* error = nil;
    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    options.languageVersion = MTLLanguageVersion2_4;
    id<MTLLibrary> library = [device newLibraryWithSource:[shader stringByAppendingString:vertex] options:options error:&error];
    if (!library) { fprintf(stderr, "FAIL: production Metal shader compilation: %s\n", error.description.UTF8String); return nil; }
    MTLRenderPipelineDescriptor* pipeline = [[MTLRenderPipelineDescriptor alloc] init];
    pipeline.vertexFunction = [library newFunctionWithName:@"crt_test_vertex"];
    pipeline.fragmentFunction = [library newFunctionWithName:@"main0"];
    pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA32Float;
    self.pipeline = [device newRenderPipelineStateWithDescriptor:pipeline error:&error];
    if (!self.pipeline) { fprintf(stderr, "FAIL: Metal pipeline: %s\n", error.description.UTF8String); return nil; }
    MTLSamplerDescriptor* sampler = [[MTLSamplerDescriptor alloc] init];
    sampler.minFilter = MTLSamplerMinMagFilterNearest;
    sampler.magFilter = MTLSamplerMinMagFilterNearest;
    sampler.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sampler.tAddressMode = MTLSamplerAddressModeClampToEdge;
    self.sampler = [device newSamplerStateWithDescriptor:sampler];
    MTLTextureDescriptor* texture = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:sourceWidth height:sourceHeight mipmapped:NO];
    texture.usage = MTLTextureUsageShaderRead;
    texture.storageMode = MTLStorageModePrivate;
    self.input = [device newTextureWithDescriptor:texture];
    id<MTLBuffer> upload = [device newBufferWithBytes:fixture.bytes length:fixture.length options:MTLResourceStorageModeShared];
    if (!self.queue || !self.sampler || !self.input || !upload) { fprintf(stderr, "FAIL: Metal source resource allocation\n"); return nil; }
    id<MTLCommandBuffer> command = [self.queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    [blit copyFromBuffer:upload sourceOffset:0 sourceBytesPerRow:sourceWidth * 4 sourceBytesPerImage:sourceWidth * sourceHeight * 4
        sourceSize:MTLSizeMake(sourceWidth, sourceHeight, 1) toTexture:self.input destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding]; [command commit]; [command waitUntilCompleted];
    if (command.status == MTLCommandBufferStatusError) { fprintf(stderr, "FAIL: fixture upload: %s\n", command.error.description.UTF8String); return nil; }
    return self;
}
- (NSData*)renderPreset:(int)preset strength:(float)strength {
    MTLTextureDescriptor* texture = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
        width:outputWidth height:outputHeight mipmapped:NO];
    texture.usage = MTLTextureUsageRenderTarget;
    texture.storageMode = MTLStorageModePrivate;
    id<MTLTexture> target = [self.device newTextureWithDescriptor:texture];
    NSUInteger rowBytes = outputWidth * 4 * sizeof(float); // Multiple of the required 256-byte alignment.
    id<MTLBuffer> readback = [self.device newBufferWithLength:rowBytes * outputHeight options:MTLResourceStorageModeShared];
    if (!target || !readback) { fprintf(stderr, "FAIL: Metal output allocation\n"); return nil; }
    CRTTestOptions uniforms = {
        .controls = { strength, (float)preset, (float)outputWidth, (float)outputHeight },
        .source = { (float)sourceWidth, (float)sourceHeight, 0, 0 }
    };
    id<MTLCommandBuffer> command = [self.queue commandBuffer];
    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:self.pipeline];
    [encoder setFragmentTexture:self.input atIndex:0];
    [encoder setFragmentSamplerState:self.sampler atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    [blit copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
        sourceSize:MTLSizeMake(outputWidth, outputHeight, 1) toBuffer:readback destinationOffset:0
        destinationBytesPerRow:rowBytes destinationBytesPerImage:rowBytes * outputHeight];
    [blit endEncoding]; [command commit]; [command waitUntilCompleted];
    if (command.status == MTLCommandBufferStatusError) {
        fprintf(stderr, "FAIL: rendering preset %d: %s\n", preset, command.error.description.UTF8String); return nil;
    }
    return [NSData dataWithBytes:readback.contents length:rowBytes * outputHeight];
}
@end

static double difference(NSData* lhs, NSData* rhs) {
    const float* a = lhs.bytes; const float* b = rhs.bytes;
    double total = 0;
    for (NSUInteger pixel = 0; pixel < outputWidth * outputHeight; pixel++) {
        for (NSUInteger channel = 0; channel < 3; channel++) total += fabs((double)a[pixel * 4 + channel] - b[pixel * 4 + channel]);
    }
    return total / (double)(outputWidth * outputHeight * 3);
}
static BOOL validImage(NSData* image, const char* label) {
    if (!image || image.length != outputWidth * outputHeight * 4 * sizeof(float)) return NO;
    const float* values = image.bytes;
    double sum = 0; NSUInteger lit = 0;
    for (NSUInteger pixel = 0; pixel < outputWidth * outputHeight; pixel++) {
        for (NSUInteger channel = 0; channel < 4; channel++) {
            float value = values[pixel * 4 + channel];
            if (!isfinite(value) || value < -0.00001f || value > 1.0001f) {
                fprintf(stderr, "FAIL: %s non-finite/out-of-range pixel %lu channel %lu: %.8g\n", label,
                    (unsigned long)pixel, (unsigned long)channel, value); return NO;
            }
        }
        double luma = 0.2126 * values[pixel * 4] + 0.7152 * values[pixel * 4 + 1] + 0.0722 * values[pixel * 4 + 2];
        sum += luma; if (luma > 0.01) lit++;
    }
    if (sum / (outputWidth * outputHeight) < 0.02 || lit < outputWidth * outputHeight / 10) {
        fprintf(stderr, "FAIL: %s rendered a black/near-empty image\n", label); return NO;
    }
    return YES;
}
static NSData* rgbImage(NSData* floatImage) {
    NSMutableData* rgb = [NSMutableData dataWithLength:outputWidth * outputHeight * 3];
    uint8_t* dst = rgb.mutableBytes; const float* src = floatImage.bytes;
    for (NSUInteger pixel = 0; pixel < outputWidth * outputHeight; pixel++) {
        for (NSUInteger channel = 0; channel < 3; channel++) dst[pixel * 3 + channel] = (uint8_t)lrintf(fminf(1, fmaxf(0, src[pixel * 4 + channel])) * 255);
    }
    return rgb;
}
static BOOL writePPM(NSString* path, NSData* rgb, NSUInteger width, NSUInteger height) {
    FILE* file = fopen(path.fileSystemRepresentation, "wb");
    if (!file) { perror("FAIL: output PPM"); return NO; }
    fprintf(file, "P6\n%lu %lu\n255\n", (unsigned long)width, (unsigned long)height);
    BOOL ok = fwrite(rgb.bytes, 1, rgb.length, file) == rgb.length;
    if (fclose(file) != 0) ok = NO;
    return ok;
}
// A small original bitmap alphabet labels the exported contact sheet.
static const uint8_t alphabet[26][7] = {
    {14,17,17,31,17,17,17},{30,17,17,30,17,17,30},{14,17,16,16,16,17,14},{30,17,17,17,17,17,30},
    {31,16,16,30,16,16,31},{31,16,16,30,16,16,16},{14,17,16,23,17,17,15},{17,17,17,31,17,17,17},
    {14,4,4,4,4,4,14},{7,2,2,2,18,18,12},{17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
    {17,27,21,21,17,17,17},{17,25,21,19,17,17,17},{14,17,17,17,17,17,14},{30,17,17,30,16,16,16},
    {14,17,17,17,21,18,13},{30,17,17,30,20,18,17},{15,16,16,14,1,1,30},{31,4,4,4,4,4,4},
    {17,17,17,17,17,17,14},{17,17,17,17,17,10,4},{17,17,17,21,21,21,10},{17,17,10,4,10,17,17},
    {17,17,10,4,4,4,4},{31,1,2,4,8,16,31}
};
static BOOL writeContactSheet(NSString* path, NSArray<NSData*>* images) {
    const NSUInteger columns = 3, header = 30, rows = (images.count + columns - 1) / columns;
    NSUInteger width = outputWidth * columns, height = (outputHeight + header) * rows;
    NSMutableData* sheet = [NSMutableData dataWithLength:width * height * 3];
    uint8_t* dst = sheet.mutableBytes; memset(dst, 12, sheet.length);
    for (NSUInteger index = 0; index < images.count; index++) {
        NSUInteger x = index % columns * outputWidth, y = index / columns * (outputHeight + header);
        const char* title = filterNames[index];
        for (NSUInteger character = 0; title[character]; character++) {
            int letter = title[character]; if (letter >= 'a' && letter <= 'z') letter -= 'a' - 'A';
            if (letter < 'A' || letter > 'Z') continue;
            for (NSUInteger gy = 0; gy < 7; gy++) for (NSUInteger gx = 0; gx < 5; gx++) {
                if (!(alphabet[letter - 'A'][gy] & (1 << (4 - gx)))) continue;
                for (NSUInteger sy = 0; sy < 3; sy++) for (NSUInteger sx = 0; sx < 3; sx++) {
                    NSUInteger pixel = ((y + 4 + gy * 3 + sy) * width + x + 8 + character * 18 + gx * 3 + sx) * 3;
                    dst[pixel] = dst[pixel + 1] = dst[pixel + 2] = 238;
                }
            }
        }
        const uint8_t* src = images[index].bytes;
        for (NSUInteger row = 0; row < outputHeight; row++) memcpy(dst + ((y + header + row) * width + x) * 3,
            src + row * outputWidth * 3, outputWidth * 3);
    }
    return writePPM(path, sheet, width, height);
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr, "Usage: %s production-ios-crt.frag output-directory\n", argv[0]); return 2; }
        NSString* output = [NSString stringWithUTF8String:argv[2]];
        NSError* error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:&error]) {
            fprintf(stderr, "FAIL: output directory: %s\n", error.description.UTF8String); return 1;
        }
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            NSString* reason = @"SKIP: no Metal device is available. No rendering comparison was performed.\n";
            fputs(reason.UTF8String, stderr);
            [reason writeToFile:[output stringByAppendingPathComponent:@"SKIP.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            return 77;
        }
        NSString* shader = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:&error];
        if (!shader) { fprintf(stderr, "FAIL: shader source: %s\n", error.description.UTF8String); return 1; }
        printf("Metal device: %s\n", device.name.UTF8String);
        CRTMetalHarness* harness = [[CRTMetalHarness alloc] initWithDevice:device shader:shader fixture:diagnosticImage()];
        if (!harness) return 1;
        NSData* off = [harness renderPreset:0 strength:0.75f];
        if (!validImage(off, "Off")) return 1;
        NSMutableArray<NSData*>* rendered = [NSMutableArray arrayWithObject:off];
        NSMutableArray<NSData*>* images = [NSMutableArray arrayWithObject:rgbImage(off)];
        NSMutableArray<NSData*>* images50 = [NSMutableArray arrayWithObject:rgbImage(off)];
        NSMutableString* metrics = [NSMutableString stringWithString:@"filter\tmean_absolute_difference_25\tmean_absolute_difference_50\tmean_absolute_difference_75\tmean_absolute_difference_100\n"];
        BOOL passed = YES;
        for (int preset = 1; preset < 7; preset++) {
            @autoreleasepool {
                NSData* zero = [harness renderPreset:preset strength:0];
                NSData* low = [harness renderPreset:preset strength:0.25f];
                NSData* middle = [harness renderPreset:preset strength:0.50f];
                NSData* normal = [harness renderPreset:preset strength:0.75f];
                NSData* high = [harness renderPreset:preset strength:1.0f];
                if (!validImage(zero, filterNames[preset]) || !validImage(low, filterNames[preset]) ||
                    !validImage(middle, filterNames[preset]) || !validImage(normal, filterNames[preset]) ||
                    !validImage(high, filterNames[preset])) return 1;
                double zeroDifference = difference(off, zero), lowDifference = difference(off, low);
                double middleDifference = difference(off, middle);
                double normalDifference = difference(off, normal), highDifference = difference(off, high);
                printf("%s: Off delta at strength 0/25/50/75/100 = %.8f / %.6f / %.6f / %.6f / %.6f\n",
                    filterNames[preset], zeroDifference, lowDifference, middleDifference, normalDifference, highDifference);
                if (zeroDifference > 0.000001) { fprintf(stderr, "FAIL: strength zero changes %s\n", filterNames[preset]); passed = NO; }
                if (middleDifference < 0.0025) { fprintf(stderr, "FAIL: %s has no measurable effect at strength 50\n", filterNames[preset]); passed = NO; }
                if (normalDifference < 0.0025) { fprintf(stderr, "FAIL: %s has no measurable effect at strength 75\n", filterNames[preset]); passed = NO; }
                if (highDifference <= lowDifference + 0.0005) { fprintf(stderr, "FAIL: strength 100 does not exceed strength 25 for %s\n", filterNames[preset]); passed = NO; }
                [metrics appendFormat:@"%s\t%.8f\t%.8f\t%.8f\t%.8f\n", filterNames[preset], lowDifference, middleDifference, normalDifference, highDifference];
                [rendered addObject:normal]; [images addObject:rgbImage(normal)];
                [images50 addObject:rgbImage(middle)];
            }
        }
        [metrics appendString:@"\nfirst_filter\tsecond_filter\tmean_absolute_difference_at_75\n"];
        for (NSUInteger first = 1; first < rendered.count; first++) for (NSUInteger second = first + 1; second < rendered.count; second++) {
            double delta = difference(rendered[first], rendered[second]);
            printf("Pair %s / %s: %.6f\n", filterNames[first], filterNames[second], delta);
            [metrics appendFormat:@"%s\t%s\t%.8f\n", filterNames[first], filterNames[second], delta];
            if (delta < 0.001) { fprintf(stderr, "FAIL: %s and %s are visually indistinguishable in fixture\n", filterNames[first], filterNames[second]); passed = NO; }
        }
        NSString* directory50 = [output stringByAppendingPathComponent:@"strength-50"];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory50 withIntermediateDirectories:YES attributes:nil error:&error]) {
            fprintf(stderr, "FAIL: strength-50 output directory: %s\n", error.description.UTF8String); return 1;
        }
        for (NSUInteger index = 0; index < images.count; index++) {
            if (!writePPM([output stringByAppendingPathComponent:[NSString stringWithUTF8String:fileNames[index]]], images[index], outputWidth, outputHeight)) return 1;
            if (!writePPM([directory50 stringByAppendingPathComponent:[NSString stringWithUTF8String:fileNames[index]]], images50[index], outputWidth, outputHeight)) return 1;
        }
        if (!writeContactSheet([output stringByAppendingPathComponent:@"contact-sheet.ppm"], images)) return 1;
        if (!writeContactSheet([output stringByAppendingPathComponent:@"contact-sheet-50.ppm"], images50)) return 1;
        if (![metrics writeToFile:[output stringByAppendingPathComponent:@"metrics.tsv"] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            fprintf(stderr, "FAIL: metrics write: %s\n", error.description.UTF8String); return 1;
        }
        printf("%s: actual Metal fragment rendering; output %s\n", passed ? "PASS" : "FAIL", output.fileSystemRepresentation);
        return passed ? 0 : 1;
    }
}
