#version 440

// ASCII jellyfish ocean. Density per grid cell picks a glyph from the atlas;
// coordinates are global so the ocean continues across monitors.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float glyphs;
    vec2 resolution;
    vec2 origin;
    vec2 world;
    vec2 cell;
    vec4 tint;
    vec4 tint2;
    vec4 tint3;
    vec4 base;
};

layout(binding = 1) uniform sampler2D atlas;

#define T (time * 1.3)

const int JELLIES = 12;
const int TENTACLES = 6;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Returns density in x, colour (0 cyan, 1 purple, 2 yellow) in y.
vec2 jelly(int i, vec2 p) {
    float fi = float(i);
    float size = mix(150.0, 270.0, hash(vec2(fi, 3.1)));
    float rise = mix(8.0, 16.0, hash(vec2(fi, 5.3)));
    float span = world.y + size * 4.6;
    float cy = world.y + size * 1.2 - mod(T * rise + fract(fi * 0.618034) * span, span);
    float cx = (fi + 0.5 + 0.6 * (hash(vec2(fi, 7.9)) - 0.5)) / float(JELLIES) * world.x
             + sin(T * 0.07 + fi * 1.3) * size * 0.8;

    float pulse = sin(T * mix(0.7, 1.1, hash(vec2(fi, 9.4))) + fi * 2.0);
    float wx = 1.0 + 0.09 * pulse;
    float hy = 1.0 - 0.07 * pulse;

    vec2 d = (p - vec2(cx, cy)) / size;
    float a = 0.18 * sin(T * 0.13 + fi);
    d = mat2(cos(a), -sin(a), sin(a), cos(a)) * d;
    if (d.y < -1.2 || d.y > 3.4 || abs(d.x) > 1.6) return vec2(0.0);

    float grain = noise(p / cell * 0.55 + vec2(fi * 7.0, T * 0.25));
    float density = 0.0;

    float rx = 1.0 * wx;
    float ry = 0.95 * hy;
    float e = pow(d.x / rx, 2.0) + pow(d.y / ry, 2.0);
    float lip = 0.1 + 0.05 * sin(d.x * 16.0 + T * 1.8);
    if (d.y < lip) {
        float shell = smoothstep(1.0, 0.86, e);
        float top = 1.0 - smoothstep(-ry, lip, d.y);
        float rim = smoothstep(0.55, 0.9, e) * shell;
        density = max(density, shell * (0.38 + 0.5 * top + 0.25 * rim) * (0.65 + 0.55 * grain));
    }

    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float x0 = (fk - 1.0) * 0.24 * wx;
        float sway = sin(d.y * 3.8 - T * 1.4 + fk * 2.1 + fi) * 0.13 * d.y;
        float w = 0.11 * (1.0 - 0.45 * clamp(d.y / 1.6, 0.0, 1.0));
        float arm = smoothstep(w, w * 0.25, abs(d.x - x0 - sway))
                  * smoothstep(0.02, 0.14, d.y) * smoothstep(1.7, 1.0, d.y);
        density = max(density, arm * 0.5 * (0.55 + 0.6 * grain));
    }

    float line = cell.x * 0.55 / size;
    for (int m = 0; m < TENTACLES; m++) {
        float fm = float(m);
        float len = 1.9 + 1.3 * hash(vec2(fi, fm));
        float t = d.y / len;
        float x0 = mix(-0.88, 0.88, fm / float(TENTACLES - 1)) * wx;
        float sway = sin(d.y * 2.6 - T * (0.9 + 0.3 * hash(vec2(fm, fi))) + fm * 1.7) * 0.3 * t;
        float tent = smoothstep(line, 0.0, abs(d.x - x0 - sway))
                   * step(0.08, d.y) * (1.0 - smoothstep(0.55, 1.0, t));
        density = max(density, tent * 0.24);
    }

    return vec2(density, mod(fi, 3.0));
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    vec2 global = origin + px;
    vec2 id = floor(global / cell);
    vec2 center = (id + 0.5) * cell;
    vec2 local = global - id * cell;

    float density = 0.0;
    float hue = 0.0;
    for (int i = 0; i < JELLIES; i++) {
        vec2 j = jelly(i, center);
        if (j.x > density) {
            density = j.x;
            hue = j.y;
        }
    }

    float epoch = floor(T * 0.35 + hash(id) * 7.0);
    float plankton = hash(id * 1.31 + vec2(epoch * 17.13, epoch * 3.71));
    if (density < 0.05 && plankton > 0.9965) density = 0.1;
    density = clamp(density, 0.0, 1.0);

    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    vec3 color = base.rgb * (1.0 - 0.35 * dot(uv * 0.6, uv * 0.6));

    float edge = step(local.x, 1.0) + step(local.y, 1.0);
    color += vec3(0.6, 0.85, 0.9) * 0.018 * min(edge, 1.0);

    if (density > 0.05) {
        vec3 glow = hue < 0.5 ? tint.rgb : hue < 1.5 ? tint2.rgb : tint3.rgb;
        float flicker = (hash(id + floor(T * 2.5)) - 0.5) * 0.18;
        float g = clamp(floor((density + flicker) * (glyphs - 1.0) + 0.5), 1.0, glyphs - 1.0);
        vec2 inset = step(vec2(1.0), local) * step(local, cell - 1.0);
        float box = inset.x * inset.y;
        float ink = texture(atlas, vec2((g + local.x / cell.x) / glyphs, local.y / cell.y)).a;
        bool solid = density > 0.86;

        vec3 fill = glow * (solid ? 0.85 : 0.07 + 0.32 * density);
        color = mix(color, fill, box * (solid ? 1.0 : 0.9));
        vec3 glyph = solid ? base.rgb : mix(glow, vec3(0.95, 1.0, 1.0), density * 0.6);
        color = mix(color, glyph, ink * (0.35 + 0.65 * density));
    }

    fragColor = vec4(color, 1.0) * qt_Opacity;
}
