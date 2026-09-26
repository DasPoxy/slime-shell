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
    vec2 origin;      // this window's top-left on the screen
    float blobMode;   // 1 = no bar: just a free-standing blob in panelRect
    float barShape;   // 0 classic strip, 1 pills, 2 islands, 3 notch
    vec4 dripStyle;   // speed x, thickness x, frozen (1 = hang still), density x
    vec4 dripExtra;   // x: shape 0 drip / 1 stringy / 2 mitosis; y: variable amount 0/1;
                      // z: how far the window reaches from the bar (0 = no limit)
    vec4 eggDrip;     // easter egg: x along the bar, edge y, start time, active
    float material;   // 0 slime, 1 sinew, 2 bone, 3 plain
    float orient;     // which screen edge the bar is on: 0 top, 1 bottom, 2 left, 3 right
    vec2 screenSize;  // for bottom / right bars
    vec4 group0;      // left / centre / right section extents (x, y, w, h)
    vec4 group1;
    vec4 group2;
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
    vec4 bulb16;
    vec4 bulb17;
    vec4 bulb18;
    vec4 bulb19;
    vec4 bulb20;
    vec4 bulb21;
    vec4 bulb22;
    vec4 bulb23;
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

// A segment whose thickness runs from ra at a to rb at b.
float sdTaper(vec2 p, vec2 a, vec2 b, float ra, float rb) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
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
// Where drip `seed` hangs its tip right now (xy) and how much of it is still
// attached (z: 1 hanging, falling to 0 as it lets go). Mirrors drip()'s timing
// so the stringy style can web neighbouring drips together.
// 1 until y nears the far side of the window, then down to 0: falling goo
// shrinks away there instead of being sliced off by the window edge.
float fadeOut(float y) {
    return dripExtra.z > 0.0 ? 1.0 - smoothstep(dripExtra.z - 70.0, dripExtra.z - 6.0, y) : 1.0;
}

vec3 dripTip(float cx, float edgeY, float seed, float scale) {
    float speed = (0.06 + 0.09 * hash(seed + 1.0)) * dripStyle.x;
    float s = fract(time * speed + hash(seed + 2.0));
    if (dripStyle.z > 0.5) s = 0.35 + 0.42 * hash(seed + 2.0);
    float maxLen = scale * min(dripAmount, 2.1) * (12.0 + 48.0 * hash(seed + 3.0));
    if (dripExtra.y > 0.5) maxLen *= 0.15 + 1.7 * vnoise(vec2(seed * 3.1, time * 0.12));
    float grow = smoothstep(0.0, 0.8, s);
    float release = smoothstep(0.8, 1.0, s);
    return vec3(cx, edgeY + maxLen * grow * grow * (1.0 - release), 1.0 - release);
}

