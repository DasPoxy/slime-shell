#!/usr/bin/env python3
"""Build "Slime Honey Drip": Lobster (SIL OFL) with honey drips hanging off
its letters, for Slime Shell's "honey drip" font style.

Every glyph is scanned in columns for lower edges (the underside of a stroke,
bowl or crossbar); a seeded-random subset of those edges grows a drip: a
flared neck that blends into the letter, a stem, and a round bulb. Drips off
the bottom of a letter run long, ones from inner strokes stay short. The drips
are unioned into the outline, hinting is dropped (it no longer fits) and the
font is renamed, since "Lobster" is a Reserved Font Name.

Needs fonttools and skia-pathops (a throwaway venv is fine):
    python3 -m venv /tmp/fontenv
    /tmp/fontenv/bin/pip install fonttools skia-pathops
    /tmp/fontenv/bin/python tools/make-drip-font.py Lobster-Regular.ttf \
        plugins/slime.bar/fonts/SlimeHoneyDrip-Regular.ttf
"""
import random
import sys

import pathops
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.ttProgram import Program

FAMILY = "Slime Honey Drip"
PS_NAME = "SlimeHoneyDrip-Regular"

COL = 30          # column spacing when looking for edges (font units, upm 1000)
ROW = 6           # vertical scan step
LOWEST_DRIP = -330  # no drip reaches below this (keeps them near the line)


def circle(path, cx, cy, r):
    k = 0.5523 * r
    path.moveTo(cx + r, cy)
    path.cubicTo(cx + r, cy + k, cx + k, cy + r, cx, cy + r)
    path.cubicTo(cx - k, cy + r, cx - r, cy + k, cx - r, cy)
    path.cubicTo(cx - r, cy - k, cx - k, cy - r, cx, cy - r)
    path.cubicTo(cx + k, cy - r, cx + r, cy - k, cx + r, cy)
    path.close()


def drip(path, x, edge, length, width, thick):
    """A drip hanging from a lower edge at (x, edge), `length` long."""
    hw = width / 2
    flare = width * 0.8
    top = edge + min(14, thick * 0.45)     # tuck the neck up into the stroke
    bot = edge - length
    path.moveTo(x - hw - flare, top)
    path.quadTo(x - hw, top, x - hw, edge - flare)
    path.lineTo(x - hw * 0.85, bot)
    path.lineTo(x + hw * 0.85, bot)
    path.lineTo(x + hw, edge - flare)
    path.quadTo(x + hw, top, x + hw + flare, top)
    path.close()
    circle(path, x, bot, hw * 1.35)


def lower_edges(outline, x, y0, y1):
    """(edge y, stroke thickness above it) for each inside->outside step going down."""
    out = []
    inside = False
    run_top = None
    y = y1
    while y >= y0:
        now = outline.contains((x, y))
        if now and not inside:
            run_top = y
        if inside and not now:
            out.append((y + ROW / 2, run_top - y))
        inside = now
        y -= ROW
    return out


def free_below(outline, x, edge, width, ymin):
    """How far below `edge` the column (and its sides) stays clear of the glyph."""
    y = edge - ROW * 2
    while y > ymin - 400:
        for dx in (-width * 0.6, 0, width * 0.6):
            if outline.contains((x + dx, y)):
                return edge - y
        y -= ROW
    return 1e6


def add_drips(name, outline):
    xmin, ymin, xmax, ymax = outline.bounds
    if xmax - xmin < 40 or ymax - ymin < 40:
        return None
    rnd = random.Random(name)
    drips = pathops.Path()
    placed = []            # (x, edge y) of drips so far, to keep them apart
    lowest = ymin + ROW * 2
    x = xmin + COL / 2 + rnd.random() * COL * 0.5
    any_drip = False
    while x < xmax - COL / 3:
        for edge, thick in lower_edges(outline, x, ymin - ROW, ymax + ROW):
            if thick < 45:
                continue
            bottom = edge <= lowest + 40
            if rnd.random() > (0.55 if bottom else 0.35):
                continue
            if any(abs(px - x) < 140 and abs(py - edge) < 90 for px, py in placed):
                continue
            length = rnd.uniform(70, 250) if bottom else rnd.uniform(40, 110)
            length = min(length, edge - LOWEST_DRIP)
            width = rnd.uniform(44, 70)
            # only hang in open air: stop short of any stroke below (a drip
            # running into a counter's floor just looks like a notch)
            room = free_below(outline, x, edge, width, ymin)
            length = min(length, room - width * 0.7 - 18)
            if length < 35:
                continue
            drip(drips, x, edge, length, width, thick)
            placed.append((x, edge))
            any_drip = True
        x += COL
    if not any_drip:
        return None
    result = pathops.Path()
    pathops.union([outline, drips], result.getPen(), fix_winding=True, clockwise=True)
    return result


def main(src, dst):
    font = TTFont(src)
    glyf = font["glyf"]
    gs = font.getGlyphSet()
    changed = 0
    for name in font.getGlyphOrder():
        g = glyf[name]
        if g.isComposite() or g.numberOfContours <= 0:
            continue
        outline = pathops.Path()
        gs[name].draw(outline.getPen())
        new = add_drips(name, outline)
        if new is None:
            continue
        pen = TTGlyphPen(gs)
        new.draw(Cu2QuPen(pen, max_err=1.0, reverse_direction=False))
        ng = pen.glyph()
        ng.recalcBounds(glyf)
        glyf[name] = ng
        changed += 1

    # the old hints don't fit the new outlines
    for tag in ("fpgm", "prep", "cvt ", "DSIG", "gasp"):
        if tag in font:
            del font[tag]
    for name in font.getGlyphOrder():
        g = glyf[name]
        if g.numberOfContours != 0:
            g.program = Program()
            g.program.fromBytecode(b"")
    font["maxp"].maxSizeOfInstructions = 0

    # rename (Reserved Font Name): keep the copyright, say what this is
    for rec in font["name"].names:
        if rec.nameID in (1, 16):
            rec.string = FAMILY
        elif rec.nameID in (4, 18):
            rec.string = FAMILY + " Regular" if rec.nameID == 4 else FAMILY
        elif rec.nameID == 3:
            rec.string = "SlimeShell:" + PS_NAME
        elif rec.nameID == 6:
            rec.string = PS_NAME
        elif rec.nameID == 5:
            rec.string = str(rec) + "; Slime Shell honey drips"
    font.save(dst)
    print(f"{changed} glyphs dripping -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
