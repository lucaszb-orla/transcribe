#include <metal_stdlib>
using namespace metal;

static float circularDistance(float a, float b) {
    float distance = abs(a - b);
    return min(distance, 1.0 - distance);
}

static float perimeterPosition(float2 uv) {
    float top = uv.y;
    float right = 1.0 - uv.x;
    float bottom = 1.0 - uv.y;
    float left = uv.x;
    float nearestEdge = min(min(top, right), min(bottom, left));

    if (nearestEdge == top) {
        return uv.x * 0.25;
    }
    if (nearestEdge == right) {
        return 0.25 + uv.y * 0.25;
    }
    if (nearestEdge == bottom) {
        return 0.5 + (1.0 - uv.x) * 0.25;
    }
    return 0.75 + (1.0 - uv.y) * 0.25;
}

[[ stitchable ]]
half4 chromeBorder(float2 position, float2 size, float time, float progress) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = clamp(position / safeSize, 0.0, 1.0);
    float perimeter = perimeterPosition(uv);

    float center = fract(time / 14.0 + clamp(progress, 0.0, 1.0) * 0.27);
    float highlight = exp(-pow(circularDistance(perimeter, center) / 0.055, 2.0));
    float warmReflection = exp(-pow(circularDistance(perimeter, fract(center + 0.085)) / 0.032, 2.0));
    float cyanReflection = exp(-pow(circularDistance(perimeter, fract(center - 0.07)) / 0.026, 2.0));

    float brushed = 0.5 + 0.5 * sin(position.x * 0.17 + position.y * 0.11);
    float silverLevel = 0.48 + brushed * 0.12 + highlight * 0.48;
    float3 color = mix(float3(0.18, 0.20, 0.23), float3(0.93, 0.95, 0.97), silverLevel);
    color += warmReflection * float3(0.42, 0.18, 0.035);
    color += cyanReflection * float3(0.02, 0.22, 0.34);
    color += highlight * 0.24;

    return half4(half3(clamp(color, 0.0, 1.0)), 1.0h);
}
