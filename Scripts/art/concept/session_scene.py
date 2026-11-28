#!/usr/bin/env python3
"""The scene while a session runs: the maple and Pip from the concept picture, in a landscape drawn here.

The owner turned down the maple on a small raised patch of grass over a plain sky ("why is the tree on a small
elevated platform"), and flat drawn backdrops ("so dull and unrealistic"), and asked for it drawn here (28 Nov 2026).
So: a warm sky with the sun low on the right; hazy far hills with a far row of trees; a nearer row of autumn trees in
the concept's own look (a lighter crown over darker lobes, thick dark outlines); and a meadow that runs off every edge,
rolling gently, with grass tufts, fallen leaves (the concept's own), mushrooms and a few flowers. The middle of the
lower meadow is kept quiet for the time left and the buttons.

Layers, so clouds can drift between the sky and the maple:
- `VanTreeBackdrop`: everything behind the maple.
- `VanTreeCloud0…2`: clouds, drawn here, which the app moves.
- `VanTreeMaple`: the concept's maple with its sky taken out and its painted mid-air leaves gone (they swing and fall
  at home; here the app's own leaves fall), its trunk carried down to the meadow.
- `VanTreeBasketBack`, `VanTreeBasketFront`, `VanTreeBasket`, `VanTreePip`: Pip's woven wicker basket ("make the
  bucket from classic woven wicker"), in Pip's square, behind and in front of the leaves heaped in it, whole, and in
  his paw.

    python3 -I Scripts/art/concept/session_scene.py [preview folder]
"""

import importlib.util
import math
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("build_concept_art", HERE / "build_concept_art.py")
art = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(art)

W, H = art.TREE_W, art.TREE_H
LINE = art.LINE
PEACH = art.PEACH
# Where the far hills meet the sky, and where the meadow's top edge runs in front of the near trees.
HORIZON = 1420
MEADOW_TOP = 1505
# Kept quiet: the time left and the buttons sit over this part of the meadow.
QUIET = (250, 1900, 950, 2420)
HORIZON_SKY = (255, 233, 210)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(stops, size=(W, H)):
    w, h = size
    col = np.zeros((h, 3), np.float32)
    ys = np.linspace(0, 1, h)
    for (f0, c0), (f1, c1) in zip(stops, stops[1:]):
        sel = (ys >= f0) & (ys <= f1)
        t = (ys[sel] - f0) / max(1e-6, f1 - f0)
        t = t * t * (3 - 2 * t)
        col[sel] = np.array(c0) + (np.array(c1) - np.array(c0)) * t[:, None]
    return Image.fromarray(np.repeat(col[:, None, :], w, axis=1).astype(np.uint8)).convert("RGBA")


def glow(image, cx, cy, r, colour, strength):
    yy, xx = np.mgrid[0:image.height, 0:image.width]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    a = np.clip(1 - d, 0, 1) ** 2 * strength
    layer = Image.new("RGBA", image.size, colour + (0,))
    layer.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
    image.alpha_composite(layer)


# ---------- the land ----------

def ridge(base, amp, phase, freq, x0=-60, x1=W + 60, n=80):
    pts = []
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        u = x / W * 2 * math.pi
        y = base - amp * (0.6 * math.sin(freq * u + phase) + 0.4 * math.sin(2.3 * freq * u + 1.7 * phase))
        pts.append((x, y))
    return pts


