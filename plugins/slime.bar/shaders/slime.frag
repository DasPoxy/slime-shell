#version 440

// Slime skin: the bar, its drips and the control-centre panel are one signed
// distance field, blended with smooth-min so everything reads as a single
// body of ooze. Coordinates are window pixels, y pointing down.
//
// shadingStyle: 0 = soft (smooth lighting), 1 = anime (cel bands, ink line,
// hard wet highlights), 2 = manga (anime + halftone screentone everywhere),
// 3 = print (risograph/mural: jagged hue-shifted shadows, terminator ink,
// hatching, halftone transitions, paper grain, misregistered colour plate).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float barHeight;
    float openProgress;
    float dripAmount;
    float shadingStyle;
    vec2 resolution;
    vec4 panelRect;   // x, unused, width, full height
    vec4 slimeColor;
    vec4 slimeColor2; // gradient partner; equal to slimeColor for none
    vec4 paperColor;  // the theme's lightest tone, showing through print gaps
    // Panel windows reuse this shader: draw only below clipTop and inside
    // cullRect (xMin, xMax, yMax, enabled), and sink the panel's interior into
    // a darker pool (poolDepth) so stock panel text stays readable.
    vec4 cullRect;
    float clipTop;
    float poolDepth;
    vec2 origin;      // this window's top-left in bar coordinates (popups)
    float blobMode;   // 1 = no bar: just a free-standing blob in panelRect
                      //     (x, y, w, h) with drips off its bottom edge
    vec4 bulb0;       // floating widgets: x, y, width, height (width 0 = unused)
    vec4 bulb1;
    vec4 bulb2;
    vec4 bulb3;
    vec4 bulb4;
    vec4 bulb5;
    vec4 bulb6;
    vec4 bulb7;
    vec4 bulb8;
    vec4 bulb9;
    vec4 bulb10;
    vec4 bulb11;
    vec4 bulb12;
    vec4 bulb13;
    vec4 bulb14;
    vec4 bulb15;
};

const float CELL = 64.0;
// Light comes from the upper left; AWAY points to where the shadows fall.
const vec2 AWAY = vec2(0.7, 0.714);

float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

float hash2(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
               mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 7.3) + 0.15 * vnoise(p * 4.3 + 1.9);
}


