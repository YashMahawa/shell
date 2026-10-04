#version 440
// Sweeps a soft-edged highlight across one sung word. The source is the word
// rendered in white; unsung glyphs are drawn at `dim` opacity.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float softness;
    float dim;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 glyph = texture(source, qt_TexCoord0);
    float edge = progress * (1.0 + 2.0 * softness) - softness;
    float lit = 1.0 - smoothstep(edge - softness, edge + softness, qt_TexCoord0.x);
    fragColor = glyph * mix(dim, 1.0, lit) * qt_Opacity;
}
