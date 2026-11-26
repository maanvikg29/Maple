"""Everything outside the van: the ground, the maple tree, the lights and bunting, and the things on the grass."""

import math

from .core import *  # noqa: F401,F403


def leafy(cx, cy, rx, ry, tips, seed, depth=0.13, rot=0.0):
    """A clump of maple canopy: a blob whose edge is a run of leaf points."""
    r = rng(seed)
    pts = []
    for i in range(tips):
        a = rot + math.tau * i / tips + r.uniform(-0.08, 0.08)
        k = 1 + r.uniform(-0.05, 0.06) + (0.045 if i % 2 == 0 else -0.02)
        pts.append((cx + rx * k * math.cos(a), cy + ry * k * math.sin(a)))
    d = f"M{f(pts[0][0])} {f(pts[0][1])}"
    for i in range(tips):
        a, b = pts[i], pts[(i + 1) % tips]
        mid = lerp(a, b, 0.5 + r.uniform(-0.1, 0.1))
        v = (mid[0] + (cx - mid[0]) * depth, mid[1] + (cy - mid[1]) * depth)
        c1 = lerp(a, v, 0.55)
        c1 = (c1[0] + (c1[0] - cx) * 0.07, c1[1] + (c1[1] - cy) * 0.07)
        c2 = lerp(v, b, 0.45)
        c2 = (c2[0] + (c2[0] - cx) * 0.07, c2[1] + (c2[1] - cy) * 0.07)
        d += f" Q{f(c1[0])} {f(c1[1])} {f(v[0])} {f(v[1])} Q{f(c2[0])} {f(c2[1])} {f(b[0])} {f(b[1])}"
    return d + " Z"


def leaf(s, x, y, size, rot, colour, sw=3.5, vein=True):
    s.add(maple_leaf(x, y, size, rot), fill=colour, sw=sw)
    if vein:
        c, si = math.cos(rot), math.sin(rot)
        tip = (x + si * size * 0.55, y - c * size * 0.55)
        base = (x - si * size * 0.3, y + c * size * 0.3)
        s.line([base, tip], sw=sw * 0.55, opacity=0.55)
        for side in (-1, 1):
            s.line([lerp(base, tip, 0.25), (x + (side * c * 0.42 + si * 0.2) * size, y + (side * si * 0.42 - c * 0.2) * size)],
                   sw=sw * 0.5, opacity=0.5)


def small_leaf(s, x, y, size, rot, colour):
    """A plain pointed leaf, for the ones drifting far off."""
    c, si = math.cos(rot), math.sin(rot)

    def at(u, v):
        return (x + (u * c - v * si) * size, y + (u * si + v * c) * size)
    s.add(f"M{f(at(0, -1)[0])} {f(at(0, -1)[1])} Q{f(at(0.75, -0.2)[0])} {f(at(0.75, -0.2)[1])} {f(at(0, 1)[0])} {f(at(0, 1)[1])} "
          f"Q{f(at(-0.75, -0.2)[0])} {f(at(-0.75, -0.2)[1])} {f(at(0, -1)[0])} {f(at(0, -1)[1])} Z", fill=colour, sw=3.5)
    s.line([at(0, -0.6), at(0, 1.35)], sw=2.2)


def ground(s):
    s.begin("ground")
    island = [(28, 1480), (120, 1370), (330, 1290), (640, 1250), (980, 1190), (1320, 1120), (1540, 1150), (1596, 1330),
              (1540, 1540), (1400, 1670), (1180, 1790), (960, 1860), (760, 1885), (520, 1850), (300, 1780), (120, 1680),
              (40, 1580)]
    under = [(x, y + 26) for x, y in island]
    s.add(smooth(under), fill=GRASS_D, sw=5)
    s.add(smooth(island), fill=GRASS, sw=5)
    # Lighter patches and tufts.
    for cx, cy, rx, ry in [(250, 1650, 120, 40), (1320, 1560, 150, 46), (700, 1800, 170, 34), (1430, 1330, 90, 30)]:
        s.fill(ellipse(cx, cy, rx, ry), GRASS_L, opacity=0.55)
    r = rng(7)
    for x, y in [(90, 1560), (170, 1470), (420, 1790), (980, 1800), (1130, 1740), (1470, 1500), (1500, 1380),
                 (1360, 1660), (640, 1840), (60, 1500), (1250, 1250), (1540, 1450), (860, 1850), (230, 1730)]:
        k = r.uniform(0.8, 1.2)
        s.line([(x - 9 * k, y), (x - 12 * k, y - 15 * k)], sw=3)
        s.line([(x, y), (x + 1 * k, y - 20 * k)], sw=3)
        s.line([(x + 9 * k, y), (x + 13 * k, y - 13 * k)], sw=3)
    s.end()