float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float sdSegment(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float sdRoundBox(vec2 p, vec2 c, vec2 halfSize, float r) {
    vec2 q = abs(p - c) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdEllipse(vec2 p, vec2 c, vec2 r) {
    vec2 q = (p - c) / r;
    return (length(q) - 1.0) * min(r.x, r.y);
}

float barEdge(float x) {
    return barHeight
        + 3.0 * sin(x * 0.011 + time * 0.6)
        + 2.0 * sin(x * 0.027 - time * 0.9 + 1.3);
}

// One drip hanging from edgeY: it slowly stretches, lets a droplet go, and
// the neck snaps back up. `scale` shrinks drips on a hs-open panel.
// Returns (shape distance, distance to its sparkle highlights).
vec2 drip(vec2 p, float cx, float edgeY, float seed, float scale) {
    float speed = 0.06 + 0.09 * hash(seed + 1.0);
    float s = fract(time * speed + hash(seed + 2.0));
    float maxLen = scale * dripAmount * (12.0 + 48.0 * hash(seed + 3.0));
    float neck = 3.5 + 4.0 * hash(seed + 4.0);

    float grow = smoothstep(0.0, 0.8, s);
    float release = smoothstep(0.8, 1.0, s);
    float len = maxLen * grow * grow * (1.0 - release);
    float bulb = (neck + 3.0 + 6.0 * grow) * (1.0 - release);

    vec2 top = vec2(cx, edgeY - 6.0);
    vec2 tip = vec2(cx, edgeY + len);
    float d = sdSegment(p, top, tip, neck * (1.0 - 0.6 * release));
    d = smin(d, length(p - tip) - bulb, 8.0);

    // Anime wet-look sparkle: a tilted oval up-left on the bulb, a dot below.
    float hl = 1e5;
    if (bulb > 5.0) {
        hl = sdEllipse(p, tip + vec2(-0.38, -0.3) * bulb, vec2(0.16, 0.3) * bulb);
        hl = min(hl, length(p - (tip + vec2(0.3, 0.42) * bulb)) - 0.1 * bulb);
    }

    if (release > 0.0) {
        float fall = (s - 0.8) / 0.2;
        vec2 drop = vec2(cx, edgeY + maxLen + fall * fall * 240.0);
        float dr = (neck + 6.0) * (1.0 - 0.5 * fall);
        d = min(d, length(p - drop) - dr);
        hl = min(hl, sdEllipse(p, drop + vec2(-0.35, -0.3) * dr, vec2(0.18, 0.32) * dr));
    }
    return vec2(d, hl);
}

// A widget bulb: the ooze sagging under a floating widget (b = the widget's
// rect), gently breathing, with a drip or two hanging from its belly.
const float BULB_HANG = 20.0;

vec2 bulb(vec2 p, vec4 b, float seed) {
    if (b.z <= 0.0 || abs(p.x - (b.x + b.z * 0.5)) > b.z * 0.5 + 70.0) return vec2(1e5);
    float sag = 1.5 * sin(time * 0.8 + seed * 2.3);
    vec2 hs = vec2(b.z * 0.5, (b.w + BULB_HANG + sag) * 0.5);
    vec2 c = vec2(b.x + hs.x, b.y + hs.y);
    float d = sdRoundBox(p, c, hs, hs.y);
    // heavier belly: the goo pools toward the bottom middle
    d = smin(d, sdEllipse(p, vec2(c.x, c.y + hs.y * 0.45), vec2(hs.x * 0.75, hs.y * 0.8)), 6.0);

    float hl = 1e5;
    float bottom = c.y + hs.y - 3.0;
    float span = max(hs.x - hs.y * 0.6, 4.0);
    for (int k = 0; k < 2; k++) {
        float sk = seed * 17.0 + float(k) * 5.0 + 200.0;
        if (k == 1 && hash(sk + 0.5) < 0.5) break;
        float x = c.x + (hash(sk) * 2.0 - 1.0) * span;
        vec2 dr = drip(p, x, bottom, sk, 0.75);
        d = smin(d, dr.x, 7.0);
        hl = min(hl, dr.y);
    }
    return vec2(d, hl);
}

// A free-standing blob (blobMode): a gooey dome in panelRect that wobbles a
// little and drips from its underside.
vec2 mapBlob(vec2 p) {
    vec2 c = panelRect.xy + panelRect.zw * 0.5;
    vec2 hs = panelRect.zw * 0.5;
    float wob = 2.0 * sin(p.x * 0.05 + time * 1.3) + 1.5 * sin(p.y * 0.07 - time * 0.9);
    float d = sdRoundBox(p, c, hs, min(hs.y, 46.0)) + wob * 0.4;
    // heavier bottom: goo pools downward
    d = smin(d, sdEllipse(p, vec2(c.x, c.y + hs.y * 0.45), vec2(hs.x * 0.85, hs.y * 0.6)), 10.0);

    float hl = 1e5;
    float bottom = panelRect.y + panelRect.w - 6.0;
    float ci = floor(p.x / CELL);
    for (int k = -1; k <= 1; k++) {
        float i = ci + float(k);
        if (hash(i * 5.3 + 71.0) < 0.35) continue;
        float dx = (i + 0.5 + (hash(i + 40.0) - 0.5) * 0.6) * CELL;
        if (abs(dx - c.x) > hs.x - 30.0) continue;
        vec2 dr = drip(p, dx, bottom, i + 300.0, 0.8);
        d = smin(d, dr.x, 9.0);
        hl = min(hl, dr.y);
    }
    return vec2(d, hl);
}

vec2 mapScene(vec2 p) {
    if (blobMode > 0.5) return mapBlob(p);
    float d = p.y - barEdge(p.x);
    float hl = 1e5;
    float ci = floor(p.x / CELL);

    for (int k = -1; k <= 1; k++) {
        float i = ci + float(k);
        if (hash(i * 3.7 + 11.0) < 0.3) continue;
        float cx = (i + 0.5 + (hash(i) - 0.5) * 0.6) * CELL;
        vec2 dr = drip(p, cx, barEdge(cx), i, 1.0);
        d = smin(d, dr.x, 12.0);
        hl = min(hl, dr.y);
    }

    vec2 bs;
    bs = bulb(p, bulb0, 1.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb1, 2.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb2, 3.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb3, 4.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb4, 5.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb5, 6.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb6, 7.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb7, 8.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb8, 9.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb9, 10.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb10, 11.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb11, 12.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb12, 13.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb13, 14.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb14, 15.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb15, 16.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);

    if (openProgress > 0.001) {
        // Opens like a fat drip: a narrow bead falls first, then spreads
        // sideways into the panel body.
        float o = openProgress;
        float h = max(panelRect.w * smoothstep(0.0, 0.75, o), 2.0);
        float w = mix(40.0, panelRect.z, smoothstep(0.35, 1.0, o));
        float cx = panelRect.x + panelRect.z * 0.5;
        float r = min(min(w, h) * 0.5, 22.0);
        float pd = sdRoundBox(p, vec2(cx, barHeight + h * 0.5), vec2(w * 0.5, h * 0.5), r);
        d = smin(d, pd, 26.0);

        float bottom = barHeight + h;
        float reach = w * 0.5 - r;
        for (int k = -1; k <= 1; k++) {
            float i = ci + float(k);
            if (hash(i * 5.3 + 71.0) < 0.35) continue;
            float dx = (i + 0.5 + (hash(i + 40.0) - 0.5) * 0.6) * CELL;
            if (abs(dx - cx) > reach) continue;
            vec2 dr = drip(p, dx, bottom, i + 100.0, smoothstep(0.6, 1.0, o) * 1.3);
            d = smin(d, dr.x, 8.0);
            hl = min(hl, dr.y);
        }
    }
    return vec2(d, hl);
}

float fill(float dist) { return clamp(0.5 - dist, 0.0, 1.0); }

// 1 inside the calm centre of a widget bulb, where text and icons sit.
// Soft, feathered calm zone around a floating widget: texture thins out
// toward it without leaving a visible pill edge.
float labelOf(vec2 p, vec4 b) {
    if (b.z <= 0.0 || abs(p.x - (b.x + b.z * 0.5)) > b.z * 0.5 + 12.0) return 0.0;
    vec2 hs = b.zw * 0.5 + vec2(2.0, 0.0);
    return 1.0 - smoothstep(-4.0, 10.0, sdRoundBox(p, b.xy + b.zw * 0.5, hs, hs.y));
}

float labelZone(vec2 p) {
    float l = 0.0;
    l = max(l, labelOf(p, bulb0));
    l = max(l, labelOf(p, bulb1));
    l = max(l, labelOf(p, bulb2));
    l = max(l, labelOf(p, bulb3));
    l = max(l, labelOf(p, bulb4));
    l = max(l, labelOf(p, bulb5));
    l = max(l, labelOf(p, bulb6));
    l = max(l, labelOf(p, bulb7));
    l = max(l, labelOf(p, bulb8));
    l = max(l, labelOf(p, bulb9));
    l = max(l, labelOf(p, bulb10));
    l = max(l, labelOf(p, bulb11));
    l = max(l, labelOf(p, bulb12));
    l = max(l, labelOf(p, bulb13));
    l = max(l, labelOf(p, bulb14));
    l = max(l, labelOf(p, bulb15));
    return l;
}

// Scattered wet glints: a jittered grid where each cell may hold a tapered
// brush stroke (and sometimes a companion dot) with its own length, tilt and
// weight, each fading in and out on its own slow cycle — no visible repeat.
float glints(vec2 p, float density) {
    const vec2 G = vec2(86.0, 26.0);
    vec2 cell = floor(p / G);
    float g = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = cell + vec2(float(i), float(j));
            float h = hash2(c + 0.37);
            if (h < 1.0 - density) continue;
            float vis = smoothstep(-0.3, 0.4, sin(time * (0.12 + 0.2 * hash2(c + 5.1)) + h * 40.0));
            if (vis <= 0.0) continue;
            vec2 o = (c + vec2(hash2(c + 1.3), hash2(c + 2.9))) * G;
            float len = 3.0 + 34.0 * hash2(c + 4.4) * hash2(c + 8.8);
            float tilt = (hash2(c + 6.6) - 0.5) * 0.6;
            vec2 dir = vec2(cos(tilt), sin(tilt));
            float wgt = (0.6 + 1.2 * hash2(c + 7.7)) * vis;
            vec2 a = o - dir * len * 0.5, ba = dir * len;
            float t = clamp(dot(p - a, ba) / dot(ba, ba), 0.0, 1.0);
            float k = length(p - a - ba * t) - wgt * (1.0 - 0.75 * abs(2.0 * t - 1.0));
            if (hash2(c + 9.9) > 0.55)
                k = min(k, length(p - o - dir * (len * 0.5 + 4.0 + 4.0 * hash2(c + 3.3))) - wgt * 0.8);
            g = max(g, fill(k));
        }
    }
    return g;
}