def crown(ink, cx, ground, h, light, dark, line, width, rng):
    """An autumn tree in the concept's look: a trunk, a lumpy crown in a light tone over darker lower lobes, all with
    its dark outline."""
    bark = mix((143, 84, 52), light, 0.25)
    tw = h * 0.07
    trunk = [(cx - tw, ground + 4), (cx - tw * 0.8, ground - h * 0.42), (cx + tw * 0.8, ground - h * 0.42), (cx + tw, ground + 4)]
    ink.fill(trunk, bark)
    ink.line(trunk, line, width)
    r = h * 0.36
    my = ground - h * 0.58
    puffs = [(0, -0.42, 0.62), (-0.58, -0.12, 0.56), (0.58, -0.1, 0.56), (-0.36, 0.3, 0.58), (0.38, 0.32, 0.56),
             (0.02, 0.08, 0.66), (-0.18, -0.5, 0.42), (0.3, -0.46, 0.44)]
    puffs = [(dx + rng.uniform(-0.06, 0.06), dy + rng.uniform(-0.05, 0.05), rr * rng.uniform(0.92, 1.08)) for dx, dy, rr in puffs]
    for dx, dy, rr in puffs:
        ink.ellipse(cx + dx * r, my + dy * r, rr * r + width / 2, rr * r * 0.94 + width / 2, line)
    for dx, dy, rr in puffs:
        ink.ellipse(cx + dx * r, my + dy * r, rr * r - width / 2, rr * r * 0.94 - width / 2, light)
    # The darker lobes below, each with its own outline, as the concept's canopy has them.
    for dx, dy, rr in [(-0.34, 0.36, 0.42), (0.36, 0.38, 0.4), (0.0, 0.46, 0.38)]:
        dx += rng.uniform(-0.05, 0.05)
        ink.ellipse(cx + dx * r, my + dy * r, rr * r, rr * r * 0.86, dark, line, width * 0.7)


def pine(ink, cx, ground, h, light, dark, line, width):
    tiers = 3
    for i in range(tiers):
        top = ground - h + i * h * 0.22
        bottom = ground - h * 0.18 - (tiers - 1 - i) * h * 0.2
        half = h * (0.18 + 0.07 * i)
        pts = [(cx, top), (cx + half, bottom), (cx - half, bottom)]
        ink.fill(pts, light if i % 2 == 0 else mix(light, dark, 0.5))
        ink.line(pts + [pts[0]], line, width)
    ink.fill([(cx - h * 0.03, ground - h * 0.18), (cx + h * 0.03, ground - h * 0.18), (cx + h * 0.03, ground), (cx - h * 0.03, ground)],
             (120, 80, 50))


def tuft(ink, x, y, s, colour):
    for dx, lean in ((-0.5, -0.5), (0, 0.05), (0.5, 0.5)):
        ink.line([(x + dx * 6 * s, y), (x + dx * 6 * s + lean * 10 * s, y - 18 * s)], colour, 2.6 * s)


def flower(ink, x, y, s, petal):
    for k in range(5):
        a = k * 2 * math.pi / 5
        ink.ellipse(x + math.cos(a) * 5 * s, y + math.sin(a) * 5 * s, 4.2 * s, 4.2 * s, petal)
    ink.ellipse(x, y, 3 * s, 3 * s, (236, 160, 60))


def quiet(x, y):
    return QUIET[0] < x < QUIET[2] and QUIET[1] < y < QUIET[3]