def trunk(s):
    s.begin("tree-trunk")
    # Branches first, as thick strokes with an outline.
    branches = [
        ([(300, 760), (230, 640), (150, 560), (60, 470), (-20, 420)], 86),
        ([(360, 780), (430, 640), (520, 500), (600, 380), (660, 250), (700, 120)], 96),
        ([(520, 500), (470, 400), (440, 300), (430, 200)], 58),
        ([(600, 380), (700, 330), (800, 300), (900, 250)], 50),
        ([(190, 600), (190, 500), (220, 400), (260, 300)], 48),
    ]
    for pts, w in branches:
        s.add(smooth(pts, close=False), stroke=OUT, sw=w + 10)
    for pts, w in branches:
        s.add(smooth(pts, close=False), stroke=TRUNK, sw=w)
    body = [(150, 1392), (205, 1330), (232, 1180), (236, 1000), (225, 860), (205, 760), (300, 700), (420, 760),
            (430, 900), (428, 1060), (440, 1220), (470, 1330), (520, 1392), (330, 1420)]
    s.add(smooth(body), fill=TRUNK, sw=5)
    # Cover the joins between trunk and branches.
    s.fill(smooth([(215, 800), (250, 700), (330, 690), (415, 790), (400, 860), (240, 860)]), TRUNK)
    # The shaded side and the bark.
    s.fill(smooth([(160, 1388), (210, 1330), (236, 1180), (240, 1000), (230, 860), (270, 880), (285, 1060), (280, 1250),
                   (250, 1360), (220, 1400)]), TRUNK_D, opacity=0.75)
    s.fill(smooth([(385, 820), (412, 900), (408, 1060), (420, 1220), (400, 1230), (385, 1060)]), TRUNK_L, opacity=0.6)
    for pts in [[(300, 920), (310, 1000), (302, 1090)], [(350, 1130), (345, 1200), (356, 1280)],
                [(262, 1150), (270, 1220), (262, 1300)], [(370, 900), (366, 960)], [(330, 780), (322, 850)],
                [(300, 1290), (312, 1350)], [(470, 560), (500, 510)], [(260, 620), (230, 590)]]:
        s.curve(pts, sw=3.5, opacity=0.8)
    s.add(smooth([(315, 1180), (328, 1168), (338, 1182), (330, 1200), (318, 1196)]), fill=TRUNK_D, sw=3)
    # Roots.
    s.curve([(150, 1392), (110, 1400), (70, 1418)], sw=5)
    s.add(smooth([(150, 1392), (100, 1396), (56, 1416), (60, 1428), (120, 1420), (180, 1416)]), fill=TRUNK, sw=5)
    s.end()


