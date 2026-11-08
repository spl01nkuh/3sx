/*
 * 3SX single-pass Metal CRT filters.
 *
 * Lottes Gaussian reconstruction/warp/mask: PUBLIC DOMAIN, Timothy Lottes.
 * zfast cubic scaling/brightness-dependent scanlines:
 *   Copyright (C) 2017 Greg Hogan (SoltanGris42), GPL-2.0-or-later.
 * Caligari phosphor spots:
 *   Copyright (C) 2011 caligari; ported by Hyllian, GPL-2.0-or-later.
 * EasyMode slot-mask: EasyMode, modified by Carlos, License: GPL.
 *
 * This adaptation is GPL-3.0-or-later. Unmodified upstream sources, their
 * original notices, pinned source links and the GPL text are retained under
 * third_party_sources/libretro-crt and third_party_sources/carlos-crt.
 * Sharp scaling and Composite TV are 3SX adaptations; Composite TV is a
 * lightweight YIQ color-bleed effect, not a complete NTSC signal emulator.
 */
#include <metal_stdlib>
using namespace metal;

// Two 16-byte blocks match IOSCRTUniforms in sdl_gpu_renderer.c exactly.
struct Options {
    float4 controls; // strength, preset, output width, output height
    float4 source;   // source width, source height, frame, reserved
};
struct Input { float4 position [[position]]; float2 uv [[user(locn0)]]; };

constexpr sampler filtered(coord::normalized, address::clamp_to_edge, filter::linear);
constant float PI = 3.14159265358979323846f;