def backdrop(van):
    rng = random.Random(7)
    img = gradient([(0, (249, 196, 142)), (0.22, (252, 210, 166)), (0.48, (255, 226, 198)), (HORIZON / H, HORIZON_SKY),
                    (1, HORIZON_SKY)])
    glow(img, 930, 1210, 520, (255, 244, 205), 0.7)
    ink = art.Ink((W, H), k=2)
    ink.ellipse(930, 1250, 92, 92, (255, 238, 186))

    # Far hills, hazy, with a far row of trees on them.
    far_line = mix((214, 160, 125), HORIZON_SKY, 0.2)
    hill = ridge(HORIZON - 20, 34, 0.6, 1.1)
    ink.fill(hill + [(W + 60, H), (-60, H)], mix((232, 178, 140), HORIZON_SKY, 0.35))
    ink.line(hill, far_line, 3)
    for i in range(15):
        x = -30 + i * 88 + rng.uniform(-24, 24)
        h = rng.uniform(150, 215)
        colour = rng.choice([(240, 150, 84), (226, 118, 66), (240, 184, 96)])
        light = mix(colour, HORIZON_SKY, 0.5)
        crown(ink, x, HORIZON + 40 + rng.uniform(-8, 8), h, light, mix(light, (190, 100, 60), 0.25), far_line, 2.6, rng)
    ink.fill(ridge(HORIZON + 46, 10, 2.0, 1.4) + [(W + 60, H), (-60, H)], mix((214, 196, 130), HORIZON_SKY, 0.35))

    # The near row: maples in the concept's colours, crowns overlapping, over a shaded forest floor.
    near_line = mix(LINE, (214, 160, 125), 0.35)
    floor = ridge(MEADOW_TOP - 70, 16, 0.4, 2.2)
    ink.fill(floor + [(W + 60, MEADOW_TOP + 40), (-60, MEADOW_TOP + 40)], mix((176, 96, 60), HORIZON_SKY, 0.2))
    xs = [-60 + i * 96 + rng.uniform(-20, 20) for i in range(15)]
    rng.shuffle(xs)
    for x in xs:
        h = rng.uniform(300, 430)
        ground = MEADOW_TOP + 14 + rng.uniform(-6, 10)
        light, dark = rng.choice([((240, 142, 72), (222, 104, 52)), ((218, 96, 58), (188, 72, 44)),
                                  ((244, 182, 86), (228, 140, 62)), ((236, 128, 64), (204, 86, 48))])
        light = mix(light, HORIZON_SKY, 0.12)
        dark = mix(dark, HORIZON_SKY, 0.12)
        crown(ink, x, ground, h, light, dark, near_line, 3.6, rng)
    ink.onto(img)

    # The meadow, running off every edge, a little lighter toward the trees.
    meadow = gradient([(0, (190, 184, 112)), (MEADOW_TOP / H, (190, 184, 112)), (0.75, (168, 166, 100)), (1, (150, 152, 90))])
    edge = ridge(MEADOW_TOP, 9, 1.1, 1.7)
    mask = Image.new("L", (W * 2, H * 2), 0)
    ImageDraw.Draw(mask).polygon([(x * 2, y * 2) for x, y in edge + [(W + 60, H + 10), (-60, H + 10)]], fill=255)
    mask = mask.resize((W, H), Image.LANCZOS)
    img.paste(meadow, (0, 0), mask)
    ink = art.Ink((W, H), k=2)
    ink.line(edge, (112, 112, 64), 4)
    # Gentle rises in the meadow: a lighter crest with a darker line under it.
    for base, amp, phase, x0, x1 in [(1760, 26, 0.3, 560, W + 60), (2010, 30, 2.2, -60, 470), (2470, 22, 1.0, 820, W + 60)]:
        crest = ridge(base, amp, phase, 1.0, x0, x1, 40)
        band = crest + [(x, y + 26) for x, y in reversed(crest)]
        ink.fill(band, (178, 176, 106))
        ink.line(crest, (124, 124, 74), 3.4)

    # Grass tufts, small flowers and fallen leaves, fewer far off and none in the quiet middle.
    for _ in range(170):
        x = rng.uniform(-10, W + 10)
        y = rng.uniform(MEADOW_TOP + 18, H - 10)
        if quiet(x, y):
            continue
        depth = (y - MEADOW_TOP) / (H - MEADOW_TOP)
        tuft(ink, x, y, 0.55 + 0.9 * depth, (112, 116, 62))
    for _ in range(26):
        x = rng.uniform(20, W - 20)
        y = rng.uniform(MEADOW_TOP + 60, H - 40)
        if quiet(x, y):
            continue
        depth = (y - MEADOW_TOP) / (H - MEADOW_TOP)
        flower(ink, x, y, 0.6 + 0.8 * depth, rng.choice([(255, 246, 228), (252, 222, 120)]))
    ink.onto(img)

    is_sky = art.near(PEACH, 30)
    leaves = [art.cut_from(van, (1474, 410, 1606, 536), is_sky), art.cut_from(van, (1284, 262, 1396, 356), is_sky),
              art.cut_from(van, (1632, 1574, 1722, 1660), art.is_grass)]
    for _ in range(30):
        x = rng.uniform(0, W)
        y = rng.uniform(MEADOW_TOP + 40, H - 30)
        if quiet(x, y) and rng.random() < 0.8:
            continue
        depth = (y - MEADOW_TOP) / (H - MEADOW_TOP)
        leaf = rng.choice(leaves)
        k = 0.3 + 0.55 * depth
        small = leaf.resize((max(4, round(leaf.width * k)), max(4, round(leaf.height * k))), Image.LANCZOS)
        small = small.rotate(rng.uniform(0, 360), resample=Image.BICUBIC, expand=True)
        img.alpha_composite(small, (round(x - small.width / 2), round(y - small.height / 2)))
    mushrooms = art.cut_from(van, (1372, 1606, 1502, 1734), art.is_grass)
    for (x, y), k in [((820, 1700), 0.9), ((1060, 1860), 0.7), ((120, 2140), 1.1), ((1020, 2480), 1.2)]:
        m = mushrooms.resize((round(mushrooms.width * k), round(mushrooms.height * k)), Image.LANCZOS)
        img.alpha_composite(m, (round(x - m.width / 2), round(y - m.height)))
    return img.convert("RGB"), leaves


