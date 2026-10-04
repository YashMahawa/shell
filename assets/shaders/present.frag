#version 440
// Full-resolution present pass for the low-resolution fluid texture: adds a
// soft vignette and sub-LSB triangular dither so the smooth gradients do not
// band on 8-bit panels.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float vignette;
};

layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec3 colour = texture(source, qt_TexCoord0).rgb;
    vec2 q = qt_TexCoord0 - 0.5;
    colour *= 1.0 - vignette * smoothstep(0.25, 0.85, dot(q, q) * 2.0);
    float noise = hash(gl_FragCoord.xy) + hash(gl_FragCoord.xy + 17.17) - 1.0;
    colour += noise / 255.0;
    fragColor = vec4(colour, 1.0) * qt_Opacity;
}
