#version 440
// Apple Music style flowing artwork backdrop. Several mirrored, slowly
// rotating copies of a pre-blurred artwork texture are blended with soft
// weights around drifting centres, then domain-warped. Rendered into a small
// offscreen texture, so the cost is independent of the screen resolution.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float mixAmount;
    float saturation;
    float brightness;
};

layout(binding = 1) uniform sampler2D artA;
layout(binding = 2) uniform sampler2D artB;

vec2 rotate2(vec2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec2 mirror(vec2 p) {
    return 1.0 - abs(1.0 - mod(p, 2.0));
}

vec3 art(vec2 uv) {
    return mix(texture(artA, uv).rgb, texture(artB, uv).rgb, mixAmount);
}

vec3 copyAt(vec2 p, vec2 centre, float scale, float angle) {
    return art(mirror(rotate2(p - centre, angle) / scale + 0.5));
}

void main() {
    float t = time;
    vec2 p = qt_TexCoord0 - 0.5;
    p.x *= aspect;

    // Gentle domain warp keeps the colour fields liquid rather than rigid.
    p += 0.075 * vec2(sin(p.y * 2.4 + t * 0.19), cos(p.x * 2.0 - t * 0.16));
    p += 0.035 * vec2(sin(p.y * 5.1 - t * 0.11), cos(p.x * 4.3 + t * 0.13));

    vec2 c0 = vec2(0.42 * sin(t * 0.051), 0.28 * cos(t * 0.067));
    vec2 c1 = vec2(-0.48 * cos(t * 0.043 + 1.3), 0.31 * sin(t * 0.058 + 0.4));
    vec2 c2 = vec2(0.52 * sin(t * 0.033 + 2.1), -0.33 * cos(t * 0.041 + 0.9));
    vec2 c3 = vec2(-0.36 * sin(t * 0.047 + 3.7), -0.27 * sin(t * 0.037 + 2.2));

    vec3 a = copyAt(p, c0, 1.85, t * 0.031);
    vec3 b = copyAt(p, c1, 1.35, -t * 0.044 + 1.7);
    vec3 c = copyAt(p, c2, 2.30, t * 0.022 + 3.1);
    vec3 d = copyAt(p, c3, 1.15, -t * 0.038 + 4.4);

    float w0 = exp(-dot(p - c0, p - c0) * 2.2);
    float w1 = exp(-dot(p - c1, p - c1) * 2.6);
    float w2 = exp(-dot(p - c2, p - c2) * 1.8);
    float w3 = exp(-dot(p - c3, p - c3) * 3.0);
    float base = 0.18;
    vec3 colour = (a * (w0 + base) + b * (w1 + base) + c * (w2 + base) + d * (w3 + base))
        / (w0 + w1 + w2 + w3 + 4.0 * base);

    float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
    colour = mix(vec3(luma), colour, saturation);
    // Compress highlights so white lyrics stay legible on bright artwork.
    colour = colour * brightness / (1.0 + 0.55 * colour);

    fragColor = vec4(colour, 1.0) * qt_Opacity;
}
