#version 450

layout(push_constant) uniform Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

vec3 filmic(vec3 x) {
    // Removed max() and black level subtraction for raw speed
    return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
}

vec2 curve(vec2 uv) {
    uv = (uv - 0.5) * 2.08;
    uv *= vec2(1.0 + (uv.y * uv.y) / 64.0, 1.0 + (uv.x * uv.x) / 49.0);
    return (uv * 0.46) + 0.5;
}

void main()
{
    vec2 curved_uv = mix(curve(vTexCoord), vTexCoord, 0.80);

    // Optimized inside check: 1 max, 2 abs, 1 step (replaces 4 steps and 3 multiplies)
    vec2 ndc = curved_uv * 2.0 - 1.0;
    float inside = step(max(abs(ndc.x), abs(ndc.y)), 1.0);

    vec3 col = texture(Source, curved_uv).rgb;
    col *= col;
    col *= 1.25;

    // Simulate halation/glow
    float col_luma = dot(col, vec3(0.299, 0.587, 0.114));
    // Removed clamp on col_luma, just multiply directly
    col += col * vec3(1.1, 1.0, 0.85) * 0.15 * col_luma;

    col *= vec3(1.08, 1.02, 0.88);
    // Removed clamp(..., 0.0, 10.0). The filmic operator will safely handle overbrights.
    col = col * 1.2 + 0.65 * col * col;

    float vig = 16.0 * curved_uv.x * curved_uv.y * (1.0 - curved_uv.x) * (1.0 - curved_uv.y);
    // Removed clamp on vignette, just use absolute
    vig = 0.3 + 0.7 * abs(vig * 1.3);
    col *= vig;

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    
    // Fix Moire: Use SourceSize.y (native 240p) instead of OutputSize.y.
    // This perfectly maps exactly 1 scanline per Atari pixel.
    // Also use straight vTexCoord.y to prevent curve-induced aliasing against the pixel grid.
    float phase = fract(vTexCoord.y * params.SourceSize.y);
    float tri = abs(phase - 0.5) * 4.0 - 1.0; // Triangle wave between -1 and 1
    float fast_cos = 1.0 - (tri * tri);       // Smooth it
    
    float scans = 0.35 + 0.35 * fast_cos;
    // Removed clamp and mix() for scanline blooming. Simple addition handles it smoothly!
    scans += luma * 0.3;
    col *= scans;

    // Fast integer modulo for the grille mask instead of float mod() and steps
    int x_int = int(gl_FragCoord.x) % 3;
    vec3 grille_mask = vec3(
        x_int == 0 ? 1.0 : 0.65,
        x_int == 1 ? 1.0 : 0.65,
        x_int == 2 ? 1.0 : 0.65
    );
    col *= grille_mask;

    col = filmic(col);
    col *= inside;

    FragColor = vec4(col, 1.0);
}