def clouds():
    out = []
    for seed, (w, h) in enumerate([(300, 130), (220, 100), (170, 80)]):
        rng = random.Random(30 + seed)
        size = (w + 40, h + 40)
        ink = art.Ink(size, k=3)
        puffs = [(0.22, 0.62, 0.2), (0.4, 0.42, 0.26), (0.62, 0.38, 0.24), (0.8, 0.6, 0.18), (0.5, 0.66, 0.22)]
        puffs = [(px * w + 20 + rng.uniform(-6, 6), py * h + 20 + rng.uniform(-4, 4), r * w * rng.uniform(0.95, 1.05)) for px, py, r in puffs]
        for x, y, r in puffs:
            ink.ellipse(x, y, r + 2.4, r * 0.82 + 2.4, (224, 172, 140))
        for x, y, r in puffs:
            ink.ellipse(x, y, r - 1.2, r * 0.82 - 1.2, (255, 245, 232))
        # A flat, slightly shaded underside.
        ink.fill([(20, h * 0.72 + 20), (w + 20, h * 0.72 + 20), (w + 20, h + 40), (20, h + 40)], (0, 0, 0)) if False else None
        img = Image.new("RGBA", size, (0, 0, 0, 0))
        ink.onto(img)
        out.append(img)
    return out


# ---------- the maple ----------

def maple(van):
    """The concept's maple with its sky taken out, the painted mid-air leaves gone, and its trunk carried down to the
    meadow, flaring into a soft shadow."""
    tree = van.crop((0, 0, W, art.TREE_CUT)).convert("RGBA")
    d = ImageDraw.Draw(tree)
    d.polygon([(536, 682), (545, 669), (880, 669), (880, 428), (1012, 428), (1045, 395), (1045, 318), (W, 318),
               (W, art.TREE_CUT), (483, art.TREE_CUT), (483, 862), (485, 822), (489, 783), (497, 763), (508, 738),
               (524, 704)], fill=PEACH + (255,))
    d.rectangle([70, 950, 180, art.TREE_CUT], fill=PEACH + (255,))
    for name, (piece, box) in art.canopy_leaves(van).items():
        if name.endswith("Gap"):
            tree.alpha_composite(piece, box[:2])
    rgb = np.asarray(tree.convert("RGB")).astype(np.float32)
    # The sky: peach that reaches the picture's edge, and the soft edge round it.
    sky = art.outside(art.near(PEACH, 40)(rgb.astype(np.int32)))
    fringe = art.grow(sky, 3)
    dist = np.sqrt(((rgb - np.array(PEACH)) ** 2).sum(axis=2))
    alpha = np.where(fringe, np.clip((dist - 18) / 60, 0, 1), 1.0)
    alpha[sky] = np.minimum(alpha[sky], 0)
    unmixed = np.clip((rgb - (1 - alpha[..., None]) * np.array(PEACH)) / np.maximum(alpha, 1e-3)[..., None], 0, 255)
    cut = Image.fromarray(np.dstack([unmixed, alpha * 255]).astype(np.uint8), "RGBA")

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ink = art.Ink((W, H), k=3)
    ink.ellipse(360, 1588, 230, 34, (128, 128, 76))
    ink.onto(out)
    out.alpha_composite(cut, (0, 0))
    band = np.asarray(van.crop((228, art.TREE_CUT - 16, 492, art.TREE_CUT - 2))).astype(np.float32).mean(axis=0)
    cd = np.sqrt(((band - np.array(PEACH)) ** 2).sum(axis=1))
    ca = np.clip((cd - 18) / 60, 0, 1)
    crgb = np.clip((band - (1 - ca[:, None]) * np.array(PEACH)) / np.maximum(ca, 1e-3)[:, None], 0, 255)
    column = Image.fromarray(np.concatenate([crgb, (ca * 255)[:, None]], axis=1)[None].astype(np.uint8), "RGBA")
    out.alpha_composite(column.resize((492 - 228, 1470 - art.TREE_CUT + 2), Image.NEAREST), (228, art.TREE_CUT - 2))
    darkness = 255 - band.mean(axis=1)
    lx = 228 + float(np.average(np.arange(0, 40), weights=np.clip(darkness[:40] - 190, 0, None)))
    rx = 228 + float(np.average(np.arange(224, 264), weights=np.clip(darkness[224:] - 190, 0, None)))
    ink = art.Ink((W, H), k=3)
    left = [(lx, 1400)] + art.curve([(lx, 1440), (lx - 3, 1492), (lx - 20, 1538), (lx - 58, 1566), (lx - 94, 1578)])
    right = [(rx, 1400)] + art.curve([(rx, 1440), (rx + 3, 1492), (rx + 20, 1538), (rx + 58, 1566), (rx + 94, 1578)])
    foot = art.curve([(lx - 94, 1578), (lx + 10, 1590), ((lx + rx) / 2, 1594), (rx - 10, 1590), (rx + 94, 1578)])
    ink.fill(left + foot + right[::-1], art.BARK)
    ink.line(left + foot[1:] + right[::-1][1:], LINE, 3.6)
    ink.onto(out)
    return out


