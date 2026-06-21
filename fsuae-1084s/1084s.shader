<?xml version="1.0" encoding="UTF-8"?>
<!--
    Commodore 1084S CRT Monitor Shader for FS-UAE — v2 (two-pass)

    Pass 1 — Horizontal 9-tap Gaussian blur → intermediate texture
    Pass 2 — 1084S CRT shader:
                rubyOrigTexture  original emulator frame  (backbuffer)
                rubyTexture      pass-1 output            (vertical blur applied
                                                           inline → full 2D Gaussian)

    This matches Amiberry's three-stage approach (H-blur pass, V-blur pass,
    main CRT shader) by folding the vertical pass into the CRT shader, reaching
    equivalent quality at 9 + (3+9) = 21 texture reads vs Amiberry's ~22.

    Fallback: git checkout v1-single-pass 1084s.shader
-->
<shader language="GLSL">

<!-- ── Shared vertex shader ──────────────────────────────────────────────── -->
<vertex><![CDATA[
    void main() {
        gl_Position  = gl_ModelViewProjectionMatrix * gl_Vertex;
        gl_TexCoord[0] = gl_MultiTexCoord0;
    }
]]></vertex>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- PASS 1 — Horizontal 9-tap Gaussian blur                                -->
<!-- ════════════════════════════════════════════════════════════════════════ -->
<fragment scale="1.0" filter="linear"><![CDATA[
    uniform sampler2D rubyTexture;
    uniform vec2 rubyTextureSize;

    /* Gaussian sigma ≈ 1.5, kernel ±4 texels */
    const float W0 = 0.2270270270;
    const float W1 = 0.1945945946;
    const float W2 = 0.1216216216;
    const float W3 = 0.0540540541;
    const float W4 = 0.0162162162;

    void main() {
        vec2  tc = gl_TexCoord[0].xy;
        float dx = 1.0 / rubyTextureSize.x;

        vec3 s = texture2D(rubyTexture, tc                       ).rgb * W0;
        s += texture2D(rubyTexture, tc + vec2( 1.0*dx, 0.0)).rgb * W1;
        s += texture2D(rubyTexture, tc + vec2(-1.0*dx, 0.0)).rgb * W1;
        s += texture2D(rubyTexture, tc + vec2( 2.0*dx, 0.0)).rgb * W2;
        s += texture2D(rubyTexture, tc + vec2(-2.0*dx, 0.0)).rgb * W2;
        s += texture2D(rubyTexture, tc + vec2( 3.0*dx, 0.0)).rgb * W3;
        s += texture2D(rubyTexture, tc + vec2(-3.0*dx, 0.0)).rgb * W3;
        s += texture2D(rubyTexture, tc + vec2( 4.0*dx, 0.0)).rgb * W4;
        s += texture2D(rubyTexture, tc + vec2(-4.0*dx, 0.0)).rgb * W4;

        gl_FragColor = vec4(s, 1.0);
    }
]]></fragment>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- PASS 2 — 1084S CRT shader                                              -->
<!--   rubyOrigTexture = original frame  →  backbuffer (with convergence)  -->
<!--   rubyTexture     = H-blurred frame →  vertical blur inline → blurbuf -->
<!-- ════════════════════════════════════════════════════════════════════════ -->
<fragment scale="1.0" filter="linear"><![CDATA[
    uniform sampler2D rubyTexture;       /* pass-1 output: H-blurred frame */
    uniform sampler2D rubyOrigTexture;   /* original emulator frame */
    uniform vec2      rubyTextureSize;
    uniform vec2      rubyInputSize;
    uniform vec2      rubyOutputSize;
    uniform int       rubyFrameCount;

    /* Gaussian weights — must match pass 1 for isotropic result */
    const float W0 = 0.2270270270;
    const float W1 = 0.1945945946;
    const float W2 = 0.1216216216;
    const float W3 = 0.0540540541;
    const float W4 = 0.0162162162;

    /* 0..1 image-normalised UV from raw texture coord */
    vec2 uvNorm(vec2 tc) {
        return tc * (rubyTextureSize / rubyInputSize);
    }

    /* 0..1 image-normalised → texture2D sample coord */
    vec2 toTex(vec2 uv) {
        return uv * (rubyInputSize / rubyTextureSize);
    }

    /* Sample original frame with gamma decode — Amiberry's tsample() */
    vec3 tsample(vec2 uv) {
        vec3 s = pow(abs(texture2D(rubyOrigTexture, toTex(uv)).rgb), vec3(2.2));
        return s * 1.25;
    }

    /* Vertical 9-tap Gaussian on the H-blurred texture.
       Combined with pass 1 this is a separable 2D Gaussian — exact
       structural match to Amiberry's two dedicated blur passes. */
    vec3 blurbuffer(vec2 uv) {
        vec2  tc = toTex(uv);
        float dy = 1.0 / rubyTextureSize.y;

        vec3 s = texture2D(rubyTexture, tc                       ).rgb * W0;
        s += texture2D(rubyTexture, tc + vec2(0.0,  1.0*dy)).rgb * W1;
        s += texture2D(rubyTexture, tc + vec2(0.0, -1.0*dy)).rgb * W1;
        s += texture2D(rubyTexture, tc + vec2(0.0,  2.0*dy)).rgb * W2;
        s += texture2D(rubyTexture, tc + vec2(0.0, -2.0*dy)).rgb * W2;
        s += texture2D(rubyTexture, tc + vec2(0.0,  3.0*dy)).rgb * W3;
        s += texture2D(rubyTexture, tc + vec2(0.0, -3.0*dy)).rgb * W3;
        s += texture2D(rubyTexture, tc + vec2(0.0,  4.0*dy)).rgb * W4;
        s += texture2D(rubyTexture, tc + vec2(0.0, -4.0*dy)).rgb * W4;

        return pow(abs(s), vec3(2.2)) * 1.25;
    }

    vec3 filmic(vec3 c) {
        vec3 x = max(vec3(0.0), c - vec3(0.004));
        return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    }

    /* Very mild barrel — the 1084S screen was nearly flat */
    vec2 curve(vec2 uv) {
        uv = (uv - 0.5) * 2.0;
        uv *= 1.04;
        uv.x *= 1.0 + pow(abs(uv.y) / 8.0, 2.0);
        uv.y *= 1.0 + pow(abs(uv.x) / 7.0, 2.0);
        uv = (uv / 2.0) + 0.5;
        uv = uv * 0.92 + 0.04;
        return uv;
    }

    float rand(vec2 co) {
        return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
    }

    void main() {
        float time       = float(rubyFrameCount) / 60.0;
        vec2  uv         = uvNorm(gl_TexCoord[0].xy);
        vec2  resolution = rubyOutputSize;
        vec2  size       = rubyInputSize;

        /* ── Barrel distortion ──────────────────────────────────────────── */
        vec2 curved_uv = mix(curve(uv), uv, 0.80);
        vec2 scuv = curved_uv;

        /* ── Edge-dependent RGB convergence ─────────────────────────────── */
        vec2  center_dist = curved_uv - 0.5;
        float edge_factor = dot(center_dist, center_dist) * 4.0;

        /* ── Horizontal instability (monitor-grade: very subtle) ─────────── */
        float x = sin(0.1  * time + curved_uv.y * 13.0)
                * sin(0.23 * time + curved_uv.y * 19.0)
                * sin(0.3  + 0.11 * time + curved_uv.y * 23.0) * 0.0012;
        float o = sin(gl_FragCoord.y * 1.5) / resolution.x;
        x = x * 0.06 + o * 0.06;

        /* ── Sample RGB with convergence offset per channel ─────────────── */
        vec3  col;
        float cs = 0.0004;
        col.r = tsample(vec2(x + scuv.x + cs*(1.0 + 2.0*edge_factor),
                                 scuv.y + cs*(0.7 + 1.2*edge_factor))).r + 0.02;
        col.g = tsample(vec2(x + scuv.x, scuv.y)).g + 0.02;
        col.b = tsample(vec2(x + scuv.x - cs*(1.2 + 1.5*edge_factor),
                                 scuv.y + cs*(0.5 + 1.0*edge_factor))).b + 0.02;

        /* ── Halation — separable 2D Gaussian (H in pass 1, V here) ────── */
        vec3  blurr        = blurbuffer(vec2(scuv.x, scuv.y));
        float blur_luma    = dot(blurr, vec3(0.299, 0.587, 0.114));
        vec3  halation_col = blurr * vec3(1.1, 1.0, 0.85);
        col += halation_col * 0.12 * smoothstep(0.15, 0.8, blur_luma);
        col += blurr * 0.04;

        /* ── 1084S warm colour temperature ──────────────────────────────── */
        col *= vec3(1.08, 1.02, 0.88);

        /* ── Level adjustment / contrast curve ──────────────────────────── */
        col = clamp(col * 1.2
                  + 0.65 * col * col
                  + 1.1  * col * col * col * col * col,
                    vec3(0.0), vec3(10.0));

        /* ── Vignette — mild for a monitor ──────────────────────────────── */
        float vig = 0.3 + 16.0 * curved_uv.x * curved_uv.y
                                * (1.0 - curved_uv.x) * (1.0 - curved_uv.y);
        vig = 1.2 * pow(vig, 0.4);
        col *= vig;

        /* ── Brightness-dependent scanlines (time-animated) ─────────────── */
        float luma          = dot(col, vec3(0.299, 0.587, 0.114));
        float scanline_phase = curved_uv.y * size.y * 1.5;
        float scans         = clamp(0.35 + 0.35 * sin(1.5*time + scanline_phase),
                                    0.0, 1.0);
        float s             = pow(scans, 0.9);
        float scan_reduce   = smoothstep(0.0, 0.7, luma);
        s = mix(s, 1.0, scan_reduce * 0.65);
        col *= s;

        /* ── Aperture grille: vertical RGB phosphor stripes ─────────────── */
        float stripe = mod(gl_FragCoord.x, 3.0);
        vec3 grille;
        if (stripe < 1.0)
            grille = vec3(1.0, 0.65, 0.65);
        else if (stripe < 2.0)
            grille = vec3(0.65, 1.0, 0.65);
        else
            grille = vec3(0.65, 0.65, 1.0);
        col *= grille;

        /* ── Filmic tone mapping ─────────────────────────────────────────── */
        col = filmic(col);

        /* ── Subtle analog noise ─────────────────────────────────────────── */
        vec2 seed = curved_uv * resolution;
        col -= 0.008 * pow(vec3(rand(seed + time),
                                rand(seed + time * 2.0),
                                rand(seed + time * 3.0)), vec3(1.5));

        /* ── Minimal power-supply flicker ───────────────────────────────── */
        col *= 1.0 - 0.001 * (sin(50.0*time + curved_uv.y*2.0) * 0.5 + 0.5);

        /* ── Clamp to screen boundary ────────────────────────────────────── */
        if (curved_uv.x < 0.0 || curved_uv.x > 1.0 ||
            curved_uv.y < 0.0 || curved_uv.y > 1.0)
            col = vec3(0.0);

        gl_FragColor = vec4(col, 1.0);
    }
]]></fragment>

</shader>
