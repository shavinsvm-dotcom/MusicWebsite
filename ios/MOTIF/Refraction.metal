#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

[[ stitchable ]] half4 motifRefraction(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float time,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float2 centered = uv - 0.5;
    float radius = length(centered);
    float2 direction = normalize(centered + float2(0.0001));

    float ripple = sin(radius * 34.0 - time * 0.72) * 0.0032;
    float lensDistance = length(float2(centered.x * 1.08, centered.y * 0.86));
    float lens = 1.0 - smoothstep(0.0, 0.62, lensDistance);

    float2 offset = direction * (ripple + lens * 0.0062) * safeSize * strength;
    float2 samplePoint = position + offset;

    half4 color = layer.sample(samplePoint);
    half4 warm = layer.sample(samplePoint + direction * (1.1 * strength));
    half4 cool = layer.sample(samplePoint - direction * (1.1 * strength));

    color.r = mix(color.r, warm.r, 0.40);
    color.b = mix(color.b, cool.b, 0.40);

    half caustic = half(lens * strength) * half(0.045);
    color.rgb += half3(0.70, 0.84, 1.0) * caustic;

    return color;
}