def canopy(s):
    s.begin("tree-canopy")
    clumps = [
        # (cx, cy, rx, ry, tips, colour, seed)
        (70, 540, 200, 120, 21, CANOPY_D, 3),
        (540, 440, 270, 120, 25, CANOPY_D, 5),
        (860, 270, 210, 120, 21, CANOPY_D, 8),
        (250, 350, 320, 170, 29, CANOPY, 11),
        (720, 180, 320, 170, 29, CANOPY, 13),
        (40, 270, 230, 200, 25, CANOPY, 17),
        (180, 100, 320, 180, 29, CANOPY_L, 19),
        (570, 30, 350, 160, 29, CANOPY_L, 23),
        (940, 20, 200, 140, 21, CANOPY_L, 29),
    ]
    for cx, cy, rx, ry, tips, colour, seed in clumps:
        s.add(leafy(cx, cy, rx, ry, tips, seed), fill=colour, sw=5)
    # Leaf-edge marks inside the clumps, so the mass reads as leaves.
    r = rng(41)
    for cx, cy, rx, ry, tips, colour, seed in clumps[3:]:
        for _ in range(3):
            a = r.uniform(0, math.tau)
            x, y = cx + rx * 0.55 * math.cos(a), cy + ry * 0.5 * math.sin(a)
            w = r.uniform(26, 44)
            s.curve([(x - w, y - 4), (x - w * 0.5, y + 12), (x, y - 2)], sw=3.5, opacity=0.4)
            s.curve([(x, y - 2), (x + w * 0.5, y + 12), (x + w, y - 6)], sw=3.5, opacity=0.4)
    # Whole leaves sitting on the canopy.
    for x, y, size, rot, colour in [(160, 220, 46, -0.5, LEAF_Y), (330, 300, 50, 0.35, LEAF_R), (560, 130, 44, 0.25, LEAF_R),
                                    (80, 420, 34, 0.9, LEAF_Y), (770, 320, 36, -0.3, LEAF_O), (320, 40, 34, 0.2, LEAF_Y),
                                    (640, 300, 30, 0.8, LEAF_Y), (880, 120, 34, -0.6, LEAF_R), (440, 450, 30, -0.9, LEAF_R)]:
        leaf(s, x, y, size, rot, colour)
    s.end()


def string_lights(s):
    s.begin("string-lights")
    rope = [(214, 772), (260, 800), (330, 812), (400, 800), (436, 776)]
    s.curve(rope, sw=4)
    for (x, y) in [(232, 786), (286, 808), (344, 812), (398, 802)]:
        s.fill(ellipse(x, y + 20, 26, 26), GLOW, opacity=0.35)
        s.add(poly([(x - 6, y), (x + 6, y), (x + 5, y + 9), (x - 5, y + 9)]), fill=IRON, sw=2.5)
        s.add(ellipse(x, y + 22, 13, 15), fill=GLOW, sw=3.5)
        s.line([(x - 5, y + 16), (x - 2, y + 12)], sw=2, stroke=WHITE)
    # The line carries on to the van's roof.
    tail = [(436, 776), (520, 830), (610, 842), (700, 806)]
    s.curve(tail, sw=4)
    for (x, y) in [(486, 812), (566, 840), (650, 832)]:
        s.fill(ellipse(x, y + 20, 24, 24), GLOW, opacity=0.35)
        s.add(poly([(x - 6, y), (x + 6, y), (x + 5, y + 9), (x - 5, y + 9)]), fill=IRON, sw=2.5)
        s.add(ellipse(x, y + 22, 12, 14), fill=GLOW, sw=3.5)
    s.end()


def bunting(s, to=(838, 590)):
    s.begin("bunting")
    a, b = (452, 600), to
    pts = []
    n = 7
    for i in range(n + 1):
        t = i / n
        x = a[0] + (b[0] - a[0]) * t
        y = a[1] + (b[1] - a[1]) * t + math.sin(math.pi * t) * 62
        pts.append((x, y))
    colours = [STRIPE, GOLD, LEAF_O, GOLD_L, STRIPE, GOLD, LEAF_O]
    for i in range(n):
        p, q = lerp(pts[i], pts[i + 1], 0.08), lerp(pts[i], pts[i + 1], 0.92)
        mid = lerp(p, q, 0.5)
        s.add(poly([p, q, (mid[0] + 2, mid[1] + 62)]), fill=colours[i], sw=4)
    s.curve(pts, sw=4.5)
    s.end()


def drifting_leaves(s):
    s.begin("drifting-leaves")
    leaf(s, 110, 870, 34, -0.5, LEAF_Y)
    leaf(s, 1340, 420, 40, 0.5, LEAF_Y)
    leaf(s, 1450, 1395, 28, 0.6, LEAF_R)
    small_leaf(s, 1165, 270, 30, -0.9, LEAF_Y)
    small_leaf(s, 1470, 720, 28, 0.7, LEAF_O)
    small_leaf(s, 372, 1640, 20, 0.5, LEAF_R)
    small_leaf(s, 312, 1672, 14, 1.3, LEAF_O)
    leaf(s, 1260, 1930, 24, -0.4, LEAF_O, sw=3)
    s.end()


