#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// A screen-content ripple centred on the AirPods status tile. The layer is the
// app screen captured just before the moment starts; `origin` is the tile in
// the layer's flipped (bottom-left) unit space. A soft lens bends the backdrop
// around the glass, then one shockwave rolls out across the display.
[[ stitchable ]] half4 airPodsRipple(
    float2 position,
    SwiftUI::Layer layer,
    float t,
    float2 size,
    float2 origin
) {
    if (size.x < 1.0 || size.y < 1.0) {
        return layer.sample(position);
    }

    // SwiftUI layers sample from the bottom-left, so work in a flipped
    // coordinate space and flip back when sampling.
    float2 flipped = float2(position.x, size.y - position.y);
    float2 uv = flipped / size;

    float aspect = size.x / max(size.y, 1.0);
    float pull = smoothstep(0.0, 0.45, t) * (1.0 - smoothstep(1.15, 1.95, t));

    // The glass tile bends the backdrop around itself.
    float2 lensDelta = uv - origin;
    lensDelta.x *= aspect;
    float lensDistance = length(lensDelta);
    float lensMask = 1.0 - smoothstep(0.02, 0.22, lensDistance);
    float2 lensDirection = lensDelta / max(lensDistance, 0.0001);
    uv -= lensDirection * lensMask * 0.030 * pull;

    // One shockwave rolls out from under the tile.
    float rippleT = clamp((t - 0.06) / 1.15, 0.0, 1.0);
    float2 delta = uv - origin;
    delta.x *= aspect;

    float distanceFromOrigin = length(delta);
    float radius = 0.02 + rippleT * 1.05;
    float band = (distanceFromOrigin - radius) / 0.028;
    float ring = exp(-band * band);
    float2 direction = delta / max(distanceFromOrigin, 0.0001);

    uv += direction * ring * 0.024 * (1.0 - rippleT * 0.65);
    uv = clamp(uv, float2(0.0), float2(1.0));

    // A thin neutral fringe rides the shockwave so the glass reads as a
    // physical refractor rather than a plain blur.
    float2 fringeOffset = direction * ring * 0.0035;
    float2 redUV = clamp(uv + fringeOffset, float2(0.0), float2(1.0));
    float2 blueUV = clamp(uv - fringeOffset, float2(0.0), float2(1.0));

    half4 color = layer.sample(uv * size);
    half3 fringe = half3(
        layer.sample(redUV * size).r,
        color.g,
        layer.sample(blueUV * size).b
    );
    color.rgb = mix(color.rgb, fringe, half(ring) * 0.55h);
    color.rgb += half3(0.04h) * half(ring * (1.0 - rippleT));
    return color;
}