vec2 drip(vec2 p, float cx, float edgeY, float seed, float scale) {
    float speed = (0.06 + 0.09 * hash(seed + 1.0)) * dripStyle.x;
    float s = fract(time * speed + hash(seed + 2.0));
    // frozen: each drip hangs at its own length and never lets go
    if (dripStyle.z > 0.5) s = 0.35 + 0.42 * hash(seed + 2.0);
    float maxLen = scale * min(dripAmount, 2.1) * (12.0 + 48.0 * hash(seed + 3.0));
    // variable amount: each drip swells and dries up on its own slow cycle
    if (dripExtra.y > 0.5) maxLen *= 0.15 + 1.7 * vnoise(vec2(seed * 3.1, time * 0.12));
    float neck = (3.5 + 4.0 * hash(seed + 4.0)) * dripStyle.y;
    float hl = 1e5;

    // ---- mitosis / lava lamp: a blob buds off the edge, pinches its neck
    // shut, splits away and sinks slowly, wobbling, then dissolves
    if (dripExtra.x > 1.5) {
        float r = (6.0 + 11.0 * hash(seed + 5.0)) * dripStyle.y * (0.6 + 0.4 * scale) * clamp(dripAmount, 0.5, 1.6);
        float bud = smoothstep(0.0, 0.45, s);                     // swelling
        float pinch = smoothstep(0.35, 0.62, s);                  // neck closing
        float sink = max(0.0, s - 0.62) / 0.38;                   // after the split
        float wob = sin(time * 1.7 + seed * 5.0) * 3.0 * sink;
        vec2 c = vec2(cx + wob, edgeY + r * (0.2 + 1.3 * bud) + sink * sink * maxLen * 2.4);
        float br = r * (0.35 + 0.65 * bud) * (1.0 - 0.3 * sink);
        br *= fadeOut(c.y + br * 1.6);
        // stretched tall while it pinches, rounding off once it floats free
        float stretch = 1.0 + 0.35 * pinch * (1.0 - sink);
        // every glob its own shape: squat or tall, lumpy edges that roll
        // slowly, and sometimes a smaller lobe riding on its side
        float asp = 0.72 + 0.62 * hash(seed + 21.0);
        vec2 q = p - c;
        vec2 qs = vec2(q.x * stretch / asp, q.y * asp / stretch);
        float ang = atan(qs.y, qs.x);
        float lump = 1.0 + 0.16 * hash(seed + 22.0) * sin(2.0 * ang + seed * 3.0 + time * 0.6)
                         + 0.11 * hash(seed + 23.0) * sin(3.0 * ang + seed * 7.0 - time * 0.9)
                         + 0.06 * hash(seed + 24.0) * sin(5.0 * ang + time * 1.3);
        float d = (length(qs) - br * lump) / max(stretch / asp, asp / stretch);
        if (hash(seed + 25.0) < 0.55) {
            float la = seed * 2.4 + time * 0.35 * (hash(seed + 26.0) - 0.5);
            vec2 lc = c + vec2(cos(la), sin(la)) * br * (0.7 + 0.25 * hash(seed + 27.0));
            d = smin(d, length(p - lc) - br * (0.3 + 0.25 * hash(seed + 28.0)), br * 0.5);
        }
        // the neck: a waist that thins to nothing, pulling into two lobes
        if (pinch < 1.0) {
            float waist = mix(br * 0.9, 0.0, pinch);
            d = smin(d, sdSegment(p, vec2(cx, edgeY - 4.0), c, waist), 6.0 * (1.0 - pinch) + 0.5);
        }
        // a sister lobe left behind on the edge, drawn back in
        if (pinch > 0.0 && sink < 0.35) d = smin(d, length(p - vec2(cx, edgeY + 1.0)) - br * 0.5 * (1.0 - sink * 2.8), 4.0);
        if (br > 5.0) hl = sdEllipse(p, c + vec2(-0.38, -0.3) * br, vec2(0.16, 0.3) * br);
        return vec2(d, hl);
    }

    float grow = smoothstep(0.0, 0.8, s);
    float release = smoothstep(0.8, 1.0, s);
    float len = maxLen * grow * grow * (1.0 - release);
    float bulb = (neck + 3.0 + 6.0 * grow) * (1.0 - release);

    vec2 top = vec2(cx, edgeY - 6.0);
    vec2 tip = vec2(cx, edgeY + len);
    bool stringy = dripExtra.x > 0.5;
    // stringy goo necks down as it stretches
    float d = sdSegment(p, top, tip, neck * (1.0 - 0.6 * release) * (stringy ? 1.0 - 0.4 * grow : 1.0));
    d = smin(d, length(p - tip) - bulb, 8.0);

    // Anime wet-look sparkle: a tilted oval up-left on the bulb, a dot below.
    if (bulb > 5.0) {
        hl = sdEllipse(p, tip + vec2(-0.38, -0.3) * bulb, vec2(0.16, 0.3) * bulb);
        hl = min(hl, length(p - (tip + vec2(0.3, 0.42) * bulb)) - 0.1 * bulb);
    }

    float fall = release > 0.0 ? (s - 0.8) / 0.2 : 0.0;
    vec2 drop = vec2(cx, edgeY + maxLen + fall * fall * 240.0);
    if (release > 0.0) {
        float dr = (neck + 6.0) * (1.0 - 0.5 * fall);
        dr *= fadeOut(drop.y + dr);
        // stringy: once free of its strands the glob breaks up, droplets
        // drifting apart as they fall
        float split = stringy ? smoothstep(0.3, 0.75, fall) : 0.0;
        if (split > 0.0) {
            float dd = 1e5;
            for (int q = 0; q < 4; q++) {
                float fq = float(q);
                vec2 o = vec2((hash(seed + fq * 3.7) - 0.5) * 64.0, hash(seed + fq * 5.1) * 26.0 - 6.0) * split;
                float rq = dr * mix(0.8, 0.3 + 0.3 * hash(seed + fq * 1.9), split);
                dd = smin(dd, length(p - drop - o) - rq, 7.0 * (1.0 - split) + 0.1);
            }
            d = min(d, dd);
        } else {
            d = min(d, length(p - drop) - dr);
            hl = min(hl, sdEllipse(p, drop + vec2(-0.35, -0.3) * dr, vec2(0.18, 0.32) * dr));
        }
    }

    // ---- stringy: extra strands from the edge to the bulb, sagging a little.
    // They taper thinner in the middle as the glob stretches away, snap one by
    // one early in its fall, and the broken ends spring back up to the edge.
    if (stringy) {
        for (int j = 0; j < 4; j++) {
            float fj = float(j);
            if (hash(seed * 7.0 + fj) < 0.12) continue;
            float root0 = cx + (hash(seed * 3.0 + fj * 1.7) - 0.5) * (neck * 5.0 + 10.0);
            float snapAt = 0.08 + 0.3 * hash(seed + fj * 2.3);   // how far the drop falls before it snaps
            vec2 a0 = vec2(root0, edgeY - 2.0);
            float base = 1.8 + 1.4 * hash(seed + fj * 4.4);
            float sagY = 4.0 + 3.0 * hash(seed + fj * 9.1);
            if (release > 0.0 && fall > snapAt) {
                // recoil: what's left on the bar shortens and fattens back in
                float k = clamp((fall - snapAt) / 0.22, 0.0, 1.0);
                if (k >= 1.0) continue;
                vec2 dropS = vec2(cx, edgeY + maxLen + snapAt * snapAt * 240.0);
                vec2 midS = mix(a0, dropS, 0.5) + vec2(0.0, sagY);
                vec2 tail = mix(midS, a0, k * k * (3.0 - 2.0 * k));
                d = min(d, sdTaper(p, a0, tail, base * 0.8, max(0.5, base * 0.25 * (1.0 - k))));
                continue;
            }
            vec2 end = release > 0.0 ? drop : tip + vec2((hash(seed + fj) - 0.5) * bulb, -bulb * 0.4);
            vec2 mid = mix(a0, end, 0.5) + vec2(0.0, sagY);
            // snap before the drop shrinks away near the window's edge (a
            // hairline with nothing on the end still draws its outline)
            if (fadeOut(end.y + 40.0) < 0.6) continue;
            float st = clamp(0.65 * grow + 0.35 * (release > 0.0 ? fall / snapAt : 0.0), 0.0, 1.0);
            float wRoot = base * (1.0 - 0.3 * st);
            float wMid = max(0.5, base * (1.0 - 0.78 * st));
            d = min(d, min(sdTaper(p, a0, mid, wRoot, wMid), sdTaper(p, mid, end, wMid, wRoot * 0.75)));
        }
    }
    return vec2(d, hl);
}

