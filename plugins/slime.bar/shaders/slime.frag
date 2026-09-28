#version 440

// Slime skin: the bar, its drips and the control-centre panel are one signed
// distance field, blended with smooth-min so everything reads as a single
// body of ooze. Coordinates are window pixels, y pointing down.
//
// shadingStyle: 4 = cel (clean three-tone cel shading, crisp outline),
// 5 = sketch (coloured pencil: hatching, wobbly overshooting outlines);
// 0 = soft (smooth lighting), 1 = anime (cel bands, ink line,
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
    float barShape;   // 0 classic strip, 1 pills, 2 islands, 3 notch, 4 corners, 5 dock
    vec4 dripStyle;   // speed x, thickness x, frozen (1 = hang still), density x
    vec4 dripExtra;   // x: shape 0 drip / 1 stringy / 2 mitosis; y: variable amount 0/1;
                      // z: how far falling goo may reach from the bar (0 = no limit)
                      // w: past this depth only the command centre's column is drawn
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
    vec4 cava0;       // cava drip style: 16 audio bands, 0..1 (left to right along the bar)
    vec4 cava1;
    vec4 cava2;
    vec4 cava3;
    vec4 cavaOpts;    // cava: x bars across the bar, y mirrored, z reach, w thickness (0s: defaults)
    vec4 dropShape;   // a lyric drip instead of the panel: x on, y how far it has sunk (px),
                      // z falling / bursting 0..1, w the bead's height (its width is panelRect.z)
    vec4 dockBracket; // the dock melting into the bar: no bar drips within x of its start / y of its end;
                      // on the dock itself, z shifts its gradient to match the bar's
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