# ---------- Pip's wicker basket ----------

WICKER = (222, 170, 96)
WICKER_LIGHT = (240, 200, 128)
WICKER_DARK = (150, 98, 52)
INSIDE = (118, 74, 38)
# In Pip's square (`PIP_BOX`): where his paw grips the handle, the basket's middle, its rim and its bottom.
GRIP = (636, 430)
CX, RIM, BOTTOM, HALF = 684, 532, 690, 82
FOOT = HALF - 20


def basket_layers():
    x0, y0 = art.PIP_BOX[0], art.PIP_BOX[1]
    size = (art.PIP_BOX[2] - x0, art.PIP_BOX[3] - y0)
    at = lambda pts: [(x - x0, y - y0) for x, y in pts]  # noqa: E731

    back = art.Ink(size)
    # The handle: one woven hoop from each side of the rim up to his paw.
    for end in (CX - HALF + 6, CX + HALF - 6):
        bend = 10 if end > CX else -6
        handle = art.curve([(end, RIM), ((end + GRIP[0]) / 2 + bend, (RIM + GRIP[1]) / 2 + 4), GRIP])
        back.line(at(handle), LINE, 15)
        back.line(at(handle), WICKER, 8)
        for i in range(2, len(handle) - 2, 3):
            (ax, ay), (bx, by) = handle[i - 1], handle[i + 1]
            nx, ny = -(by - ay), bx - ax
            n = math.hypot(nx, ny) or 1
            mx, my = handle[i]
            back.line(at([(mx - nx / n * 3.5, my - ny / n * 3.5), (mx + nx / n * 3.5 + (bx - ax) * 0.3, my + ny / n * 3.5 + (by - ay) * 0.3)]), WICKER_DARK, 1.8)
    back.ellipse(CX - x0, RIM - y0, HALF, 22, INSIDE, LINE, 5)
    back_img = Image.new("RGBA", size, (0, 0, 0, 0))
    back.onto(back_img)

    front = art.Ink(size)
    side = [(CX - HALF, RIM), (CX - FOOT, BOTTOM - 10)] + art.curve([(CX - FOOT, BOTTOM - 10), (CX, BOTTOM + 4), (CX + FOOT, BOTTOM - 10)]) + [(CX + HALF, RIM)]
    lip = art.curve([(CX - HALF, RIM), (CX - 40, RIM + 18), (CX, RIM + 22), (CX + 40, RIM + 18), (CX + HALF, RIM)])
    front.fill(at(side + lip[::-1]), WICKER)

    def half_width(y):
        t = (y - RIM) / (BOTTOM - RIM)
        return HALF + (FOOT - HALF) * t

    # The weave: rows that follow the basket's curve, with short uprights between them, every other row offset.
    rows = 6
    for k in range(1, rows):
        y = RIM + 18 + k * (BOTTOM - RIM - 18) / rows
        hw = half_width(y) - 3
        front.line(at(art.curve([(CX - hw, y - 2), (CX, y + 8), (CX + hw, y - 2)], 10)), WICKER_DARK, 2.6)
    for k in range(rows):
        top = RIM + 18 + k * (BOTTOM - RIM - 18) / rows
        bottom = top + (BOTTOM - RIM - 18) / rows
        hw = half_width((top + bottom) / 2) - 8
        step = 20
        offset = 0 if k % 2 == 0 else step / 2
        x = CX - hw + offset
        while x < CX + hw:
            sag = 8 * (1 - ((x - CX) / max(1, hw)) ** 2)
            front.line(at([(x, top + sag + 3), (x, bottom + sag - 3)]), WICKER_DARK, 2.2)
            x += step
    front.line(at(side), LINE, 5)
    # The rim: a thick braided band.
    band_top = lip
    band_bottom = [(x, y + 14) for x, y in lip]
    front.fill(at(band_top + band_bottom[::-1]), WICKER_LIGHT)
    for i in range(1, len(lip) - 1, 2):
        (x, y) = lip[i]
        front.line(at([(x - 5, y + 2), (x + 5, y + 12)]), WICKER_DARK, 2.2)
    front.line(at(band_top), LINE, 5)
    front.line(at(band_bottom), LINE, 3.6)
    front_img = Image.new("RGBA", size, (0, 0, 0, 0))
    front.onto(front_img)
    return back_img, front_img