vec3 softShade(vec2 p, float d, vec3 base) {
    vec2 g = vec2(mapScene(p + vec2(1.0, 0.0)).x - d, mapScene(p + vec2(0.0, 1.0)).x - d);
    float depth = clamp(-d / 10.0, 0.0, 1.0);
    float dome = sqrt(1.0 - (1.0 - depth) * (1.0 - depth));
    vec3 n = normalize(vec3(g * (1.0 - dome) * 1.6, dome + 0.08));

    vec3 L = normalize(vec3(-0.35, -0.6, 0.72));
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float diffuse = max(dot(n, L), 0.0);
    float spec = pow(max(dot(n, H), 0.0), 60.0);
    float sheen = pow(max(dot(n, H), 0.0), 8.0);
    float rim = 1.0 - dome;
    float underside = clamp(dot(n.xy, vec2(0.0, 1.0)), 0.0, 1.0) * rim;

    vec3 col = base * (0.45 + 0.65 * diffuse);
    col += base * 0.4 * rim;
    col = mix(col, base * 0.35, underside * 0.6);
    return col + vec3(1.0) * (0.9 * spec + 0.12 * sheen);
}

vec3 celShade(vec2 p, vec2 scene, vec3 base, bool screentone) {
    float d = scene.x;

    // Shadow shapes: the body offset away from the light. Where the offset
    // copy has left the shape, we are on the shadow side.
    float shadow1 = fill(-mapScene(p + AWAY * 15.0).x);
    float shadow2 = fill(-mapScene(p + AWAY * 6.0).x);
    float litEdge = fill(-mapScene(p - AWAY * 9.0).x);

    // Hue-shifted cel tones: shadows go cooler and more saturated.
    vec3 light = min(base * 1.25 + 0.1, vec3(1.0));
    vec3 mid = base * vec3(0.6, 0.64, 0.82);
    vec3 dark = base * vec3(0.32, 0.35, 0.58);
    vec3 ink = mix(base * 0.12, vec3(0.02, 0.02, 0.07), 0.6);

    vec3 col = mix(base, light, litEdge * 0.9);
    col = mix(col, mid, shadow1);
    col = mix(col, dark, shadow2);

    if (screentone) {
        // Screentone only where it earns its place: nothing in the light,
        // halftone dots across the shadow side, and cross-hatching in the core
        // shadow and along the rim for emphasis. Panel contents stay clean.
        float calm = labelZone(p);
        float inPanel = step(barHeight + 8.0, p.y) * step(panelRect.x, p.x) * step(p.x, panelRect.x + panelRect.z);
        calm = max(calm, inPanel * smoothstep(-12.0, -22.0, d));

        float tone = mix(0.0, 0.32, shadow1);
        tone = mix(tone, 0.4, shadow2);
        tone *= 1.0 - calm;
        vec2 q = mat2(0.7071, -0.7071, 0.7071, 0.7071) * p / 6.0;
        float dist = length(fract(q) - 0.5);
        float dots = clamp((tone - dist) * 7.0 + 0.5, 0.0, 1.0) * step(0.02, tone);
        col = mix(col, ink, dots * 0.8);

        // hatching: diagonal strokes in the deep shadow, crossed near the rim
        float rim = fill(-(d + 9.0)) * (1.0 - fill(-(d + 2.0)));   // band just inside the edge
        float u = dot(p, vec2(0.6, -0.8)) / 4.2;
        float v = dot(p, vec2(0.8, 0.6)) / 4.2;
        float lines1 = clamp((0.14 - abs(fract(u) - 0.5)) * 5.0 + 0.5, 0.0, 1.0);
        float lines2 = clamp((0.12 - abs(fract(v) - 0.5)) * 5.0 + 0.5, 0.0, 1.0);
        float hatch = lines1 * shadow2 + lines2 * shadow2 * rim;
        col = mix(col, ink, clamp(hatch, 0.0, 1.0) * 0.7 * (1.0 - calm));
    }

    // Reflected light: a thin bright sliver just inside the shadow-side rim.
    float reflectBand = fill(-(d + 6.0)) * (1.0 - fill(-(d + 3.4)));
    col = mix(col, light * 0.9, reflectBand * shadow2 * 0.85);

    // Wet highlights: hard white streaks inset along lit edges (broken up so
    // they read as glints), bulb sparkles, and a glint band across the bar.
    float streakBand = fill(-(d + 8.0)) * (1.0 - fill(-(d + 4.0)));
    float label = labelZone(p);
    float breakUp = step(0.52, vnoise(p / 15.0));
    float streak = streakBand * (1.0 - shadow1) * breakUp * litEdge;
    float barGlint = glints(p, 0.5) * step(d, -4.0) * (1.0 - shadow1) * (1.0 - label);

    float sparkle = fill(scene.y) * step(-16.0, d);  // hide bulbs buried in the panel
    float glow = exp(-max(scene.y, 0.0) * 0.35) * 0.35 * step(-16.0, d);
    col = mix(col, light, glow * (1.0 - sparkle));
    col = mix(col, vec3(1.0), clamp(max(max(streak, barGlint), sparkle), 0.0, 1.0));

    // Ink outline, heavier on the shadow side like a brush line.
    float lineW = mix(1.8, 3.4, shadow2);
    col = mix(col, ink, fill(-(d + lineW)));
    return col;
}


