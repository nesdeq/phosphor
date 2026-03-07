#version 460 core

#include <flutter/runtime_effect.glsl>

// Uniforms
uniform vec2 uResolution;         // 0, 1
uniform float uTime;              // 2
uniform float uCurvature;         // 3
uniform float uScanlineIntensity; // 4
uniform float uGlowStrength;      // 5
uniform float uChromAberration;   // 6
uniform float uFlickerIntensity;  // 7
uniform float uVignetteStrength;  // 8
uniform sampler2D uTerminalTexture; // sampler 0

out vec4 fragColor;

// Barrel distortion for CRT screen curvature
vec2 curveUV(vec2 uv) {
    vec2 centered = uv - 0.5;
    float dist = dot(centered, centered);
    return uv + centered * dist * uCurvature;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;

    // --- Barrel distortion ---
    vec2 curved = curveUV(uv);

    // Discard fragments outside the curved screen area
    if (curved.x < 0.0 || curved.x > 1.0 || curved.y < 0.0 || curved.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // --- Chromatic aberration ---
    float aberr = uChromAberration;
    float r = texture(uTerminalTexture, curved + vec2(aberr, 0.0)).r;
    float g = texture(uTerminalTexture, curved).g;
    float b = texture(uTerminalTexture, curved - vec2(aberr, 0.0)).b;
    vec3 color = vec3(r, g, b);

    // --- Scanlines ---
    // Create horizontal scanlines that darken every other pixel row
    float scanline = sin(curved.y * uResolution.y * 3.14159265) * 0.5 + 0.5;
    scanline = pow(scanline, 1.5); // sharpen the scanline edges
    color *= mix(1.0, scanline, uScanlineIntensity);

    // --- Phosphor glow / bloom approximation ---
    // Sample neighboring pixels for a simple box blur glow
    vec2 texel = 1.0 / uResolution;
    vec3 bloom = vec3(0.0);
    bloom += texture(uTerminalTexture, curved + vec2(-texel.x, 0.0)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(texel.x, 0.0)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(0.0, -texel.y)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(0.0, texel.y)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(-texel.x, -texel.y)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(texel.x, -texel.y)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(-texel.x, texel.y)).rgb;
    bloom += texture(uTerminalTexture, curved + vec2(texel.x, texel.y)).rgb;
    bloom /= 8.0;
    color += bloom * uGlowStrength;

    // --- Flicker ---
    // Subtle brightness oscillation simulating unstable power
    float flicker = 1.0 - uFlickerIntensity * 0.5
        + uFlickerIntensity * 0.5 * sin(uTime * 7.0 + sin(uTime * 13.0) * 0.5);
    color *= flicker;

    // --- Vignette ---
    // Gentle darkening at edges — keep corners readable
    vec2 vignetteCoord = curved - 0.5;
    float vignette = 1.0 - dot(vignetteCoord, vignetteCoord) * (0.8 + uVignetteStrength * 0.8);
    vignette = clamp(vignette, 0.3, 1.0);
    color *= vignette;

    // --- Subtle horizontal line noise ---
    float noise = fract(sin(dot(vec2(uTime * 0.1, curved.y * 100.0), vec2(12.9898, 78.233))) * 43758.5453);
    color *= 0.98 + 0.02 * noise;

    // Flutter requires premultiplied alpha output
    fragColor = vec4(color, 1.0);
}