# Where the leaves heaped in the basket sit, in Pip's square, in the order they come as the session goes on:
# (x, y, turn in degrees, size, which leaf). The app draws as many as the session is long (`PipBasket.heap`).
HEAP = [(650, 522, -24, 0.55, 0), (716, 520, 28, 0.55, 1), (684, 514, 6, 0.6, 2), (630, 506, -46, 0.58, 1),
        (738, 506, 50, 0.55, 0), (664, 494, -12, 0.64, 2), (706, 492, 22, 0.64, 0), (684, 478, 0, 0.7, 1)]


def heap_onto(sprite, leaves, count=len(HEAP)):
    x0, y0 = art.PIP_BOX[0], art.PIP_BOX[1]
    for x, y, turn, k, which in HEAP[:count]:
        leaf = leaves[which]
        small = leaf.resize((round(leaf.width * k), round(leaf.height * k)), Image.LANCZOS)
        small = small.rotate(-turn, resample=Image.BICUBIC, expand=True)
        sprite.alpha_composite(small, (round(x - x0 - small.width / 2), round(y - y0 - small.height / 2)))


def main():
    van = Image.open(art.CONCEPTS / "syrup-van.jpg").convert("RGB")
    ground, leaves = backdrop(van)
    art.imageset("VanTreeBackdrop", "tree-backdrop.jpg", ground, quality=90)
    tree = maple(van)
    art.imageset("VanTreeMaple", "tree-maple.png", tree)
    for i, cloud in enumerate(clouds()):
        art.imageset(f"VanTreeCloud{i}", f"tree-cloud{i}.png", cloud)
    back, front = basket_layers()
    art.imageset("VanTreeBasketBack", "basket-back.png", back)
    art.imageset("VanTreeBasketFront", "basket-front.png", front)
    whole = back.copy()
    heap_onto(whole, leaves)
    whole.alpha_composite(front)
    art.imageset("VanTreeBasket", "basket.png", whole)
    pip = whole.copy()
    pip.alpha_composite(art.pip_alone())
    art.imageset("VanTreePip", "pip-basket.png", pip)
    if len(sys.argv) > 1:
        out = pathlib.Path(sys.argv[1])
        out.mkdir(parents=True, exist_ok=True)
        scene = ground.convert("RGBA")
        for i, cloud in enumerate(clouds()):
            scene.alpha_composite(cloud, [(640, 420), (860, 880), (520, 1120)][i])
        scene.alpha_composite(tree)
        w, h = round(pip.width * 0.61), round(pip.height * 0.61)
        cx, cy = 440 + (305 - 310) * 0.61, 668 + (290 - 555) * 0.61
        scene.alpha_composite(pip.resize((w, h), Image.LANCZOS), (round(cx - w / 2), round(cy - h / 2)))
        scene.convert("RGB").save(out / "session-scene.jpg", quality=90)
        whole.save(out / "basket.png")


if __name__ == "__main__":
    main()