// cava: the space between bars (the bar count spread along the whole bar)
float cavaStep() {
    float len = orient < 1.5 ? screenSize.x : screenSize.y;
    if (len <= 0.0) len = resolution.x;
    return len / max(4.0, cavaOpts.x > 0.0 ? cavaOpts.x : len / (CELL * 0.5));
}
// cava: the audio level under x (bands blended into a smooth wave)
float cavaBand(float i) {
    // floats only: some GL drivers balk at the int maths once translated
    i = clamp(i, 0.0, 15.0);
    vec4 v = i < 3.5 ? cava0 : i < 7.5 ? cava1 : i < 11.5 ? cava2 : cava3;
    float j = i - floor(i / 4.0) * 4.0;
    return j < 0.5 ? v.x : j < 1.5 ? v.y : j < 2.5 ? v.z : v.w;
}
float cavaLevel(float x) {
    float len = orient < 1.5 ? screenSize.x : screenSize.y;
    if (len <= 0.0) len = resolution.x;
    float u = clamp(x / len, 0.0, 1.0);
    // mirrored: bass in the middle, treble out to both ends
    if (cavaOpts.y > 0.5) u = abs(u * 2.0 - 1.0);
    float f = u * 15.0;
    float i = floor(f);
    float t = f - i;
    return mix(cavaBand(i), cavaBand(i + 1.0), t * t * (3.0 - 2.0 * t));
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

    // ---- cava: every drip is a bar of the audio visualizer — it hangs as far
    // as the music under it reaches, a round bead of goo swelling at its tip
    if (dripExtra.x > 3.5) {
        float lv = cavaLevel(cx);
        float reach = cavaOpts.z > 0.0 ? cavaOpts.z : 1.0;
        float len = scale * (5.0 + lv * 118.0 * reach * clamp(dripAmount, 0.5, 1.8));
        float w = (4.2 + 1.2 * hash(seed + 4.0)) * dripStyle.y * (cavaOpts.w > 0.0 ? cavaOpts.w : 1.0);
        w = min(w, cavaStep() * 0.36);          // never so fat they run together
        vec2 tip = vec2(cx, edgeY + len);
        float r = w * (1.15 + 0.35 * lv);
        float d = min(sdSegment(p, vec2(cx, edgeY - 4.0), tip, w * (0.8 + 0.2 * lv)), length(p - tip) - r);
        hl = length(p - (tip + vec2(-0.35, -0.4) * r)) - 0.28 * r;
        return vec2(d, hl);
    }

    // ---- gelatinous: the bar holds on to its goo; now and then a small bead
    // gathers on the underside, quivers, and is shaken loose to fall like a
    // raindrop. Most cells shed nothing in a given cycle.
    if (dripExtra.x > 2.5) {
        float cyc = floor(time * speed + hash(seed + 2.0));
        if (hash(seed * 1.3 + cyc * 7.1) > 0.4) return vec2(1e5, 1e5);
        float r = (2.4 + 2.2 * hash(seed + cyc * 1.7)) * clamp(dripAmount, 0.6, 1.6);
        float bx = cx + (hash(seed + cyc * 3.3) - 0.5) * 34.0;
        float form = smoothstep(0.0, 0.5, s);            // gathering
        float fall = max(0.0, s - 0.72) / 0.28;          // shaken loose
        float shake = sin(time * 23.0 + seed * 4.0) * 1.6 * form * (1.0 - step(0.001, fall));
        vec2 c = vec2(bx + shake, edgeY + r * 0.7 * form + fall * fall * (maxLen * 1.5 + 190.0));
        float rr = r * (0.3 + 0.7 * form) * (1.0 - 0.2 * fall);
        rr *= fadeOut(c.y + rr);
        vec2 q = p - c;
        q.y *= 1.0 - 0.3 * fall;                          // stretched as it falls
        float d = length(q) - rr;
        if (fall <= 0.0) d = smin(d, sdSegment(p, vec2(bx, edgeY - 3.0), c, rr * 0.5), 4.0);
        if (rr > 2.5) hl = length(p - (c + vec2(-0.35, -0.4) * rr)) - 0.28 * rr;
        return vec2(d, hl);
    }

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
    bool stringy = dripExtra.x > 0.5 && dripExtra.x < 1.5;
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

// Corner patches (4): a lumpy blob of goo centred on each end of the edge —
// i.e. nested right into the screen's corners.
const float CORNER_R = 66.0;
float cornerLen() { float l = orient < 1.5 ? screenSize.x : screenSize.y; return l > 0.0 ? l : resolution.x; }
float cornerBlob(vec2 p, vec2 c, float seed) {
    vec2 q = p - c;
    float a = atan(q.y, q.x);
    float r = CORNER_R * (1.0 + 0.07 * sin(a * 3.0 + time * 0.7 + seed) + 0.04 * sin(a * 7.0 - time * 1.1 + seed * 2.0));
    return length(q) - r;
}
float corners(vec2 p) {
    return min(cornerBlob(p, vec2(0.0), 0.0), cornerBlob(p, vec2(cornerLen(), 0.0), 3.0));
}
// the blobs' underside above x (for hanging drips), or -1
float cornerEdge(float x) {
    float dx = min(x, cornerLen() - x);
    float r = CORNER_R * 0.92;
    return dx < r - 8.0 ? sqrt(r * r - dx * dx) - 3.0 : -1.0;
}

// The dock (5): a lump of goo hanging off its screen edge holding the icons
// (group1), flaring into the edge like the notch; group0 / group2 (any
// width) also melt a corner blob into its start / end, where it meets the
// corner slimes.
float dockShape(vec2 p) {
    float d = 1e5;
    if (group1.z > 0.0) {
        vec2 c = group1.xy + group1.zw * 0.5;
        vec2 hs = vec2(group1.z * 0.5 + PAD * 2.0, (group1.y + group1.w + PAD + 12.0) * 0.5);
        float wob = 1.2 * sin(time * 0.9 + 2.0);
        float body = sdRoundBox(p, vec2(c.x, hs.y - 12.0), hs + vec2(0.0, wob * 0.3), 18.0);
        float lip = max(p.y - 4.0 - 1.5 * sin(p.x * 0.03 + time), abs(p.x - c.x) - hs.x - 36.0);
        d = smin(body, lip, 16.0);
    }
    // x 1: the bar runs across this end (y = its thickness): melt into its
    // underside with a fat fillet, one slime bracketing the corner
    float reach = group1.y + group1.w + PAD + 40.0;
    if (group0.z > 0.0) d = group0.x > 0.5 ? smin(d, max(p.x - group0.y, p.y - reach), 30.0)
                                           : smin(d, cornerBlob(p, vec2(0.0), 0.0), 26.0);
    if (group2.z > 0.0) d = group2.x > 0.5 ? smin(d, max(cornerLen() - group2.y - p.x, p.y - reach), 30.0)
                                           : smin(d, cornerBlob(p, vec2(cornerLen(), 0.0), 3.0), 26.0);
    return d;
}
float dockEdge(float x) {
    float e = -1.0;
    if (group1.z > 0.0 && x > group1.x - PAD && x < group1.x + group1.z + PAD) e = group1.y + group1.w + PAD;
    float r = CORNER_R * 0.92;
    if (group0.z > 0.0 && group0.x < 0.5 && x < r - 8.0) e = max(e, sqrt(r * r - x * x) - 3.0);
    float dx = cornerLen() - x;
    if (group2.z > 0.0 && group2.x < 0.5 && dx < r - 8.0) e = max(e, sqrt(r * r - dx * dx) - 3.0);
    return e;
}

float baseShape(vec2 p) {
    if (barShape > 4.5) return dockShape(p);
    if (barShape > 3.5) return corners(p);
    if (barShape < 0.5) return p.y - barEdge(p.x);
    if (barShape < 1.5) return podsAll(p);
    if (barShape < 2.5) return islands(p);
    return notch(p);
}

// Bottom edge of the goo above x (for hanging drips), or -1 where there is
// none. Classic always has the strip; the others only under their shapes.
float podBottom(vec4 b, float x, float extra) {
    bool pill = barShape > 0.5 && barShape < 1.5;
    float padX = pill ? -2.5 : PAD;
    // pills sit 5px apart: keep drips well in from the ends (narrow pills
    // still get one in the middle) so a drip's blend never bridges two pills
    float inset = pill ? min(18.0, b.z * 0.5 - 2.0) : 6.0 - padX;
    if (b.z <= 0.0 || x < b.x + inset || x > b.x + b.z - inset) return -1.0;
    return b.y + b.w + PAD * 0.55 + extra;
}
float dripEdge(float x) {
    if (barShape > 4.5) return dockEdge(x);
    if (barShape > 3.5) return cornerEdge(x);
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

// Keep the two bulbs horizontally nearest px (distance past their ends).
void pickBulb(vec4 b, float seed, float px, inout vec4 b1, inout float s1, inout float e1,
              inout vec4 b2, inout float s2, inout float e2) {
    if (b.z <= 0.0) return;
    float e = abs(px - (b.x + b.z * 0.5)) - b.z * 0.5;
    if (e < e1) { b2 = b1; s2 = s1; e2 = e1; b1 = b; s1 = seed; e1 = e; }
    else if (e < e2) { b2 = b; s2 = seed; e2 = e; }
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

// A lyric drip: a round bead of goo hanging from the bar on a neck, sinking
// as its line is sung (dropShape.y); then the neck snaps, it falls and bursts
// into droplets (dropShape.z). It swells in from a bead as it opens.
float lyricDrop(vec2 p, inout float hl) {
    float grow = smoothstep(0.0, 1.0, openProgress);
    float fall = dropShape.z;
    // a short drop, then it bursts while still in view
    float drop = 70.0 * smoothstep(0.0, 0.35, fall);
    float burst = smoothstep(0.12, 0.75, fall);
    float cx = panelRect.x + panelRect.z * 0.5;
    // the bead puffs up for a moment as it goes, then breaks apart
    float body = (1.0 + 0.18 * sin(min(burst * 2.0, 1.0) * 3.14)) * (1.0 - smoothstep(0.15, 0.5, burst));
    vec2 hs = vec2(panelRect.z * 0.5, dropShape.w * 0.5) * mix(0.18, 1.0, grow);
    vec2 full = hs;
    hs *= body;
    // squashed a little as it lets go
    hs *= vec2(1.0 + 0.1 * sin(min(fall * 4.0, 1.0) * 3.14), 1.0 - 0.08 * sin(min(fall * 4.0, 1.0) * 3.14));
    float top = barHeight + 6.0 + dropShape.y + drop;
    vec2 c = vec2(cx + sin(time * 1.3) * 1.5, top + full.y);
    float r = min(hs.x, hs.y);
    float d = hs.x > 0.5 ? sdRoundBox(p, c, hs, r * 0.98) + 0.9 * sin(time * 2.6 + p.x * 0.07 + p.y * 0.05) * grow : 1e5;
    if (hs.x > 0.5) d = smin(d, length(p - vec2(c.x, c.y - hs.y + 2.0)) - r * 0.35, 12.0);
    // the neck back up to the bar, thinner the further it has sunk; gone once it lets go
    if (fall < 0.02) {
        float nk = mix(7.5, 2.6, clamp(dropShape.y / 90.0, 0.0, 1.0)) * mix(0.6, 1.0, grow);
        d = smin(d, sdSegment(p, vec2(c.x, barHeight - 4.0), vec2(c.x, c.y - hs.y + 4.0), nk), 16.0);
    }
    // the burst: droplets flung out all round, arcing down, shrinking only at the end
    if (burst > 0.0) {
        for (int k = 0; k < 10; k++) {
            float a = float(k) * 0.628 + 0.3 + 0.4 * hash(float(k) + 9.0);
            float sp = 0.7 + 0.6 * hash(float(k) + 5.0);
            vec2 dir = vec2(cos(a) * full.x / max(full.y, 1.0), sin(a)) * sp;
            vec2 dp = c + dir * full.y * (0.4 + 1.8 * burst) + vec2(0.0, burst * burst * 55.0);
            float dr = (4.0 + 4.0 * hash(float(k) + 3.0)) * (1.0 - smoothstep(0.55, 1.0, burst)) * smoothstep(0.0, 0.15, burst);
            if (dr > 0.2) d = smin(d, length(p - dp) - dr, 3.0);
        }
    }
    if (r > 6.0 && burst < 0.3) hl = min(hl, length(p - (c + vec2(-0.45 * hs.x, -0.45 * hs.y))) - 0.16 * r);
    return d;
}

// The command centre / panel blob: a fat drip that falls, then spreads.
float openPanel(vec2 p, float ci, inout float hl) {
    if (dropShape.x > 0.5) return lyricDrop(p, hl);
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

// Gelatinous: the body quivers — travelling waves along the bar push its
// outline in and out, strongest along the underside, still at the screen edge.
float jelly(vec2 p) {
    float j = sin(p.x * 0.043 + time * 4.1) * 1.4
            + sin(p.x * 0.019 - time * 2.6) * 1.8
            + sin(p.x * 0.11 + time * 6.7) * 0.5;
    float band = smoothstep(0.0, barHeight, p.y) * (1.0 - smoothstep(barHeight + 30.0, barHeight + 70.0, p.y));
    return j * band;
}

vec2 mapSceneBody(vec2 p);
vec2 mapScene(vec2 p) {
    vec2 r = mapSceneBody(p);
    if (dripExtra.x > 2.5 && blobMode < 0.5) r.x += jelly(p);
    return r;
}

// where the dock melts into the bar, the bar holds its drips back
bool dockHides(float x) {
    return (dockBracket.x > 0.0 && x < dockBracket.x) || (dockBracket.y > 0.0 && x > cornerLen() - dockBracket.y);
}

vec2 mapSceneBody(vec2 p) {
    if (blobMode > 0.5) return mapBlob(p);
    float d = baseShape(p);
    float hl = 1e5;
    float ci = floor(p.x / CELL);

    // cava: evenly spaced bars, like a visualizer's (as many as asked for)
    if (dripExtra.x > 3.5) {
        float sp = cavaStep();
        float bi = floor(p.x / sp);
        for (int k = -1; k <= 1; k++) {
            float i = bi + float(k);
            float cx = (i + 0.5) * sp;
            if (dockHides(cx)) continue;
            float edge = dripEdge(cx);
            if (edge < 0.0) continue;
            vec2 dr = drip(p, cx, edge, i, 1.0);
            d = smin(d, dr.x, min(7.0, sp * 0.3));
            hl = min(hl, dr.y);
        }
    }
    else for (int k = -1; k <= 1; k++) {
        float i = ci + float(k);
        // torrent (amount > 1.8) packs more drips in as well as lengthening them
        if (hash(i * 3.7 + 11.0) < 1.0 - 0.7 * dripStyle.w * max(1.0, dripAmount * 0.55)) continue;
        float cx = (i + 0.5 + (hash(i) - 0.5) * 0.6) * CELL;
        if (dockHides(cx)) continue;
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

    // Only the two bulbs nearest this pixel can reach it (bulbs sit side by
    // side along the bar): a cheap pass picks them, then just those two are
    // evaluated. Calling bulb() for all 24 cost more than the rest of the
    // scene put together.
    vec4 b1 = vec4(0.0), b2 = vec4(0.0);
    float s1 = 0.0, s2 = 0.0, e1 = 1e5, e2 = 1e5;
    pickBulb(bulb0, 1.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb1, 2.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb2, 3.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb3, 4.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb4, 5.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb5, 6.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb6, 7.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb7, 8.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb8, 9.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb9, 10.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb10, 11.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb11, 12.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb12, 13.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb13, 14.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb14, 15.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb15, 16.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb16, 17.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb17, 18.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb18, 19.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb19, 20.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb20, 21.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb21, 22.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb22, 23.0, p.x, b1, s1, e1, b2, s2, e2);
    pickBulb(bulb23, 24.0, p.x, b1, s1, e1, b2, s2, e2);
    // blend them in their original order (smooth-min isn't order-free)
    if (s2 < s1 && s2 > 0.0) { vec4 tb = b1; b1 = b2; b2 = tb; float ts = s1; s1 = s2; s2 = ts; }
    vec2 bs = bulb(p, b1, s1); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);
    bs = bulb(p, b2, s2); d = smin(d, bs.x, 9.0); hl = min(hl, bs.y);

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

// Surface normal of the goo as a dome (shared by the lit styles).
vec3 domeNormal(vec2 p, float d) {
    vec2 g = vec2(mapScene(p + vec2(1.0, 0.0)).x - d, mapScene(p + vec2(0.0, 1.0)).x - d);
    float depth = clamp(-d / 10.0, 0.0, 1.0);
    float dome = sqrt(1.0 - (1.0 - depth) * (1.0 - depth));
    return normalize(vec3(g * (1.0 - dome) * 1.6, dome + 0.08));
}

// Cel (4): clean, graphic cel shading — three flat tones from real lighting,
// a crisp even ink outline, a thin rim light on the lit edge and one hard
// highlight. No texture, grain or glints.
vec3 cleanCel(vec2 p, float d, vec3 base) {
    vec3 n = domeNormal(p, d);
    vec3 L = normalize(vec3(-0.35, -0.6, 0.72));
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float diff = max(dot(n, L), 0.0);
    float spec = pow(max(dot(n, H), 0.0), 40.0);
    vec3 light = min(base * 1.22 + 0.08, vec3(1.0));
    vec3 shade = base * vec3(0.55, 0.58, 0.78);
    vec3 ink = mix(base * 0.1, vec3(0.03, 0.02, 0.07), 0.7);
    // hard band edges, anti-aliased over about a pixel — nudged by a little
    // noise so they read as brushed rather than ruled
    float aa = 0.04;
    float brush = (vnoise(p / 7.0) - 0.5) * 0.12 + (vnoise(p / 2.3) - 0.5) * 0.04;
    float inShade = 1.0 - smoothstep(0.55 - aa, 0.55 + aa, diff + brush);
    float inLight = smoothstep(0.9 - aa, 0.9 + aa, diff + brush * 0.7);
    vec3 col = mix(base, shade, inShade);
    col = mix(col, light, inLight * (1.0 - inShade));
    // each tone laid in as a soft, uneven wash (quieter behind widgets)
    float calm = labelZone(p);
    float wash = (vnoise(p / 18.0) - 0.5) * 0.2 + (vnoise(p / 6.0 + 3.1) - 0.5) * 0.09;
    col *= 1.0 + wash * (1.0 - calm * 0.6);
    // short ink strokes feathering the shadow's edge
    float edgeZone = smoothstep(0.3, 0.5, diff + brush) * (1.0 - smoothstep(0.5, 0.75, diff + brush));
    float u = dot(p, vec2(0.6, -0.8));
    float stroke = 1.0 - smoothstep(0.2, 0.7, abs(fract(u / 4.5) - 0.5) * 4.5);
    float dash = step(0.45, vnoise(vec2(u * 0.12, floor(u / 4.5) * 5.7)));
    col = mix(col, shade * 0.7, stroke * dash * edgeZone * 0.55 * (1.0 - calm));
    // fine paper grain over it all
    col *= 1.0 + (hash2(floor(p * 0.8)) - 0.5) * 0.08 + (vnoise(p / 1.4) - 0.5) * 0.06;
    // rim light: a thin bright line just inside the lit side of the edge
    float rimBand = fill(-(d + 4.2)) * (1.0 - fill(-(d + 2.6)));
    float litSide = smoothstep(0.2, 0.6, dot(normalize(n.xy + 1e-4), -normalize(L.xy)));
    col = mix(col, light * 1.05, rimBand * litSide * 0.9);
    // one hard highlight
    col = mix(col, vec3(1.0), smoothstep(0.55, 0.6, spec) * step(d, -3.0));
    // crisp outline of even weight
    col = mix(col, ink, smoothstep(-3.0, -2.0, d));
    return col;
}

// Sketch (5): coloured pencil on paper. A pale pencil fill, graphite hatching
// that thickens into cross-hatching in shadow, and two or three wobbly,
// overshooting outline strokes (drawn a little outside the goo too).
vec4 sketchShade(vec2 p, float d, vec3 base) {
    vec3 n = domeNormal(p, d);
    vec3 L = normalize(vec3(-0.35, -0.6, 0.72));
    float diff = max(dot(n, L), 0.0);
    vec3 paper = mix(paperColor.rgb, vec3(0.97, 0.95, 0.9), 0.5);
    vec3 graphite = vec3(0.16, 0.15, 0.17);
    // pencil fill: colour laid on lightly, heavier in shadow, with tooth
    float tooth = vnoise(p * vec2(0.9, 0.25)) * 0.5 + hash2(floor(p * 0.7)) * 0.5;
    float press = mix(0.7, 1.0, 1.0 - diff) * (0.8 + 0.3 * tooth);
    vec3 col = mix(paper, base, clamp(press, 0.0, 1.0));
    // hatching: wobbly strokes, a second crossing layer in the deep shadow
    float wob = (vnoise(p / 9.0) - 0.5) * 2.5;
    float u = dot(p, vec2(0.62, -0.78)) + wob;
    float v = dot(p, vec2(0.78, 0.62)) - wob;
    float h1 = 1.0 - smoothstep(0.25, 0.9, abs(fract(u / 5.0) - 0.5) * 5.0);
    float h2 = 1.0 - smoothstep(0.25, 0.9, abs(fract(v / 6.0) - 0.5) * 6.0);
    float dark = 1.0 - diff;
    float strokeBreak = step(0.3, vnoise(vec2(u * 0.08, floor(u / 5.0) * 3.1)));
    // (the goo's flat top counts as lit, so hatching keys off the lower,
    // rounder parts and the underside)
    float under = clamp(dot(n.xy, vec2(0.0, 1.0)), 0.0, 1.0);
    dark = clamp(dark + under * 0.6, 0.0, 1.0);
    float hatch = h1 * smoothstep(0.12, 0.3, dark) * strokeBreak + h2 * smoothstep(0.4, 0.6, dark);
    float calm = labelZone(p);
    col = mix(col, graphite, clamp(hatch, 0.0, 1.0) * 0.6 * (1.0 - calm * 0.85));
    // outlines: a few passes, each shifted and wobbling, overshooting the shape
    float line = 0.0;
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float off = (vnoise(p / (14.0 + fk * 5.0) + fk * 7.3) - 0.5) * 3.2 + fk * 0.6 - 0.8;
        float w = 0.7 + 0.35 * vnoise(p / 5.0 + fk * 3.0);
        line = max(line, (1.0 - smoothstep(w - 0.4, w + 0.4, abs(d + off))) * (0.7 + 0.3 * vnoise(p / 3.0 + fk)));
    }
    col = mix(col, graphite, line);
    float alpha = max(fill(d), line * 0.95);
    return vec4(col, alpha);
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
    // neither the ink nor the colour plate covers this pixel: it'd come out
    // fully transparent, so skip the shadow-shape passes below
    if (d >= 0.5 && dc >= 0.5) return vec4(0.0);

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
    // The bar window grows tall while the command centre is open, but below
    // the drip zone nothing lives outside the panel's column: skip those
    // pixels outright (most of the window) rather than run the whole scene.
    if (dripExtra.w > 0.0 && p.y > dripExtra.w &&
        (openProgress < 0.001 || p.x < panelRect.x - 90.0 || p.x > panelRect.x + panelRect.z + 90.0)) {
        fragColor = vec4(0.0);
        return;
    }
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
    // (the dock: z shifts its gradient to carry on from the bar's where they meet)
    float gx = p.x + (barShape > 4.5 ? dockBracket.z : 0.0);
    float gt = 0.45 + 0.35 * sin(gx * 0.0022 + time * 0.12) + (p.y - barHeight) / 220.0;
    vec3 base = mix(slimeColor.rgb, slimeColor2.rgb, smoothstep(0.0, 1.0, gt));
    // materials start from the theme colour and push it toward their stuff
    if (material > 0.5 && material < 1.5) base = toneShift(base, 0.985, 0.75, 1.05, 0.95);          // flesh
    else if (material > 1.5 && material < 2.5) base = mix(paperColor.rgb, base, 0.14);               // ivory
    vec3 col = vec3(0.0);
    if (shadingStyle > 4.5) {
        vec4 sk = sketchShade(p, d, base);
        col = sk.rgb;
        alpha = sk.a;
    } else if (shadingStyle > 3.5) {
        if (alpha > 0.0) col = cleanCel(p, d, base);
    } else if (shadingStyle > 2.5) {
        vec4 printed = printShade(p, scene, base);
        col = printed.rgb;
        alpha = printed.a;
    } else if (alpha > 0.0) {
        col = shadingStyle < 0.5 ? softShade(p, d, base) : celShade(p, scene, base, shadingStyle > 1.5);
    }

    // (colour only matters where something is drawn; skip it where nothing is)
    if (alpha > 0.0) col = materialSurface(p, d, col, base);

    if (poolDepth > 0.0 && openProgress > 0.0) {
        float inBox = step(panelRect.x + 12.0, p.x) * step(p.x, panelRect.x + panelRect.z - 12.0)
                    * step(barHeight + 12.0, p.y);
        float deep = smoothstep(-10.0, -22.0, d) * inBox * poolDepth;
        vec3 pool = toneShift(base, 0.74, 0.3, 1.1, 0.22);
        pool *= 1.0 + (hash2(floor(p)) - 0.5) * 0.08 + (vnoise(p / 2.5) - 0.5) * 0.06;
        col = mix(col, pool, deep);
    }

    // Drop shadow so the ooze sits above whatever is underneath.
    // (it only shows through where the goo isn't solid: skip the extra scene
    // pass under opaque goo, where it'd be multiplied by zero)
    float shadow = 0.0;
    if (alpha < 1.0) {
        float ds = mapScene(p - vec2(0.0, 4.0)).x;
        shadow = (1.0 - smoothstep(-2.0, 12.0, ds)) * 0.35;
    }

    vec4 slime = vec4(col * alpha, alpha);
    fragColor = (slime + vec4(0.0, 0.0, 0.0, shadow) * (1.0 - alpha)) * qt_Opacity;
}