float3 fetchPixel(texture2d<float> tex, int2 pixel) {
    const int2 size(int(tex.get_width()), int(tex.get_height()));
    if (any(pixel < int2(0)) || any(pixel >= size)) return float3(0.0f);
    return tex.read(uint2(pixel), 0).rgb;
}
float2 sharpenedUV(float2 uv, float2 size) {
    float2 pixel = uv * size;
    float2 center = floor(pixel) + 0.5f;
    float2 distance = pixel - center;
    float2 sharpened = center + 4.0f * distance * distance * distance;
    sharpened.x = mix(sharpened.x, pixel.x, 0.35f);
    return sharpened / size;
}
float3 zfast(texture2d<float> tex, float2 uv, float2 size, float2 output) {
    float3 color = tex.sample(filtered, sharpenedUV(uv, size)).rgb;
    float y = fract(uv.y * size.y) - 0.5f;
    float y2 = y * y, y4 = y2 * y2;
    float darkBeam = 1.25f - 6.0f * (y2 - 2.05f * y4);
    float brightBeam = 1.0f - 8.0f * (y4 - 2.8f * y4 * y2);
    float luminance = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    float beam = mix(darkBeam, brightBeam, luminance * 0.80f);
    float mask = (uint(floor(uv.x * output.x)) & 1u) ? 0.70f : 1.0f;
    return color * beam * mask * 1.08f;
}
float gaussian(float distance, float hardness) {
    return exp2(hardness * distance * distance);
}
float3 lottesRow(texture2d<float> tex, int2 center, float2 distance, int row, int radius) {
    float3 sum(0.0f);
    float weights = 0.0f;
    for (int x = -2; x <= 2; ++x) {
        if (abs(x) > radius) continue;
        float weight = gaussian(float(x) - distance.x, -3.0f);
        sum += pow(max(fetchPixel(tex, center + int2(x, row)), 0.0f), float3(2.2f)) * weight;
        weights += weight;
    }
    return sum / max(weights, 0.0001f);
}
float2 lottesWarp(float2 uv, float strength) {
    float2 position = uv * 2.0f - 1.0f;
    position *= 1.0f + position.yx * position.yx * float2(0.045f, 0.060f) * strength;
    return position * 0.5f + 0.5f;
}
float3 lottes(texture2d<float> tex, float2 uv, float2 size, float2 outputPixel) {
    if (any(uv < float2(0.0f)) || any(uv > float2(1.0f))) return float3(0.0f);
    float2 pixel = uv * size;
    int2 center = int2(floor(pixel));
    float2 distance = fract(pixel) - 0.5f;
    float3 color = lottesRow(tex, center, distance, -1, 1) * gaussian(-1.0f - distance.y, -7.0f);
    color += lottesRow(tex, center, distance, 0, 2) * gaussian(distance.y, -7.0f);
    color += lottesRow(tex, center, distance, 1, 1) * gaussian(1.0f - distance.y, -7.0f);
    float3 mask(0.52f);
    // Keep phosphor stripes locked to display pixels while the image curves.
    uint channel = uint(floor(outputPixel.x)) % 3u;
    mask[channel] = 1.48f;
    color *= mask * 1.35f;
    float2 tube = uv * 2.0f - 1.0f;
    color *= 1.0f - 0.16f * dot(tube, tube);
    return pow(max(color, 0.0f), float3(1.0f / 2.2f));
}
float spot(float distance, float width) {
    float x = min(abs(distance) / width, 1.0f);
    float value = 1.0f - x * x;
    return value * value;
}
float3 caligari(texture2d<float> tex, float2 uv, float2 size) {
    float2 pixel = uv * size - 0.5f;
    int2 center = int2(floor(pixel));
    float2 distance = fract(pixel);
    float3 color(0.0f);
    for (int y = 0; y <= 1; ++y) {
        for (int x = 0; x <= 1; ++x) {
            float weight = spot(distance.x - float(x), 0.82f) * spot(distance.y - float(y), 0.62f);
            color += pow(max(fetchPixel(tex, center + int2(x, y)), 0.0f), float3(2.4f)) * weight;
        }
    }
    return pow(max(color * 1.55f, 0.0f), float3(1.0f / 2.2f));
}
float easyCurve(float x, float sharpness) {
    float delta = x - step(0.5f, x);
    float curved = 0.5f - sqrt(max(0.25f - delta * delta, 0.0f)) * sign(0.5f - x);
    return mix(x, curved, sharpness);
}
float3 easyMode(texture2d<float> tex, float2 uv, float2 size, float2 output) {
    float2 pixel = uv * size - 0.5f;
    int2 center = int2(floor(pixel));
    float2 distance = fract(pixel);
    float x = easyCurve(distance.x, 0.86f);
    float3 a0 = fetchPixel(tex, center), a1 = fetchPixel(tex, center + int2(1, 0));
    float3 b0 = fetchPixel(tex, center + int2(0, 1)), b1 = fetchPixel(tex, center + int2(1, 1));
    float3 color = mix(mix(a0 * a0, a1 * a1, x), mix(b0 * b0, b1 * b1, x), easyCurve(distance.y, 1.0f));
    float luminance = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    float scan = 1.0f - pow(0.5f - 0.5f * cos(2.0f * PI * distance.y), 1.5f) * 0.70f;
    color *= mix(scan, 1.0f, clamp(luminance, 0.30f, 0.65f));
    float2 maskPixel = floor(uv * output);
    uint channel = uint(floor((maskPixel.x + fmod(maskPixel.y, 2.0f) * 3.0f) / 2.0f)) % 3u;
    float3 mask(0.48f);
    mask[channel] = 1.0f;
    color *= mask;
    return pow(max(color, 0.0f), float3(1.0f / 1.8f)) * 1.22f;
}
float3 rgbToYIQ(float3 color) {
    return float3(dot(color, float3(0.299f, 0.587f, 0.114f)),
                  dot(color, float3(0.596f, -0.274f, -0.322f)),
                  dot(color, float3(0.211f, -0.523f, 0.312f)));
}
float3 yiqToRGB(float3 color) {
    return float3(color.x + 0.956f * color.y + 0.621f * color.z,
                  color.x - 0.272f * color.y - 0.647f * color.z,
                  color.x - 1.106f * color.y + 1.703f * color.z);
}
float3 composite(texture2d<float> tex, float2 uv, float2 size, float frame) {
    float2 dx(1.0f / size.x, 0.0f);
    float3 center = rgbToYIQ(tex.sample(filtered, uv).rgb);
    float3 left = rgbToYIQ(tex.sample(filtered, uv - dx).rgb);
    float3 right = rgbToYIQ(tex.sample(filtered, uv + dx).rgb);
    float3 farLeft = rgbToYIQ(tex.sample(filtered, uv - 2.0f * dx).rgb);
    float3 farRight = rgbToYIQ(tex.sample(filtered, uv + 2.0f * dx).rgb);
    // Luma retains detail while chroma bleeds across five neighboring pixels.
    float3 signal;
    signal.x = 0.80f * center.x + 0.10f * (left.x + right.x);
    signal.yz = 0.30f * center.yz + 0.24f * (left.yz + right.yz) + 0.11f * (farLeft.yz + farRight.yz);
    float carrier = sin(PI * (uv.x * size.x + floor(uv.y * size.y) * 0.5f));
    signal.x += 0.045f * carrier * length(center.yz);
    float2 pixel = floor(uv * size);
    float grain = fract(sin(dot(pixel, float2(12.9898f, 78.233f)) + frame * 0.37f) * 43758.5453f) - 0.5f;
    signal.x += grain * 0.014f;
    float beam = 0.84f + 0.16f * cos(2.0f * PI * (uv.y * size.y - 0.5f));
    return yiqToRGB(signal) * beam;
}
fragment float4 main0(Input in [[stage_in]], constant Options& options [[buffer(0)]],
                     texture2d<float> tex [[texture(0)]], sampler nearest [[sampler(0)]]) {
    float strength = clamp(options.controls.x, 0.0f, 1.0f);
    int preset = int(options.controls.y + 0.5f);
    float2 output = max(options.controls.zw, float2(1.0f));
    float2 size = max(options.source.xy, float2(1.0f));
    float2 uv = preset == 3 ? lottesWarp(in.uv, strength) : in.uv;
    float3 original = tex.sample(nearest, uv).rgb;
    if (preset == 0 || strength == 0.0f) return float4(original, 1.0f);
    float3 color = original;
    switch (preset) {
    case 1: color = tex.sample(filtered, sharpenedUV(uv, size)).rgb; break;
    case 2: color = zfast(tex, uv, size, output); break;
    case 3: color = lottes(tex, uv, size, in.uv * output); break;
    case 4: color = caligari(tex, uv, size); break;
    case 5: color = easyMode(tex, uv, size, output); break;
    case 6: color = composite(tex, uv, size, options.source.z); break;
    default: break;
    }
    return float4(mix(original, clamp(color, 0.0f, 1.0f), strength), 1.0f);
}