def leaf_pile(s, cx, cy, w, seed, n=9):
    """Leaves heaped in a container, drawn above its rim."""
    r = rng(seed)
    cols = [LEAF_R, LEAF_O, LEAF_Y, LEAF_O, LEAF_R]
    for i in range(n):
        x = cx + r.uniform(-w, w)
        y = cy + r.uniform(-12, 10) - (1 - abs(x - cx) / w) * 16
        leaf(s, x, y, r.uniform(20, 28), r.uniform(-1.2, 1.2), cols[i % len(cols)], sw=3, vein=False)


def crate(s, x, y, z, dx, dy, dz, name, seed, leaves=True):
    """A slatted wooden crate standing on the grass."""
    s.begin(name)
    box(s, x, y, z, dx, dy, dz, WOOD_DD, PLANK_D, PLANK, sw=4.5)
    # Slats on the two faces we see.
    for k in (0.36, 0.68):
        s.line([P(x, y, z + dz * k), P(x, y + dy, z + dz * k)], sw=3.5)
        s.line([P(x, y + dy, z + dz * k), P(x + dx, y + dy, z + dz * k)], sw=3.5)
    for (px, py) in [(x, y + 10), (x, y + dy - 10)]:
        s.line([P(px, py, z), P(px, py, z + dz)], sw=3)
    for px in (x + 12, x + dx - 12):
        s.line([P(px, y + dy, z), P(px, y + dy, z + dz)], sw=3)
    # A hand slot.
    c = P(x + dx / 2, y + dy, z + dz * 0.52)
    s.add(poly([(c[0] - 20, c[1] + 6), (c[0] + 16, c[1] - 12), (c[0] + 20, c[1] - 6), (c[0] - 16, c[1] + 12)]), fill=WOOD_DD, sw=3)
    if leaves:
        top = P(x + dx / 2, y + dy / 2, z + dz)
        s.fill(poly([P(x + 8, y + 8, z + dz), P(x + dx - 8, y + 8, z + dz), P(x + dx - 8, y + dy - 8, z + dz),
                     P(x + 8, y + dy - 8, z + dz)]), LEAF_R)
        leaf_pile(s, top[0], top[1] - 6, dx * 0.62, seed)
        # The front rim again, over the leaves.
        s.line([P(x, y, z + dz), P(x, y + dy, z + dz), P(x + dx, y + dy, z + dz)], sw=4.5)
    s.end()


def basket(s, cx=270, cy=1590, name="leaf-basket-outside"):
    s.begin(name)
    # The handle, behind.
    s.add(f"M{cx - 62} {cy - 64} C{cx - 60} {cy - 150} {cx + 60} {cy - 150} {cx + 62} {cy - 64}", stroke=OUT, sw=17)
    s.add(f"M{cx - 62} {cy - 64} C{cx - 60} {cy - 150} {cx + 60} {cy - 150} {cx + 62} {cy - 64}", stroke=GOLD, sw=8)
    s.add(ellipse(cx, cy - 62, 80, 30), fill=LEAF_R, sw=4.5)
    leaf_pile(s, cx, cy - 76, 54, 51, n=10)
    body = [(cx - 82, cy - 60), (cx - 66, cy + 26), (cx - 30, cy + 46), (cx + 30, cy + 46), (cx + 66, cy + 26), (cx + 82, cy - 60),
            (cx + 40, cy - 36), (cx, cy - 30), (cx - 40, cy - 36)]
    s.add(smooth(body, tension=0.8), fill=GOLD, sw=5)
    # Weave.
    for i, yy in enumerate([cy - 30, cy - 6, cy + 18]):
        s.curve([(cx - 76 + i * 5, yy - 12), (cx - 30, yy + 6), (cx + 30, yy + 6), (cx + 76 - i * 5, yy - 12)], sw=3)
    for i in range(-3, 4):
        x = cx + i * 21
        for j in range(3):
            y0 = cy - 38 + j * 24 + abs(i) * -2.2
            if (i + j) % 2 == 0:
                s.line([(x - 6, y0 + 8), (x + 6, y0 + 8)], sw=3)
                s.line([(x, y0 + 8), (x, y0 + 20)], sw=3)
    s.add(smooth([(cx - 84, cy - 62), (cx - 42, cy - 38), (cx, cy - 32), (cx + 42, cy - 38), (cx + 84, cy - 62)], close=False), sw=7, stroke=OUT)
    s.add(smooth([(cx - 84, cy - 62), (cx - 42, cy - 38), (cx, cy - 32), (cx + 42, cy - 38), (cx + 84, cy - 62)], close=False), sw=3, stroke=GOLD_L)
    s.end()