// A widget bulb: the ooze sagging under a floating widget (b = the widget's
// rect), gently breathing, with a drip or two hanging from its belly.
const float BULB_HANG = 20.0;

// ---- bar shapes ----------------------------------------------------------
const float PAD = 7.0;        // goo around a widget or section

// A floating lozenge around rect b, breathing a little.
float sdPod(vec2 p, vec4 b, float seed) {
    if (b.z <= 0.0) return 1e5;
    float wob = 1.2 * sin(time * 0.9 + seed * 1.7);
    // pills sit inside their widget's slot (slots touch) so each stays apart
    float padX = barShape > 0.5 && barShape < 1.5 ? -2.5 : PAD;
    vec2 hs = b.zw * 0.5 + vec2(padX, PAD * 0.55 + wob * 0.3);
    return sdRoundBox(p, b.xy + b.zw * 0.5, hs, hs.y);
}

float podsAll(vec2 p) {
    float d = 1e5;
    d = min(d, sdPod(p, bulb0, 1.0));
    d = min(d, sdPod(p, bulb1, 2.0));
    d = min(d, sdPod(p, bulb2, 3.0));
    d = min(d, sdPod(p, bulb3, 4.0));
    d = min(d, sdPod(p, bulb4, 5.0));
    d = min(d, sdPod(p, bulb5, 6.0));
    d = min(d, sdPod(p, bulb6, 7.0));
    d = min(d, sdPod(p, bulb7, 8.0));
    d = min(d, sdPod(p, bulb8, 9.0));
    d = min(d, sdPod(p, bulb9, 10.0));
    d = min(d, sdPod(p, bulb10, 11.0));
    d = min(d, sdPod(p, bulb11, 12.0));
    d = min(d, sdPod(p, bulb12, 13.0));
    d = min(d, sdPod(p, bulb13, 14.0));
    d = min(d, sdPod(p, bulb14, 15.0));
    d = min(d, sdPod(p, bulb15, 16.0));
    d = min(d, sdPod(p, bulb16, 17.0));
    d = min(d, sdPod(p, bulb17, 18.0));
    d = min(d, sdPod(p, bulb18, 19.0));
    d = min(d, sdPod(p, bulb19, 20.0));
    d = min(d, sdPod(p, bulb20, 21.0));
    d = min(d, sdPod(p, bulb21, 22.0));
    d = min(d, sdPod(p, bulb22, 23.0));
    d = min(d, sdPod(p, bulb23, 24.0));
    return d;
}

float islands(vec2 p) {
    return min(min(sdPod(p, group0, 21.0), sdPod(p, group1, 22.0)), sdPod(p, group2, 23.0));
}

// A notch side piece: section g wrapped in goo that hugs the screen corner
// and runs a little way down the screen's side edge, filleted round the bend.
// `mirror` flips it for the far corner (barLen = the bar's length).
float cornerPiece(vec2 p, vec4 g, bool mirror, float barLen) {
    if (g.z <= 0.0) return 1e5;
    vec2 q = p;
    float x1 = g.x + g.z;
    if (mirror) { q.x = barLen - p.x; x1 = barLen - g.x; }
    float bottom = g.y + g.w + PAD * 0.55 + 2.0;
    float wob = 1.2 * sin(time * 0.8 + (mirror ? 2.0 : 0.0));
    float top = sdRoundBox(q, vec2((x1 + PAD * 1.6 - 30.0) * 0.5, (bottom - 30.0) * 0.5),
                           vec2((x1 + PAD * 1.6 + 30.0) * 0.5, (bottom + 30.0) * 0.5 + wob * 0.3), 16.0);
    // the run down the side edge, tapering off
    float drop = 46.0 + 10.0 * sin(time * 0.5 + (mirror ? 1.3 : 0.0));
    float taper = clamp((q.y - bottom) / drop, 0.0, 1.0);
    float side = sdRoundBox(q, vec2(0.0, bottom + drop * 0.5 - 8.0), vec2(9.0 - taper * 5.0, drop * 0.5 + 8.0), 7.0);
    return smin(top, side, 20.0);
}

