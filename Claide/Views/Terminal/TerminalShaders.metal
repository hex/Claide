// ABOUTME: Metal shaders for terminal grid rendering.
// ABOUTME: Vertex + fragment shaders for background quads, text glyphs, and cursor overlay.

#include <metal_stdlib>
using namespace metal;

// Per-instance data for a cell quad (background or glyph).
struct CellInstance {
    float2 position;     // Top-left corner in pixels
    float2 size;         // Cell size in pixels
    float4 color;        // RGBA color
    float4 texCoords;    // UV rect: (u0, v0, u1, v1) — zero for background-only
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float  hasTexture;   // 1.0 if texCoords are non-zero
};

// Uniforms passed per-frame.
struct Uniforms {
    float2 viewportSize;
};

vertex VertexOut cellVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CellInstance *instances [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    CellInstance inst = instances[instanceID];

    // Generate quad corners from vertex ID (0-5 for two triangles)
    // Triangle 1: 0,1,2  Triangle 2: 3,4,5
    float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),  // top-left, top-right, bottom-left
        float2(1, 0), float2(1, 1), float2(0, 1),   // top-right, bottom-right, bottom-left
    };

    float2 corner = corners[vertexID];

    // Position in pixels
    float2 pixelPos = inst.position + corner * inst.size;

    // Convert to clip space: (0,0)=top-left, (w,h)=bottom-right -> (-1,1) to (1,-1)
    float2 clipPos;
    clipPos.x = (pixelPos.x / uniforms.viewportSize.x) * 2.0 - 1.0;
    clipPos.y = 1.0 - (pixelPos.y / uniforms.viewportSize.y) * 2.0;

    VertexOut out;
    out.position = float4(clipPos, 0.0, 1.0);
    out.color = inst.color;

    // Interpolate texture coordinates
    float2 uv0 = inst.texCoords.xy;
    float2 uv1 = inst.texCoords.zw;
    out.texCoord = mix(uv0, uv1, corner);
    out.hasTexture = (uv1.x - uv0.x > 0.0001) ? 1.0 : 0.0;

    return out;
}

// Background fragment: solid color, no texture.
fragment float4 backgroundFragment(VertexOut in [[stage_in]]) {
    return in.color;
}

// Glyph fragment: alpha-blended text from atlas texture.
fragment float4 glyphFragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);

    if (in.hasTexture < 0.5) {
        return in.color;
    }

    float alpha = atlas.sample(s, in.texCoord).r;
    return float4(in.color.rgb, in.color.a * alpha);
}

// Emoji fragment: RGBA texture (not alpha-only).
fragment float4 emojiFragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);

    if (in.hasTexture < 0.5) {
        return in.color;
    }

    return atlas.sample(s, in.texCoord);
}
