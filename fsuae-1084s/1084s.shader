<?xml version="1.0" encoding="UTF-8"?>
<!--
    Commodore 1084S CRT Monitor Shader for FS-UAE

    Ported from the Amiberry 8.x built-in "1084" shader.
    The Commodore 1084S was the definitive monitor for Amiga computers —
    a 14" colour monitor based on aperture-grille CRT technology.

    Features faithfully reproduced from Amiberry's embedded shader:
      - Barrel distortion (very mild — the 1084S was nearly flat)
      - Edge-dependent RGB convergence errors
      - Horizontal sync instability (subtle — monitor-grade, not TV)
      - Halation / phosphor glow for bright areas (approximated via in-shader blur)
      - 1084S warm colour temperature: vec3(1.08, 1.02, 0.88)
      - Filmic contrast curve (level adjustment)
      - Mild vignette
      - Brightness-dependent scanlines with time animation
      - Aperture grille phosphor mask (RGB vertical stripes, Trinitron style)
      - Filmic tone mapping
      - Subtle analog noise
      - Minimal flicker

    Port notes:
      - Amiberry uniforms (backbuffer, blurbuffer, modulate, size, resolution, time)
        mapped to FS-UAE ruby* uniforms and rubyFrameCount.
      - Blur buffer approximated with a 9-tap Gaussian in-shader (adds ~9 extra
        texture reads, but the halation contribution is small and the Raspberry Pi 4
        VideoCore VI handles it fine at Amiga resolutions).
      - Frame/bezel overlay removed (FS-UAE has its own overlay system).
      - Y-flip in tsample removed (FS-UAE textures are right-side-up).

    Original shader copyright Dimitris Panokostas / Amiberry contributors.
    FS-UAE port in the public domain.
-->
<shader language="GLSL">

<vertex><![CDATA[
    uniform vec2 rubyTextureSize;
    uniform vec2 rubyInputSize;

    varying vec2 vUV; /* normalised 0..1 within the Amiga image */

    void main() {
        gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
        /* Convert to 0..1 image-normalised space for all the distortion math */
        vUV = gl_MultiTexCoord0.xy * (rubyTextureSize / rubyInputSize);
    }
]]></vertex>

<fragment><![CDATA[
    uniform sampler2D rubyTexture;
    uniform vec2 rubyTextureSize;
    uniform vec2 rubyInputSize;
    uniform vec2 rubyOutputSize;
    uniform int  rubyFrameCount;

    varying vec2 vUV;

    /* Convert image-normalised tc (0..1) back to a texture2D coordinate */
    vec2 toTex(vec2 tc) {
        return tc * (rubyInputSize / rubyTextureSize);
    }

    /* Sample with gamma decode — mirrors Amiberry's tsample().
       tc is in 0..1 image-normalised space, no y-flip needed in FS-UAE. */
    vec3 tsample(vec2 tc) {
        vec3 s = pow(abs(texture2D(rubyTexture, toTex(tc)).rgb), vec3(2.2));
        return s * 1.25;
    }

    /* 9-tap Gaussian approximation of the blur buffer used for halation.
       Radius is ~4 output pixels.  Weights sum to ~1. */
    vec3 approxBlur(vec2 tc) {
        vec2 r = 4.0 / rubyInputSize;
        vec3 s;
        s  = texture2D(rubyTexture, toTex(tc)).rgb                           * 0.2702;
        s += texture2D(rubyTexture, toTex(tc + vec2( r.x,  0.0))).rgb        * 0.1080;
        s += texture2D(rubyTexture, toTex(tc + vec2(-r.x,  0.0))).rgb        * 0.1080;
        s += texture2D(rubyTexture, toTex(tc + vec2( 0.0,  r.y))).rgb        * 0.1080;
        s += texture2D(rubyTexture, toTex(tc + vec2( 0.0, -r.y))).rgb        * 0.1080;
        s += texture2D(rubyTexture, toTex(tc + vec2( r.x,  r.y))).rgb        * 0.0495;
        s += texture2D(rubyTexture, toTex(tc + vec2(-r.x,  r.y))).rgb        * 0.0495;
        s += texture2D(rubyTexture, toTex(tc + vec2( r.x, -r.y))).rgb        * 0.0495;
        s += texture2D(rubyTexture, toTex(tc + vec2(-r.x, -r.y))).rgb        * 0.0495;
        /* Gamma decode the blur sample the same way tsample does */
        s = pow(abs(s), vec3(2.2)) * 1.25;
        return s;
    }

    /* Uncharted-2 / Hable filmic tone map — same as Amiberry */
    vec3 filmic(vec3 c) {
        vec3 x = max(vec3(0.0), c - vec3(0.004));
        return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    }

    /* Very mild barrel distortion — the 1084S had an almost-flat screen */
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
        /* Time in seconds from frame counter */
        float time = float(rubyFrameCount) / 60.0;

        vec2 uv         = vUV;
        vec2 resolution = rubyOutputSize;
        vec2 size       = rubyInputSize;

        /* ── Barrel distortion ──────────────────────────────────────────── */
        vec2 curved_uv = mix(curve(uv), uv, 0.80);
        vec2 scuv = curved_uv;

        /* ── Edge-dependent RGB convergence ─────────────────────────────── */
        vec2  center_dist = curved_uv - 0.5;
        float edge_factor = dot(center_dist, center_dist) * 4.0;

        /* ── Horizontal instability (monitor-grade: subtle) ─────────────── */
        float x = sin(0.1  * time + curved_uv.y * 13.0)
                * sin(0.23 * time + curved_uv.y * 19.0)
                * sin(0.3  + 0.11 * time + curved_uv.y * 23.0) * 0.0012;
        float o = sin(gl_FragCoord.y * 1.5) / resolution.x;
        x = x * 0.06 + o * 0.06;

        /* ── Sample RGB with convergence offset per channel ─────────────── */
        vec3 col;
        float cs = 0.0004;
        col.r = tsample(vec2(x + scuv.x + cs*(1.0 + 2.0*edge_factor),
                                 scuv.y + cs*(0.7 + 1.2*edge_factor))).r + 0.02;
        col.g = tsample(vec2(x + scuv.x, scuv.y)).g + 0.02;
        col.b = tsample(vec2(x + scuv.x - cs*(1.2 + 1.5*edge_factor),
                                 scuv.y + cs*(0.5 + 1.0*edge_factor))).b + 0.02;

        /* ── Halation: bright areas bleed through the CRT glass ─────────── */
        vec3  blurr        = approxBlur(vec2(scuv.x, scuv.y));
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