def logs(s, cx=960, cy=1700):
    s.begin("log-pile")

    def log(x, y, length, r):
        # A log lying along the van's x direction: its round end faces the camera's left.
        ex, ey = x + length, y - length * 0.5
        s.add(poly([(x, y - r), (ex, ey - r), (ex + r * 0.5, ey), (ex, ey + r), (x, y + r)]), fill=TRUNK_L, sw=4.5)
        s.line([(x + 14, y - r * 0.2), (ex - 6, ey - r * 0.2)], sw=2.5, opacity=0.6)
        s.line([(x + 30, y + r * 0.45), (ex - 20, ey + r * 0.45)], sw=2.5, opacity=0.6)
        s.add(ellipse(x, y, r * 0.62, r, 0.0), fill=PLANK, sw=4.5)
        s.add(ellipse(x, y, r * 0.36, r * 0.58), fill="none", sw=2.5)
        s.add(ellipse(x, y, r * 0.12, r * 0.2), fill=WOOD_D, sw=2)
    log(cx + 6, cy - 44, 110, 26)
    log(cx - 30, cy, 120, 28)
    log(cx + 44, cy + 8, 110, 27)
    s.end()


def bench(s):
    s.begin("bench")
    x, y, z = 280, 380, -75
    for (lx, ly) in [(x + 8, y + 6), (x + 172, y + 6)]:
        box(s, lx, ly, z, 14, 50, 38, WOOD_D, WOOD_DD, WOOD_D, sw=4)
    box(s, x, y, z + 38, 194, 62, 14, PLANK, WOOD_D, WOOD, sw=4.5)
    for k in (0.33, 0.66):
        s.line([P(x, y + 62 * k, z + 52), P(x + 194, y + 62 * k, z + 52)], sw=2.5, opacity=0.7)
    s.end()


def doormat(s):
    s.begin("doormat")
    x, y, z = 286, 480, -74
    pts = face_z(z, x, x + 150, y, y + 96)
    s.add(smooth([pts[0], lerp(pts[0], pts[1], 0.5), pts[1], lerp(pts[1], pts[2], 0.5), pts[2], lerp(pts[2], pts[3], 0.5), pts[3],
                  lerp(pts[3], pts[0], 0.5)], tension=0.55), fill=GOLD, sw=4.5)
    inner = face_z(z, x + 14, x + 136, y + 12, y + 84)
    s.add(poly(inner), sw=2.5, opacity=0.7)
    c = P(x + 75, y + 48, z)
    s.add(maple_leaf(c[0], c[1] - 2, 30, 0.9), fill=STRIPE, sw=3)
    s.end()


def mushrooms(s, cx=1236, cy=1452):
    s.begin("mushrooms")

    def one(x, y, k, spots=True):
        s.add(smooth([(x - 9 * k, y - 26 * k), (x - 11 * k, y), (x, y + 5 * k), (x + 11 * k, y), (x + 9 * k, y - 26 * k)]), fill=WHITE, sw=3.5)
        s.add(smooth([(x - 30 * k, y - 28 * k), (x - 22 * k, y - 50 * k), (x, y - 60 * k), (x + 22 * k, y - 50 * k), (x + 30 * k, y - 28 * k),
                      (x, y - 22 * k)], tension=0.9), fill=STRIPE, sw=4)
        if spots:
            for dx, dy, rr in [(-12, -42, 4.5), (6, -48, 5.5), (14, -34, 3.5)]:
                s.fill(ellipse(x + dx * k, y + dy * k, rr * k, rr * k * 0.8), WHITE)
    one(cx, cy, 1.25)
    one(cx + 44, cy + 26, 0.8, spots=False)
    one(cx - 34, cy + 22, 0.7, spots=False)
    s.end()


def firewood_on_grass(s):
    pass