// The notch: the centre section in a lump of goo hanging from the screen
// edge, flaring into the edge; the side sections sit in goo that wraps round
// the screen's corners.
float notch(vec2 p) {
    if (group1.z <= 0.0) return islands(p);
    vec2 c = group1.xy + group1.zw * 0.5;
    vec2 hs = vec2(group1.z * 0.5 + PAD * 2.0, (group1.y + group1.w + PAD + 12.0) * 0.5);
    float body = sdRoundBox(p, vec2(c.x, hs.y - 12.0), hs, 18.0);
    float lip = max(p.y - 4.0 - 1.5 * sin(p.x * 0.03 + time), abs(p.x - c.x) - hs.x - 36.0);   // thin edge strip
    float d = smin(body, lip, 16.0);
    float barLen = orient < 1.5 ? screenSize.x : screenSize.y;
    if (barLen <= 0.0) barLen = resolution.x;   // bar window on a top bar: its width
    return min(d, min(cornerPiece(p, group0, false, barLen), cornerPiece(p, group2, true, barLen)));
}

float baseShape(vec2 p) {
    if (barShape < 0.5) return p.y - barEdge(p.x);
    if (barShape < 1.5) return podsAll(p);
    if (barShape < 2.5) return islands(p);
    return notch(p);
}

// Bottom edge of the goo above x (for hanging drips), or -1 where there is
// none. Classic always has the strip; the others only under their shapes.
float podBottom(vec4 b, float x, float extra) {
    float padX = barShape > 0.5 && barShape < 1.5 ? -2.5 : PAD;
    if (b.z <= 0.0 || x < b.x - padX + 6.0 || x > b.x + b.z + padX - 6.0) return -1.0;
    return b.y + b.w + PAD * 0.55 + extra;
}
float dripEdge(float x) {
    if (barShape < 0.5) return barEdge(x);
    float e = -1.0;
    if (barShape < 1.5) {
        e = max(e, podBottom(bulb0, x, 0.0));
        e = max(e, podBottom(bulb1, x, 0.0));
        e = max(e, podBottom(bulb2, x, 0.0));
        e = max(e, podBottom(bulb3, x, 0.0));
        e = max(e, podBottom(bulb4, x, 0.0));
        e = max(e, podBottom(bulb5, x, 0.0));
        e = max(e, podBottom(bulb6, x, 0.0));
        e = max(e, podBottom(bulb7, x, 0.0));
        e = max(e, podBottom(bulb8, x, 0.0));
        e = max(e, podBottom(bulb9, x, 0.0));
        e = max(e, podBottom(bulb10, x, 0.0));
        e = max(e, podBottom(bulb11, x, 0.0));
        e = max(e, podBottom(bulb12, x, 0.0));
        e = max(e, podBottom(bulb13, x, 0.0));
        e = max(e, podBottom(bulb14, x, 0.0));
        e = max(e, podBottom(bulb15, x, 0.0));
        e = max(e, podBottom(bulb16, x, 0.0));
        e = max(e, podBottom(bulb17, x, 0.0));
        e = max(e, podBottom(bulb18, x, 0.0));
        e = max(e, podBottom(bulb19, x, 0.0));
        e = max(e, podBottom(bulb20, x, 0.0));
        e = max(e, podBottom(bulb21, x, 0.0));
        e = max(e, podBottom(bulb22, x, 0.0));
        e = max(e, podBottom(bulb23, x, 0.0));
        return e;
    }
    e = max(podBottom(group0, x, 0.0), podBottom(group2, x, 0.0));
    if (barShape < 2.5) return max(e, podBottom(group1, x, 0.0));
    // notch: the corner pieces reach the screen's ends, so they drip all along
    float len = orient < 1.5 ? screenSize.x : screenSize.y;
    if (len <= 0.0) len = resolution.x;
    if (group0.z > 0.0 && x > 12.0 && x < group0.x + group0.z + PAD) e = max(e, group0.y + group0.w + PAD * 0.55 + 2.0);
    if (group2.z > 0.0 && x < len - 12.0 && x > group2.x - PAD) e = max(e, group2.y + group2.w + PAD * 0.55 + 2.0);
    vec4 n = group1;   // notch: deeper, and wider by its flare
    if (n.z > 0.0 && abs(x - (n.x + n.z * 0.5)) < n.z * 0.5 + PAD * 2.0 - 8.0) e = max(e, n.y + n.w + PAD);
    return e;
}

