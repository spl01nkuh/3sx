/* Metal adaptations of Carlos' custom CRT presets:
 * https://github.com/carlosefr/retroarch-shaders
 * CRT EasyMode by EasyMode, modified for older GPUs by Carlos (License: GPL).
 * Sharp mask, noise, composite scaling and adaptive blend: GPL-2.0-or-later.
 * Original sources and presets: third_party_sources/carlos-crt/.
 * Adapted for 3SX's fixed 384x224 canvas and SDL GPU output.
 */
#include <metal_stdlib>
using namespace metal;

struct Options { float strength; float preset; float width; float height; float frame; packed_float3 padding; };
struct Input { float4 position [[position]]; float2 uv [[user(locn0)]]; };

float curve(float x, float sharp) {
    float delta = x - step(0.5f, x);
    float c = 0.5f - sqrt(max(0.25f - delta * delta, 0.0f)) * sign(0.5f - x);
    return mix(x, c, sharp);
}
float3 prepared(texture2d<float> tex, sampler s, float2 uv, bool blackCorrection, float dilation) {
    float3 c = tex.sample(s, uv).rgb;
    if (blackCorrection) c = clamp((c - 0.024f) / 0.976f, 0.0f, 1.0f);
    return c * mix(float3(1.0f), c, dilation);
}
float2 sharpUV(float2 uv, float2 size, float2 output) {
    float2 texel = uv * size;
    float2 scale = max(floor(output / size), float2(1.0f));
    float2 range = 0.5f - 0.5f / scale;
    float2 distance = fract(texel) - 0.5f;
    return (floor(texel) + (distance - clamp(distance, -range, range)) * scale + 0.5f) / size;
}

fragment float4 main0(Input in [[stage_in]], constant Options& options [[buffer(0)]],
                     texture2d<float> tex [[texture(0)]], sampler nearest [[sampler(0)]]) {
    constexpr sampler linear(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 size(384.0f, 224.0f);
    const float2 output(max(options.width, 1.0f), max(options.height, 1.0f));
    const int preset = int(options.preset);
    float3 source = tex.sample(nearest, in.uv).rgb;
    float3 color = source;

    if (preset == 10 || preset == 11) {
        // Carlos' sharp-shadowmask fast slot mask / aperture grille presets.
        color = tex.sample(linear, sharpUV(in.uv, size, output)).rgb;
        float2 pixel = in.uv * output;
        float v = step(fmod(floor(pixel.x) + 0.001f, 3.0f), 0.5f);
        float field = fract(pixel.x / 6.0f);
        float h = (field < 0.5f ? step(fmod(floor(pixel.y + 1.5f) + 0.001f, 3.0f), 0.5f)
                               : step(fmod(floor(pixel.y) + 0.001f, 3.0f), 0.5f));
        float intensity = preset == 11 ? 0.15f : 0.10f;
        color *= 1.0f - v * intensity;
        if (preset == 10) color *= 1.0f - h * intensity * 0.3f;
    } else if (preset == 12) {
        // Color-controls pass using the black-level correction from crt-scanlines.
        color = clamp((source - 0.024f) / 0.976f, 0.0f, 1.0f);
    } else if (preset == 13) {
        float2 coord = in.uv * output;
        float seed = length(coord) * 1.618f + options.frame * 0.025f;
        float noise = fract(sin(seed) * coord.x * coord.y);
        color = clamp(source + (noise - 0.5f) * (0.55f * 0.03125f) * float3(1.4f, 1.0f, 2.0f), 0.0f, 1.0f);
    } else if (preset == 14) {
        float3 left = tex.sample(nearest, in.uv - float2(1.1f / size.x, 0)).rgb;
        float3 right = tex.sample(nearest, in.uv + float2(1.1f / size.x, 0)).rgb;
        float3 neighbors = (left + right) * 0.5f;
        float contrast = abs(dot(source - neighbors, float3(0.299f, 0.587f, 0.114f)));
        color = mix(source, neighbors, 0.25f * (1.0f - smoothstep(0.0f, 0.2f, contrast)));
    } else if (preset == 15) {
        color = tex.sample(linear, sharpUV(in.uv, size, output)).rgb;
    } else {
        // CRT EasyMode Fast. Parameters follow the retained upstream presets.
        float sharpness = 0.8f, mask = 0.4f, dotWidth = 1.0f, stagger = 0.0f;
        float scanlines = 0.5f, dilation = 1.0f, boost = 1.2f;
        if (preset == 1) { mask = 0; scanlines = 0.8f; boost = 1; dotWidth = 2; stagger = 3; }
        if (preset == 3 || preset == 4 || preset == 5) { dotWidth = 2; stagger = 3; mask = 0.5f; }
        if (preset == 4) sharpness = 0.95f;
        if (preset == 5) { mask = 0.4f; scanlines = 0.3f; dilation = 0; }
        if (preset >= 6 && preset <= 9) {
            sharpness = 1; dotWidth = 2; stagger = 3;
            mask = (preset == 6 || preset == 8) ? 0.25f : 0.3f;
            scanlines = preset <= 7 ? 0.75f : 0;
            dilation = (preset == 6 || preset == 8) ? 0 : 1;
        }
        float2 pixel = in.uv * size - 0.5f;
        float2 co = (floor(pixel) + 0.5f) / size;
        float2 distance = fract(pixel);
        float x = curve(distance.x, sharpness);
        float3 a = mix(prepared(tex, nearest, co, preset == 1, dilation),
                       prepared(tex, nearest, co + float2(1.0f / size.x, 0), preset == 1, dilation), x);
        float3 b = mix(prepared(tex, nearest, co + float2(0, 1.0f / size.y), preset == 1, dilation),
                       prepared(tex, nearest, co + 1.0f / size, preset == 1, dilation), x);
        color = pow(max(mix(a, b, curve(distance.y, 1.0f)), 0.0f), float3(2.0f / (dilation + 1.0f)));
        float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
        float bright = (max(color.r, max(color.g, color.b)) + luma) * 0.5f;
        float scanBright = clamp(bright, 0.35f, 0.65f);
        float scan = 1.0f - pow(0.5f - 0.5f * cos(6.2831853f * distance.y), 1.5f) * scanlines;
        color *= mix(scan, 1.0f, scanBright);
        float2 modFac = floor(in.uv * output);
        int channel = int(fmod(floor((modFac.x + fmod(modFac.y, 2.0f) * stagger) / dotWidth), 3.0f));
        float3 weights(1.0f - mask);
        weights[uint(clamp(channel, 0, 2))] = 1.0f;
        color = pow(max(color * weights, 0.0f), float3(1.0f / 1.8f)) * boost;
    }
    return float4(mix(source, clamp(color, 0.0f, 1.0f), clamp(options.strength, 0.0f, 1.0f)), 1.0f);
}
