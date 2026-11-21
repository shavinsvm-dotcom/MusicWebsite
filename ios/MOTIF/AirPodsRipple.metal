#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// A one-shot liquid pull and radial shockwave for the AirPods connection
// moment. The layer is the current app screen captured just before the
// moment begins; the effect is strongest near the top and settles by t = 2.2.
[[ stitchable ]] half4 airPodsRipple(float2 position, SwiftUI::Layer layer, float t, float2 size) {
    if (size.x < 1.0 || size.y < 1.0) {
        return layer.sample(position);
    }

    // SwiftUI layers sample from the bottom-left, so work in a flipped
    // coordinate space and flip back when sampling.
    float2 flipped = float2(position.x, size.y - position.y);
    float2 uv = flipped / size;

    // The top of the screen pulls toward the Dynamic Island, then relaxes.
    float pull = smoothstep(0.0, 0.55, t) * (1.0 - smoothstep(1.15, 1.95, t));
    float top = smoothstep(0.28, 1.0, uv.y);
    uv.y -= 0.075 * pull * top * top;
    uv.x += (uv.x - 0.5) * 0.060 * pull * top;

    // A single shockwave rolls out from the meeting point of the two nodes.
    float rippleT = clamp((t - 0.88) / 0.95, 0.0, 1.0);
    float2 center = float2(0.5, 0.64);
    float2 delta = uv - center;
    delta.x *= size.x / max(size.y, 1.0);

    float distanceFromCenter = length(delta);
    float radius = 0.08 + rippleT * 0.46;
    float band = (distanceFromCenter - radius) / 0.035;
    float ring = exp(-band * band);
    float2 direction = delta / max(distanceFromCenter, 0.0001);

    uv += direction * ring * 0.038 * (1.0 - rippleT * 0.70);
    uv = clamp(uv, float2(0.0), float2(1.0));

    half4 color = layer.sample(uv * size);
    color.rgb += half3(0.05h, 0.16h, 0.30h) * (half(ring) * half(1.0 - rippleT));
    return color;
}