// Sinew: a row of teeth hanging off the goo's lower edge (distance only).
float teethRow(vec2 p) {
    // uneven spacing, sizes and tilts: a jittered row where some teeth are
    // missing, some are stubs, some are long fangs leaning either way
    const float STEP = 12.0;
    float i = floor(p.x / STEP);
    float d = 1e5;
    for (int k = -2; k <= 2; k++) {
        float j = i + float(k);
        if (hash(j * 2.3 + 5.0) < 0.3) continue;                       // gaps
        float cx = (j + 0.5 + (hash(j * 4.1 + 1.0) - 0.5) * 0.7) * STEP;
        float edge = dripEdge(cx);
        if (edge < 0.0) continue;
        float big = hash(j * 7.1);
        float len = big > 0.85 ? 13.0 + 7.0 * hash(j * 3.3)            // fang
                  : 4.0 + 7.0 * big;                                   // tooth or stub
        float wid = (big > 0.85 ? 3.2 : 2.4 + 2.2 * hash(j * 9.7));
        float tilt = (hash(j * 5.9) - 0.5) * (big > 0.85 ? 0.7 : 0.9);  // radians
        // rotate around the root so each leans its own way
        vec2 q = p - vec2(cx, edge - 2.0 + hash(j * 6.2) * 2.0);
        float cs = cos(tilt), sn = sin(tilt);
        q = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
        // a slightly curved point: narrows faster near the tip
        float f = clamp(q.y / len, 0.0, 1.0);
        float w = wid * (1.0 - f * f * 0.35 - f * 0.65);
        float t = max(abs(q.x + f * f * tilt * 3.0) - w, max(-q.y, q.y - len));
        d = min(d, t);
    }
    return d;
}

// Bone: rounded knuckle knobs along the lower edge, like a spine.
float boneKnobs(vec2 p) {
    const float STEP = 46.0;
    float i = floor(p.x / STEP);
    float d = 1e5;
    for (int k = -1; k <= 1; k++) {
        float cx = (i + float(k) + 0.5) * STEP;
        float edge = dripEdge(cx);
        if (edge < 0.0) continue;
        d = min(d, length(p - vec2(cx - 7.0, edge + 1.0)) - 6.5);
        d = min(d, length(p - vec2(cx + 7.0, edge + 1.0)) - 6.5);
    }
    return d;
}

// Is there a bar-edge drip in cell i? (the same test mapScene's drip loop uses)
bool edgeDripIn(float i) {
    return hash(i * 3.7 + 11.0) >= 1.0 - 0.7 * dripStyle.w * max(1.0, dripAmount * 0.55);
}

// One sagging web strand from a to b, slack by `sag`, `w` thick.
float webStrand(vec2 p, vec2 a, vec2 b, float sag, float w) {
    vec2 mid = mix(a, b, 0.5) + vec2(0.0, sag);
    return min(sdSegment(p, a, mid, w), sdSegment(p, mid, b, w));
}

// A web strung between two hanging drips (each given as its top and tip):
// usually a lattice of 2-4 sagging rungs at staggered heights crossed by
// diagonals, sometimes just a lone strand. `live` thins it as a drip lets go.
float webLattice(vec2 p, vec2 aTop, vec2 aTip, vec2 bTop, vec2 bTip, float seed, float live) {
    float x0 = min(aTop.x, bTop.x), x1 = max(aTop.x, bTop.x);
    if (p.x < x0 - 4.0 || p.x > x1 + 4.0) return 1e5;
    float d = 1e5;
    bool lattice = hash(seed + 31.0) < 0.8;
    int levels = lattice ? 2 + int(hash(seed + 32.0) > 0.35) + int(hash(seed + 33.0) > 0.7) : 1;
    vec2 A[4], B[4];
    for (int j = 0; j < 4; j++) {
        if (j >= levels) break;
        float fj = float(j);
        float t = lattice ? (fj + 0.55) / float(levels) * 0.9 : 0.45;
        A[j] = mix(aTop, aTip, clamp(t + (hash(seed + fj * 3.1) - 0.5) * 0.18, 0.1, 0.95));
        B[j] = mix(bTop, bTip, clamp(t + (hash(seed + fj * 5.7) - 0.5) * 0.18, 0.1, 0.95));
        float w = (lattice ? 0.9 + 0.5 * hash(seed + fj * 4.2) : 1.3 + 0.6 * hash(seed + fj)) * live;
        d = min(d, webStrand(p, A[j], B[j], (5.0 + 8.0 * hash(seed + fj * 2.2)) * live, w));
        if (j > 0) {
            float wd = (0.8 + 0.4 * hash(seed + fj * 6.6)) * live;
            if (hash(seed + fj * 7.7) < 0.8) d = min(d, webStrand(p, A[j - 1], B[j], 3.0 * live, wd));
            if (hash(seed + fj * 8.8) < 0.8) d = min(d, webStrand(p, A[j], B[j - 1], 3.0 * live, wd));
        }
    }
    return d;
}