// ---- print style ---------------------------------------------------------

const vec2 MISREG = vec2(-1.6, 1.2);
const mat2 ROT45 = mat2(0.7071, -0.7071, 0.7071, 0.7071);

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// Shift a colour's hue toward `target` along the short way round, then
// scale its saturation and value — painters' shadows and lights.
vec3 toneShift(vec3 c, float target, float amt, float sat, float val) {
    vec3 h = rgb2hsv(c);
    float dh = target - h.x;
    dh -= floor(dh + 0.5);
    h.x = fract(h.x + dh * amt);
    h.y = clamp(h.y * sat, 0.0, 1.0);
    h.z = clamp(h.z * val, 0.0, 1.0);
    return hsv2rgb(h);
}

vec4 printShade(vec2 p, vec2 scene, vec3 base) {
    float d = scene.x;
    float dc = mapScene(p + MISREG).x;   // colour plate, printed slightly off the ink

    // Cut-paper shadow shapes: offset copies of the body with ragged edges.
    float jag = (fbm(p / 16.0) - 0.5) * 18.0 + (vnoise(p / 3.5) - 0.5) * 2.5;
    float s1 = mapScene(p + AWAY * 26.0).x + jag;
    float s2 = mapScene(p + AWAY * 11.0).x + jag * 0.6;
    float lt = mapScene(p - AWAY * 9.0).x + jag * 0.5;
    float label = labelZone(p);
    float shadow1 = fill(-s1), shadow2 = fill(-s2) * (1.0 - label), litEdge = fill(-lt);

    vec3 lightC = toneShift(base, 0.13, 0.12, 0.85, 1.25);   // warmer, paler
    vec3 mid = toneShift(base, 0.74, 0.2, 1.15, 0.68);       // toward violet
    vec3 dark = toneShift(base, 0.74, 0.35, 1.2, 0.4);
    vec3 ink = mix(vec3(0.05, 0.03, 0.09), dark, 0.18);
    vec3 paper = paperColor.rgb;

    vec3 col = mix(base, lightC, litEdge);
    col = mix(col, mid, shadow1);
    col = mix(col, dark, shadow2);

    // Halftone in the shadow transition only.
    float dist = length(fract(ROT45 * p / 6.0) - 0.5);
    float dotR = 0.14 + 0.24 * clamp(s1 / 14.0, 0.0, 1.0);
    float dots = clamp((dotR - dist) * 6.0 + 0.5, 0.0, 1.0) * shadow1 * (1.0 - shadow2) * (1.0 - label);
    col = mix(col, dark, dots * 0.85);

    // Hand-drawn hatching in the core shadow, heavier the deeper it goes.
    float u = dot(p, vec2(0.53, -0.85)) / 4.0 + (vnoise(p / 9.0) - 0.5) * 0.6;
    float w = 0.05 + 0.2 * clamp(s2 / 7.0, 0.0, 1.0);
    float hatch = clamp((w - abs(fract(u) - 0.5)) * 4.0 + 0.5, 0.0, 1.0) * shadow2;
    col = mix(col, ink, hatch * 0.85);

    // Ink line tracing the shadow terminator, like the murals.
    col = mix(col, ink, fill(abs(s1) - 0.6) * step(d, -2.0) * (1.0 - label));

    // Bubbles trapped in the ooze, drifting up; kept out of the panel text.
    float inPanel = step(barHeight + 8.0, p.y) * step(panelRect.x, p.x) * step(p.x, panelRect.x + panelRect.z);
    vec2 bp = p + vec2(0.0, time * 6.0);
    vec2 cell = floor(bp / 34.0);
    if (hash2(cell) > 0.55 && inPanel < 0.5 && label < 0.5) {
        vec2 c = (cell + 0.25 + 0.5 * vec2(hash2(cell + 3.1), hash2(cell + 7.7))) * 34.0;
        float r = 2.0 + 4.0 * hash2(cell + 1.7);
        float bd = length(bp - c) - r;
        float room = step(d, -(r + 5.0));
        col = mix(col, lightC, fill(bd) * 0.7 * room);
        col = mix(col, ink, fill(abs(bd) - 0.55) * room);
        col = mix(col, vec3(1.0), fill(length(bp - c + r * 0.4) - r * 0.28) * room);
    }

    // Wet glints in warm paper-white.
    vec3 glintC = mix(vec3(1.0), paper, 0.25);
    float streakBand = fill(-(d + 8.0)) * (1.0 - fill(-(d + 4.0)));
    float breakUp = step(0.52, vnoise(p / 15.0));
    float streak = streakBand * (1.0 - shadow1) * breakUp * litEdge;
    // Fewer glints behind the panel's text, none on widget labels.
    float content = inPanel * smoothstep(-12.0, -22.0, d);
    float g = glints(p, mix(0.5, 0.12, content)) * step(d, -4.0) * (1.0 - label);
    float sparkle = fill(scene.y) * step(-16.0, d);
    col = mix(col, lightC, g * shadow1 * (1.0 - shadow2));   // dimmer glints in shadow
    g *= 1.0 - shadow1;
    col = mix(col, glintC, clamp(max(max(streak, g), sparkle), 0.0, 1.0));

    // Paper grain: fine per-pixel tooth plus a coarser riso mottle.
    col *= 1.0 + (hash2(floor(p)) - 0.5) * 0.14 + (vnoise(p / 2.5) - 0.5) * 0.12;

    // Misregistration: paper shows where the colour plate missed the ink.
    col = mix(paper, col, fill(dc));

    // Brush outline with a little wobble in its weight.
    float lineW = mix(1.8, 3.6, shadow2) + (vnoise(p / 6.0) - 0.5) * 1.2;
    col = mix(col, ink, fill(-(d + lineW)) * fill(d));

    return vec4(col, max(fill(d), fill(dc)));
}

void main() {
    vec2 p = qt_TexCoord0 * resolution + origin;
    if (p.y < clipTop || (cullRect.w > 0.5 && (p.x < cullRect.x || p.x > cullRect.y || p.y > cullRect.z))) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 scene = mapScene(p);
    float d = scene.x;

    // Most of the window is empty air: bail out before any shading work.
    // (18px covers the drop shadow, outline wobble and misregistration.)
    if (d > 18.0) {
        fragColor = vec4(0.0);
        return;
    }
    float alpha = fill(d);

    // Two-colour theme gradient that drifts slowly along the bar and leans
    // toward the partner colour as the ooze hangs lower.
    float gt = 0.45 + 0.35 * sin(p.x * 0.0022 + time * 0.12) + (p.y - barHeight) / 220.0;
    vec3 base = mix(slimeColor.rgb, slimeColor2.rgb, smoothstep(0.0, 1.0, gt));
    vec3 col;
    if (shadingStyle > 2.5) {
        vec4 printed = printShade(p, scene, base);
        col = printed.rgb;
        alpha = printed.a;
    } else {
        col = shadingStyle < 0.5 ? softShade(p, d, base) : celShade(p, scene, base, shadingStyle > 1.5);
    }

    if (poolDepth > 0.0 && openProgress > 0.0) {
        float inBox = step(panelRect.x + 12.0, p.x) * step(p.x, panelRect.x + panelRect.z - 12.0)
                    * step(barHeight + 12.0, p.y);
        float deep = smoothstep(-10.0, -22.0, d) * inBox * poolDepth;
        vec3 pool = toneShift(base, 0.74, 0.3, 1.1, 0.22);
        pool *= 1.0 + (hash2(floor(p)) - 0.5) * 0.08 + (vnoise(p / 2.5) - 0.5) * 0.06;
        col = mix(col, pool, deep);
    }

    // Drop shadow so the ooze sits above whatever is underneath.
    float ds = mapScene(p - vec2(0.0, 4.0)).x;
    float shadow = (1.0 - smoothstep(-2.0, 12.0, ds)) * 0.35;

    vec4 slime = vec4(col * alpha, alpha);
    fragColor = (slime + vec4(0.0, 0.0, 0.0, shadow) * (1.0 - alpha)) * qt_Opacity;
}