vec2 bulb(vec2 p, vec4 b, float seed) {
    bool stringy = dripExtra.x > 0.5 && dripExtra.x < 1.5;
    // stringy webs reach out to the neighbouring bar drips, so look further
    if (b.z <= 0.0 || abs(p.x - (b.x + b.z * 0.5)) > b.z * 0.5 + (stringy ? 2.6 * CELL : 70.0)) return vec2(1e5);
    float sag = 1.5 * sin(time * 0.8 + seed * 2.3);
    vec2 hs = vec2(b.z * 0.5, (b.w + BULB_HANG + sag) * 0.5);
    vec2 c = vec2(b.x + hs.x, b.y + hs.y);
    float d = sdRoundBox(p, c, hs, hs.y);
    // heavier belly: the goo pools toward the bottom middle
    d = smin(d, sdEllipse(p, vec2(c.x, c.y + hs.y * 0.45), vec2(hs.x * 0.75, hs.y * 0.8)), 6.0);

    float hl = 1e5;
    float bottom = c.y + hs.y - 3.0;
    float span = max(hs.x - hs.y * 0.6, 4.0);
    vec3 tips[2];
    int n = 0;
    for (int k = 0; k < 2; k++) {
        float sk = seed * 17.0 + float(k) * 5.0 + 200.0;
        if (k == 1 && hash(sk + 0.5) < (dripExtra.x > 0.5 && dripExtra.x < 1.5 ? 0.15 : 0.5)) break;
        float x = c.x + (hash(sk) * 2.0 - 1.0) * span;
        vec2 dr = drip(p, x, bottom, sk, 0.75);
        d = smin(d, dr.x, 7.0);
        hl = min(hl, dr.y);
        tips[k] = dripTip(x, bottom, sk, 0.75);
        n++;
    }
    // stringy: a sagging web between the belly's two drips
    if (n == 2 && dripExtra.x > 0.5 && dripExtra.x < 1.5 && abs(tips[0].x - tips[1].x) > 8.0) {
        float live = min(tips[0].z, tips[1].z) * smoothstep(2.0, 10.0, max(tips[0].y, tips[1].y) - bottom);
        if (live > 0.25) {
            d = smin(d, webLattice(p, vec2(tips[0].x, bottom), tips[0].xy, vec2(tips[1].x, bottom), tips[1].xy, seed + 8.0, live), 2.5);
        }
    }
    // stringy: web the belly's drips out to the nearest bar-edge drip on
    // their side, within a couple of cells of the widget
    if (stringy) {
        for (int k = 0; k < 2; k++) {
            if (k >= n) break;
            float sk = seed * 17.0 + float(k) * 5.0 + 200.0;
            if (hash(sk + 6.1) < 0.2) continue;
            vec3 t = tips[k];
            float side = n == 2 ? (t.x < tips[1 - k].x ? -1.0 : 1.0) : (hash(sk + 7.3) < 0.5 ? -1.0 : 1.0);
            float ci = floor((c.x + side * (hs.x + 6.0)) / CELL);
            for (int m = 0; m < 3; m++) {
                float i = ci + side * float(m);
                if (!edgeDripIn(i)) continue;
                float ex = (i + 0.5 + (hash(i) - 0.5) * 0.6) * CELL;
                if (abs(ex - c.x) < hs.x + 4.0) continue;        // tucked under the widget
                float ee = dripEdge(ex);
                if (ee < 0.0) break;
                vec3 et = dripTip(ex, ee, i, 1.0);
                float live = min(t.z, et.z) * smoothstep(2.0, 10.0, max(t.y - bottom, et.y - ee));
                if (live > 0.25) {
                    d = smin(d, webLattice(p, vec2(t.x, bottom), t.xy, vec2(ex, ee), et.xy, sk + 2.2, live), 2.5);
                }
                break;
            }
        }
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

// The easter-egg drip: one fat drip (the bar draws a creature inside its bulb)
// that swells for 6 s, hangs, snaps at 10 s and falls. Shares its timing with
// eggTip() in Bar.qml.
const float EGG_R = 15.5;
float eggLen(float t) { return 44.0 * smoothstep(0.0, 6.0, t); }
float eggShape(vec2 p) {
    float t = time - eggDrip.z;
    if (eggDrip.w < 0.5 || t < 0.0 || t > 14.0) return 1e5;
    float x = eggDrip.x, edge = eggDrip.y;
    float release = smoothstep(10.0, 10.6, t);
    float len = eggLen(t);
    vec2 tip = vec2(x, edge + len);
    float d = sdSegment(p, vec2(x, edge - 6.0), tip, 5.5 * (1.0 - release));
    if (release < 1.0) d = smin(d, length(p - tip) - EGG_R, 8.0);
    if (release > 0.0) {
        float f = max(0.0, t - 10.6) / 3.0;
        vec2 drop = vec2(x, edge + len + 300.0 * f * f);
        d = min(d, length(p - drop) - EGG_R);
    }
    return d;
}

// The command centre / panel blob: a fat drip that falls, then spreads.
float openPanel(vec2 p, float ci, inout float hl) {
    // Opens like a fat drip: a narrow bead falls first, then spreads
    // sideways into the panel body.
    float o = openProgress;
    float h = max(panelRect.w * smoothstep(0.0, 0.75, o), 2.0);
    float w = mix(40.0, panelRect.z, smoothstep(0.35, 1.0, o));
    float cx = panelRect.x + panelRect.z * 0.5;
    float r = min(min(w, h) * 0.5, 22.0);
    float pd = sdRoundBox(p, vec2(cx, barHeight + h * 0.5), vec2(w * 0.5, h * 0.5), r);
    float d = pd;

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
    return d;
}

vec2 mapScene(vec2 p) {
    if (blobMode > 0.5) return mapBlob(p);
    float d = baseShape(p);
    float hl = 1e5;
    float ci = floor(p.x / CELL);

    for (int k = -1; k <= 1; k++) {
        float i = ci + float(k);
        // torrent (amount > 1.8) packs more drips in as well as lengthening them
        if (hash(i * 3.7 + 11.0) < 1.0 - 0.7 * dripStyle.w * max(1.0, dripAmount * 0.55)) continue;
        float cx = (i + 0.5 + (hash(i) - 0.5) * 0.6) * CELL;
        float edge = dripEdge(cx);
        if (edge < 0.0) continue;
        vec2 dr = drip(p, cx, edge, i, 1.0);
        d = smin(d, dr.x, 12.0);
        hl = min(hl, dr.y);
    }

    // stringy: sagging webs strung between neighbouring drips, hanging from
    // partway down each one and thinning away as either drip lets go
    if (dripExtra.x > 0.5 && dripExtra.x < 1.5) {
        float dens = 1.0 - 0.7 * dripStyle.w * max(1.0, dripAmount * 0.55);
        // each drip webs to the next drip along, across at most one empty cell
        for (int k = -2; k <= 0; k++) {
            float i = ci + float(k);
            if (hash(i * 3.7 + 11.0) < dens) continue;
            float n = i + 1.0;
            if (hash(n * 3.7 + 11.0) < dens) n += 1.0;
            if (hash(n * 3.7 + 11.0) < dens) continue;
            if (hash(i * 5.3 + 2.0) > 0.85) continue;
            float xa = (i + 0.5 + (hash(i) - 0.5) * 0.6) * CELL;
            float xb = (n + 0.5 + (hash(n) - 0.5) * 0.6) * CELL;
            float ea = dripEdge(xa), eb = dripEdge(xb);
            if (ea < 0.0 || eb < 0.0) continue;
            vec3 ta = dripTip(xa, ea, i, 1.0), tb = dripTip(xb, eb, n, 1.0);
            float live = min(ta.z, tb.z) * smoothstep(2.0, 12.0, max(ta.y - ea, tb.y - eb));
            if (live < 0.25) continue;
            d = smin(d, webLattice(p, vec2(xa, ea), ta.xy, vec2(xb, eb), tb.xy, i * 9.1 + 4.0, live), 2.5);
        }
    }

    d = smin(d, eggShape(p), 8.0);

    // pills are their own lumps; every other shape sags a bulb under widgets
    if (barShape > 0.5 && barShape < 1.5) {
        if (openProgress > 0.001) d = smin(d, openPanel(p, ci, hl), 26.0);
        if (material > 0.5 && material < 1.5) d = min(d, teethRow(p));
        if (material > 1.5 && material < 2.5) d = smin(d, boneKnobs(p), 5.0);
        return vec2(d, hl);
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
    bs = bulb(p, bulb16, 17.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb17, 18.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb18, 19.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb19, 20.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb20, 21.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb21, 22.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb22, 23.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, bulb23, 24.0); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);

    if (openProgress > 0.001) d = smin(d, openPanel(p, ci, hl), 26.0);
    if (material > 0.5 && material < 1.5) d = min(d, teethRow(p));
    if (material > 1.5 && material < 2.5) d = smin(d, boneKnobs(p), 5.0);
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
    l = max(l, labelOf(p, bulb16));
    l = max(l, labelOf(p, bulb17));
    l = max(l, labelOf(p, bulb18));
    l = max(l, labelOf(p, bulb19));
    l = max(l, labelOf(p, bulb20));
    l = max(l, labelOf(p, bulb21));
    l = max(l, labelOf(p, bulb22));
    l = max(l, labelOf(p, bulb23));
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
    col += vec3(1.0) * (0.9 * spec + 0.12 * sheen);
    // a slight film grain, stronger in the shadows like real grain
    float grain = (hash2(floor(p)) - 0.5) * 0.07 + (vnoise(p / 1.7) - 0.5) * 0.05;
    return col * (1.0 + grain * (1.3 - diffuse * 0.6));
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
        // Screentone weighted toward the shadows: fine pinpricks across the lit
        // body, growing dots down the shadow side, hatching through the shadow
        // and crossed in the core and along the rim. Panel contents stay clean.
        float calm = labelZone(p);
        float inPanel = step(barHeight + 8.0, p.y) * step(panelRect.x, p.x) * step(p.x, panelRect.x + panelRect.z);
        calm = max(calm, inPanel * smoothstep(-12.0, -22.0, d));

        float tone = mix(0.13, 0.3, shadow1);
        tone = mix(tone, 0.42, shadow2);
        tone *= mix(1.0, 0.55, litEdge * (1.0 - shadow1));   // thinner still on the lit rim
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
        float hatch = lines1 * mix(shadow1 * 0.45, 1.0, shadow2) + lines2 * shadow2 * max(rim, 0.5);
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

// Texture laid over the shaded surface for the non-slime materials. Label
// zones (behind widget text) and panel interiors are kept calm.
vec3 materialSurface(vec2 p, float d, vec3 col, vec3 base) {
    if (material < 0.5) return col;
    vec3 ink = mix(base * 0.12, vec3(0.03, 0.02, 0.06), 0.7);
    float calm = labelZone(p);
    float inPanel = step(barHeight + 8.0, p.y) * step(panelRect.x, p.x) * step(p.x, panelRect.x + panelRect.z);
    calm = max(calm, inPanel * smoothstep(-12.0, -22.0, d) * 0.7);
    float rim = fill(d + 2.2);                              // 1 inside, 0 on the outline band

    if (material > 2.5) {
        // plain: flat theme colour and a clean ink edge
        return mix(ink, base, rim);
    }

    if (material < 1.5) {
        // ---- sinew ----
        // stretched muscle fibres running along the bar
        float warp = fbm(vec2(p.x / 70.0, p.y / 9.0)) * 6.0;
        float fib = sin(p.y * 1.15 + warp + sin(p.x * 0.02) * 1.5);
        vec3 c = col;
        c = mix(c, c * 0.72, smoothstep(0.55, 0.95, fib) * 0.55 * (1.0 - calm));
        c = mix(c, min(c * 1.25 + 0.05, vec3(1.0)), smoothstep(-0.95, -0.7, -fib) * 0.25 * (1.0 - calm));
        // veins: thin dark branching ridges, throbbing faintly
        float vn = abs(fbm(p / 26.0 + vec2(time * 0.02, 0.0)) - 0.5);
        float vein = smoothstep(0.035, 0.012, vn) * (0.75 + 0.25 * sin(time * 2.2));
        c = mix(c, toneShift(base, 0.8, 0.5, 1.1, 0.35), vein * 0.8 * (1.0 - calm));
        // teeth: ivory with a dark gumline
        c = mix(c, mix(paperColor.rgb, vec3(1.0, 0.96, 0.85), 0.4), step(teethRow(p), -0.8));
        return c;
    }

    // ---- bone ----
    vec3 c = col;
    // vertebra segments: faint grooves across the bar with a shadowed seam
    float seg = abs(fract(p.x / 46.0) - 0.5) * 46.0;
    c = mix(c, c * 0.8, smoothstep(2.5, 0.6, seg) * step(-d, 40.0) * (1.0 - calm) * 0.8);
    // cracks: thin dark ridges of noise
    float cn = abs(fbm(p / 18.0 + 3.1) - 0.5);
    c = mix(c, ink, smoothstep(0.011, 0.004, cn) * 0.6 * (1.0 - calm));
    // pores: speckled pits
    float pore = step(0.93, hash2(floor(p / 3.0))) * (0.5 + 0.5 * hash2(floor(p / 3.0) + 7.0));
    c = mix(c, c * 0.62, pore * 0.5 * (1.0 - calm));
    // aged staining toward the edges
    c = mix(c, c * vec3(0.86, 0.8, 0.66), smoothstep(-2.0, -14.0, d) < 1.0 ? (1.0 - smoothstep(-2.0, -14.0, d)) * 0.6 : 0.0);
    return c;
}

// Screen point -> "bar at the top" coordinates: x runs along the bar, y is the
// distance from the bar's screen edge. Everything else is drawn in that frame.
vec2 toBarSpace(vec2 g) {
    if (orient < 0.5) return g;
    if (orient < 1.5) return vec2(g.x, screenSize.y - g.y);
    if (orient < 2.5) return vec2(g.y, g.x);
    return vec2(g.y, screenSize.x - g.x);
}

void main() {
    vec2 p = toBarSpace(qt_TexCoord0 * resolution + origin);
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
    // materials start from the theme colour and push it toward their stuff
    if (material > 0.5 && material < 1.5) base = toneShift(base, 0.985, 0.75, 1.05, 0.95);          // flesh
    else if (material > 1.5 && material < 2.5) base = mix(paperColor.rgb, base, 0.14);               // ivory
    vec3 col;
    if (shadingStyle > 2.5) {
        vec4 printed = printShade(p, scene, base);
        col = printed.rgb;
        alpha = printed.a;
    } else {
        col = shadingStyle < 0.5 ? softShade(p, d, base) : celShade(p, scene, base, shadingStyle > 1.5);
    }

    col = materialSurface(p, d, col, base);

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
