"""The van: its shell, doors and wheels, the roof's load, and the workshop inside it.

The van's space: x runs from the rear doors (0) to the nose (L), y from the far wall (0) to the near side (W), z up from
the bottom of the body (0). The near wall and most of the roof over the workshop are cut away.
"""

import math

from .core import *  # noqa: F401,F403
from .outdoor import basket, crate
from .pip import cat, pip, tube

# Lengths along the van are in its first, shorter numbers; `core.P` stretches the slice between the stove and the
# boiler. As drawn, the body is L + STRETCH_ADD long and the workshop LC + STRETCH_ADD.
L, W = 810.0, 340.0     # length and width of the body
LC = 520.0              # where the workshop ends and the cab begins
LONG = LC + STRETCH_ADD  # the workshop's length as drawn
F = 50.0                # the workshop floor
H = 430.0               # the roof
T = 22.0                # how thick the shell is
CEIL = H - T
G = -84.0               # the ground
FLOOR = "#c58a58"
DOOR_IN = "#bd825a"
# Where loose things stand, as (x, y) in the van. The two views share these.
LANTERN = (504.0, 166.0)   # on the right counter, at the back
LOGBOOK = (476.0, 262.0)   # on the right counter, at the front
CARRIER = (50.0, 196.0)    # on the floor


def round_poly(pts, r):
    """A polygon with its corners rounded by r."""
    n = len(pts)
    d = ""
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        l1 = math.hypot(p0[0] - p1[0], p0[1] - p1[1])
        l2 = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        a = lerp(p1, p0, min(0.5, r / l1))
        b = lerp(p1, p2, min(0.5, r / l2))
        d += f"{'M' if i == 0 else ' L'}{f(a[0])} {f(a[1])} Q{f(p1[0])} {f(p1[1])} {f(b[0])} {f(b[1])}"
    return d + " Z"


def side(pts):
    """Points given as (x, z) on the near wall."""
    return [P(x, W, z) for x, z in pts]


def shadow(s):
    s.begin("van-shadow")
    pts = face_z(G, -30, L + 40, 30, W + 50)
    s.fill(round_poly(pts, 60), GRASS_D, opacity=0.9)
    s.end()
    s.begin("bumper-front")
    box(s, L - 8, -8, -20, 26, W + 16, 30, METAL_L, METAL, METAL, sw=4)
    s.end()


def left_door(s):
    s.begin("door-left")
    s.add(poly(face_x(-204, -12, 0, 44, 424)), fill=CREAM_DD, sw=4)
    s.add(round_poly(face_y(0, -204, 0, 44, 424), 14), fill=CREAM, sw=5)
    s.add(round_poly(face_y(0, -190, -14, 58, 410), 10), fill=DOOR_IN, sw=4)
    s.add(round_poly(face_y(0, -166, -40, 246, 388), 12), fill=CREAM, sw=4)
    s.add(round_poly(face_y(0, -154, -52, 258, 376), 8), fill=GLASS, sw=4)
    s.line([P(-140, 0, 290), P(-110, 0, 350)], sw=4, stroke=WHITE)
    s.line([P(-120, 0, 286), P(-100, 0, 326)], sw=3, stroke=WHITE)
    # A panel line and the latch.
    s.line([P(-180, 0, 210), P(-24, 0, 210)], sw=3, opacity=0.6)
    s.add(round_poly(face_y(0, -40, -22, 176, 196), 4), fill=METAL, sw=3)
    for z in (110, 340):
        s.add(poly(face_y(0, -10, 6, z, z + 34)), fill=METAL_D, sw=3)
    s.end()


def workshop_shell(s):
    """The three surfaces the workshop is built on: the far wall, the cab wall and the floor."""
    s.begin("workshop-walls")
    s.add(poly(face_y(0, 0, LC, F, CEIL)), fill=WOOD, sw=5)
    for along in range(40, int(LONG), 40):
        s.line([P(X(along), 0, F), P(X(along), 0, CEIL)], sw=2.5, opacity=0.45)
    s.add(poly(face_x(LC, 0, W, F, CEIL)), fill=WOOD_L, sw=5)
    for y in range(42, int(W), 42):
        s.line([P(LC, y, F), P(LC, y, CEIL)], sw=2.5, opacity=0.4)
    s.add(poly(face_z(F, 0, LC, 0, W)), fill=FLOOR, sw=5)
    for y in range(42, int(W), 42):
        s.line([P(0, y, F), P(LC, y, F)], sw=2.5, opacity=0.4)
    r = rng(5)
    for y in range(0, int(W), 42):
        for _ in range(3):
            x = X(r.uniform(30, LONG - 30))
            s.line([P(x, y, F), P(x, y + 42, F)], sw=2.5, opacity=0.4)
    # Skirting where the walls meet the floor.
    s.add(poly(face_y(0, 0, LC, F, F + 12)), fill=WOOD_D, sw=3)
    s.add(poly(face_x(LC, 0, W, F, F + 12)), fill=WOOD_D, sw=3)
    s.end()


def roof_strip(s):
    """What is left of the roof over the workshop: a strip along the far wall."""
    s.begin("roof-far")
    s.add(poly(face_x(0, -8, 30, CEIL, H)), fill=CREAM_DD, sw=4)
    s.add(round_poly([P(-2, -8, H), P(LC + 20, -8, H), P(LC + 20, 30, H), P(-2, 30, H)], 8), fill=CREAM, sw=5)
    s.end()


def rim(s):
    """The cut edge of the shell round the opening: along the roof, down the cab's corner. One thick cream line."""
    s.begin("van-rim")
    pts = [P(-2, 30, H - 11), P(LC, 30, H - 11), P(LC, W - 11, H - 11), P(LC, W - 11, F - 4)]
    d = (f"M{f(pts[0][0])} {f(pts[0][1])} L{f(P(LC - 46, 30, H - 11)[0])} {f(P(LC - 46, 30, H - 11)[1])} "
         f"Q{f(pts[1][0])} {f(pts[1][1])} {f(P(LC, 76, H - 11)[0])} {f(P(LC, 76, H - 11)[1])} "
         f"L{f(P(LC, W - 60, H - 11)[0])} {f(P(LC, W - 60, H - 11)[1])} "
         f"Q{f(pts[2][0])} {f(pts[2][1])} {f(P(LC, W - 11, H - 70)[0])} {f(P(LC, W - 11, H - 70)[1])} L{f(pts[3][0])} {f(pts[3][1])}")
    s.add(d, stroke=OUT, sw=32, cap="butt")
    s.add(d, stroke=CREAM_D, sw=23, cap="butt")
    s.end()


# Small things that stand on shelves and counters. Each is drawn upright at a point on the page.

def bottle(s, p, k=1.0, colour=SYRUP, label=True, tall=False):
    x, y = p
    w, h = 11 * k, (40 if tall else 30) * k
    s.add(round_poly([(x - w, y - h), (x + w, y - h), (x + w, y), (x - w, y)], 5 * k), fill=colour, sw=3)
    s.fill(round_poly([(x - w + 2.5, y - h + 2), (x + w - 2.5, y - h + 2), (x + w - 2.5, y - h * 0.72), (x - w + 2.5, y - h * 0.72)], 3 * k),
           GLASS, opacity=0.75)
    s.add(poly([(x - 5 * k, y - h - 10 * k), (x + 5 * k, y - h - 10 * k), (x + 5 * k, y - h), (x - 5 * k, y - h)]), fill=GLASS, sw=3)
    s.add(poly([(x - 6 * k, y - h - 16 * k), (x + 6 * k, y - h - 16 * k), (x + 6 * k, y - h - 9 * k), (x - 6 * k, y - h - 9 * k)]), fill=WOOD_DD, sw=3)
    if label:
        s.add(poly([(x - w + 3, y - h * 0.55), (x + w - 3, y - h * 0.55), (x + w - 3, y - h * 0.2), (x - w + 3, y - h * 0.2)]), fill=CREAM, sw=2)
    s.line([(x - w + 4, y - h * 0.9), (x - w + 4, y - h * 0.62)], sw=2, stroke=WHITE)


def jug(s, p, k=1.0, colour=SYRUP):
    x, y = p
    s.add(ellipse(x + 20 * k, y - 50 * k, 9 * k, 11 * k), fill="none", sw=5.5 * k)
    body = [(x - 26 * k, y - 4 * k), (x - 30 * k, y - 26 * k), (x - 14 * k, y - 46 * k), (x + 14 * k, y - 46 * k), (x + 30 * k, y - 26 * k),
            (x + 26 * k, y - 4 * k), (x, y + 2 * k)]
    s.add(smooth(body, tension=0.9), fill=colour, sw=3.5)
    s.fill(smooth([(x - 14 * k, y - 44 * k), (x + 14 * k, y - 44 * k), (x + 22 * k, y - 34 * k), (x - 22 * k, y - 34 * k)]), GLASS, opacity=0.8)
    s.add(poly([(x - 8 * k, y - 60 * k), (x + 8 * k, y - 60 * k), (x + 9 * k, y - 45 * k), (x - 9 * k, y - 45 * k)]), fill=GLASS, sw=3)
    s.add(poly([(x - 7 * k, y - 67 * k), (x + 7 * k, y - 67 * k), (x + 7 * k, y - 59 * k), (x - 7 * k, y - 59 * k)]), fill=WOOD_DD, sw=3)
    s.curve([(x - 20 * k, y - 22 * k), (x - 21 * k, y - 12 * k)], sw=2.5, stroke=WHITE)


def lantern(s, p, k=1.0):
    x, y = p
    s.fill(ellipse(x, y - 34 * k, 46 * k, 46 * k), GLOW, opacity=0.38)
    s.add(ellipse(x, y - 78 * k, 15 * k, 17 * k), fill="none", sw=4.5)
    s.add(round_poly([(x - 20 * k, y - 12 * k), (x + 20 * k, y - 12 * k), (x + 22 * k, y), (x - 22 * k, y)], 4), fill=IRON, sw=3.5)
    s.add(round_poly([(x - 16 * k, y - 54 * k), (x + 16 * k, y - 54 * k), (x + 19 * k, y - 12 * k), (x - 19 * k, y - 12 * k)], 8 * k), fill=GLOW, sw=3.5)
    flame = [(x, y - 44 * k), (x + 8 * k, y - 28 * k), (x, y - 16 * k), (x - 8 * k, y - 28 * k)]
    s.add(smooth(flame, tension=0.9), fill=FIRE, sw=2.5)
    s.fill(smooth([(x, y - 34 * k), (x + 4 * k, y - 26 * k), (x, y - 18 * k), (x - 4 * k, y - 26 * k)]), FIRE_L)
    s.line([(x - 9 * k, y - 52 * k), (x - 11 * k, y - 14 * k)], sw=2.5)
    s.line([(x + 9 * k, y - 52 * k), (x + 11 * k, y - 14 * k)], sw=2.5)
    s.add(smooth([(x - 18 * k, y - 54 * k), (x - 10 * k, y - 66 * k), (x + 10 * k, y - 66 * k), (x + 18 * k, y - 54 * k)], close=True, tension=0.8),
          fill=IRON, sw=3.5)


def foliage(s, cx, cy, r, seed, n=11, droop=0.0):
    """A bushy plant: leaves fanned round a centre."""
    rnd = rng(seed)
    order = sorted(range(n), key=lambda i: rnd.random())
    for i in order:
        a = -math.pi / 2 + (i - (n - 1) / 2) * (math.pi * 1.25 / n) + rnd.uniform(-0.12, 0.12)
        ln = r * rnd.uniform(0.75, 1.1)
        tip = (cx + math.cos(a) * ln, cy + math.sin(a) * ln + abs(math.cos(a)) * ln * droop)
        mid = lerp((cx, cy), tip, 0.5)
        nx, ny = -(tip[1] - cy), (tip[0] - cx)
        nl = math.hypot(nx, ny) or 1
        wd = r * 0.2
        p1 = (mid[0] + nx / nl * wd, mid[1] + ny / nl * wd)
        p2 = (mid[0] - nx / nl * wd, mid[1] - ny / nl * wd)
        col = [PLANT, PLANT_D, PLANT_L][i % 3]
        s.add(f"M{f(cx)} {f(cy)} Q{f(p1[0])} {f(p1[1])} {f(tip[0])} {f(tip[1])} Q{f(p2[0])} {f(p2[1])} {f(cx)} {f(cy)} Z", fill=col, sw=2.8)


def vine(s, pts, seed, size=9.0):
    """A trailing stem with small leaves along it."""
    rnd = rng(seed)
    s.curve(pts, sw=2.8, stroke=PLANT_D)
    for i in range(len(pts) - 1):
        for t in (0.25, 0.75):
            c = lerp(pts[i], pts[i + 1], t)
            sgn = 1 if rnd.random() > 0.5 else -1
            col = PLANT if rnd.random() > 0.4 else PLANT_L
            a = rnd.uniform(-0.6, 0.6)
            x, y = c[0] + sgn * size * 0.8, c[1] + rnd.uniform(-2, 4)
            s.add(ellipse(x, y, size, size * 0.62, a + (0.5 * sgn)), fill=col, sw=2.5)


def hanging_plant(s, x, y, drop, seed, trail=True):
    """A pot hung from the ceiling on three cords, at (x, y) in the van."""
    top = P(x, y, CEIL)
    pot = (top[0], top[1] + drop)
    s.line([top, (pot[0] - 15, pot[1] - 4)], sw=2.5)
    s.line([top, (pot[0] + 15, pot[1] - 4)], sw=2.5)
    s.line([top, (pot[0], pot[1] + 2)], sw=2.5)
    s.add(ellipse(top[0], top[1] + 2, 4, 4), fill=IRON, sw=2)
    foliage(s, pot[0], pot[1] - 2, 34, seed, n=9, droop=0.5)
    s.add(round_poly([(pot[0] - 19, pot[1] - 4), (pot[0] + 19, pot[1] - 4), (pot[0] + 13, pot[1] + 22), (pot[0] - 13, pot[1] + 22)], 5), fill=TERRA, sw=3.5)
    s.line([(pot[0] - 18, pot[1] + 3), (pot[0] + 18, pot[1] + 3)], sw=2.5)
    if trail:
        vine(s, [(pot[0] - 16, pot[1] + 2), (pot[0] - 24, pot[1] + 30), (pot[0] - 18, pot[1] + 58), (pot[0] - 24, pot[1] + 84)], seed + 1)
        vine(s, [(pot[0] + 16, pot[1] + 2), (pot[0] + 24, pot[1] + 26), (pot[0] + 20, pot[1] + 50)], seed + 2)
    for dx in (-13, 13):
        s.line([(pot[0] + dx, pot[1] + 22), (pot[0] + dx * 0.4, pot[1] + 34)], sw=2.5)
    s.line([(pot[0], pot[1] + 34), (pot[0], pot[1] + 46)], sw=2.5)


def bricks_y(s, y, x0, x1, z0, z1, row=15.0, colour=BRICK):
    s.add(poly(face_y(y, x0, x1, z0, z1)), fill=colour, sw=4)
    z, i = z0 + row, 0
    while z < z1 - 2:
        s.line([P(x0, y, z), P(x1, y, z)], sw=2, opacity=0.55)
        z += row
    z, i = z0, 0
    while z < z1 - 2:
        x = x0 + (18 if i % 2 else 36)
        while x < x1 - 4:
            s.line([P(x, y, z), P(x, y, min(z + row, z1))], sw=2, opacity=0.55)
            x += 36
        z += row
        i += 1


def bricks_x(s, x, y0, y1, z0, z1, row=15.0, colour=BRICK_D):
    s.add(poly(face_x(x, y0, y1, z0, z1)), fill=colour, sw=4)
    z, i = z0 + row, 0
    while z < z1 - 2:
        s.line([P(x, y0, z), P(x, y1, z)], sw=2, opacity=0.55)
        z += row
    z, i = z0, 0
    while z < z1 - 2:
        y = y0 + (18 if i % 2 else 36)
        while y < y1 - 4:
            s.line([P(x, y, z), P(x, y, min(z + row, z1))], sw=2, opacity=0.55)
            y += 36
        z += row
        i += 1


def wall_fittings(s):
    """Fixed to the far wall: the brick behind the stove, the pegboard and its tools, the shelves, the flue."""
    s.begin("brick-backsplash")
    bricks_y(s, 0, 212, 372, F + 118, F + 270)
    s.end()

    s.begin("pegboard")
    s.add(round_poly(face_y(0, 26, 196, F + 132, F + 262), 6), fill=PLANK, sw=4)
    for x in range(40, 190, 14):
        for z in range(int(F) + 144, int(F) + 256, 14):
            c = P(x, 0, z)
            s.fill(ellipse(c[0], c[1], 1.8, 1.8), WOOD_DD, opacity=0.7)
    # Tools hang by their heads.
    def hang(x, top, length, kind):
        a, b = P(x, 2, top), P(x, 2, top - length)
        s.fill(ellipse(a[0], a[1] - 3, 3.5, 3.5), IRON)
        if kind == "wrench":
            tube(s, [a, b], 6, METAL, edge=2.5, smooth_it=False)
            s.add(ellipse(a[0], a[1] + 4, 9, 10), fill=METAL, sw=2.5)
            s.fill(poly([(a[0] - 4, a[1] - 8), (a[0] + 4, a[1] - 8), (a[0] + 3, a[1] + 4), (a[0] - 3, a[1] + 4)]), PLANK)
            s.add(ellipse(b[0], b[1], 7, 8), fill=METAL, sw=2.5)
            s.fill(ellipse(b[0], b[1], 3, 3.5), PLANK)
        elif kind == "hammer":
            tube(s, [(a[0], a[1] + 6), b], 6, WOOD_DD, edge=2.5, smooth_it=False)
            s.add(round_poly([(a[0] - 16, a[1] - 4), (a[0] + 14, a[1] - 10), (a[0] + 16, a[1] + 2), (a[0] - 14, a[1] + 8)], 3), fill=METAL_D, sw=2.5)
        elif kind == "driver":
            tube(s, [(a[0], a[1] + 22), b], 3.5, METAL, edge=2, smooth_it=False)
            s.add(round_poly([(a[0] - 6, a[1]), (a[0] + 6, a[1]), (a[0] + 6, a[1] + 26), (a[0] - 6, a[1] + 26)], 4), fill=STRIPE, sw=2.5)
        else:
            tube(s, [a, b], 5, METAL, edge=2.5, smooth_it=False)
            s.add(ellipse(a[0], a[1] + 2, 8, 9), fill="none", sw=5, stroke=OUT)
            s.add(ellipse(a[0], a[1] + 2, 8, 9), fill="none", sw=2, stroke=METAL)
    hang(52, F + 250, 70, "spanner")
    hang(84, F + 252, 84, "wrench")
    hang(116, F + 250, 66, "driver")
    hang(146, F + 252, 78, "wrench")
    hang(176, F + 246, 60, "hammer")
    s.end()

    s.begin("shelves")
    # The shelf over the bricks carries short bottles, so that they clear the roof's cut edge from the front as well.
    for (x0, x1, z, k, items) in [(18, 214, F + 284, 1.25, [("b", SYRUP), ("j", SYRUP_L), ("b", SYRUP_D), ("b", SYRUP), ("b", SYRUP_L)]),
                                  (226, 352, F + 298, 1.1, [("s", SYRUP_D), ("s", IRON), ("s", SYRUP), ("s", SYRUP_D)])]:
        for bx in (x0 + 22, x1 - 22):
            s.add(poly([P(bx, 0, z), P(bx, 34, z), P(bx, 0, z - 30)]), fill=WOOD_DD, sw=3)
        box(s, x0, 0, z, x1 - x0, 38, 9, PLANK, WOOD_D, WOOD_D, sw=3.5)
        n = len(items)
        for i, (kind, col) in enumerate(items):
            p = P(x0 + 34 + (x1 - x0 - 60) * i / (n - 1), 18, z + 9)
            if kind == "j":
                jug(s, p, 0.8, col)
            else:
                bottle(s, p, k, col, tall=(kind == "b" and i % 2 == 0))
    # A plant trailing off the end of the low shelf.
    p = P(34, 20, F + 293)
    s.add(round_poly([(p[0] - 17, p[1] - 22), (p[0] + 17, p[1] - 22), (p[0] + 12, p[1]), (p[0] - 12, p[1])], 4), fill=TERRA, sw=3)
    foliage(s, p[0], p[1] - 22, 34, 31, n=9, droop=0.6)
    vine(s, [(p[0] - 14, p[1] - 14), (p[0] - 24, p[1] + 22), (p[0] - 18, p[1] + 56), (p[0] - 26, p[1] + 92)], 32, size=10)
    vine(s, [(p[0] + 4, p[1] - 6), (p[0] + 2, p[1] + 30), (p[0] + 8, p[1] + 60)], 33, size=9)
    s.end()


def long_wall(s):
    """What stands along the stretch of wall between the stove and the boiler."""
    s.begin("tasting-shelf")
    a, b, z = X(392), X(522), F + 276
    for along in (404, 510):
        s.add(poly([P(X(along), 0, z), P(X(along), 34, z), P(X(along), 0, z - 30)]), fill=WOOD_DD, sw=3)
    box(s, a, 0, z, b - a, 38, 9, PLANK, WOOD_D, WOOD_D, sw=3.5)
    for i, col in enumerate([SYRUP_L, LEAF_R, SYRUP, GOLD, SYRUP_D]):
        bottle(s, P(X(412 + i * 24), 18, z + 9), 1.15, col, tall=(i % 2 == 1))
    s.end()

    s.begin("framed-leaf")
    x0, x1, z0, z1 = 394, 458, F + 156, F + 236
    c = P(X((x0 + x1) / 2), 0, (z0 + z1) / 2)
    s.add(round_poly([P(X(x0), 0, z0), P(X(x1), 0, z0), P(X(x1), 0, z1), P(X(x0), 0, z1)], 4), fill=WOOD_DD, sw=3.5)
    s.add(poly([P(X(x0 + 7), 0, z0 + 8), P(X(x1 - 7), 0, z0 + 8), P(X(x1 - 7), 0, z1 - 8), P(X(x0 + 7), 0, z1 - 8)]), fill=CREAM, sw=2.5)
    s.add(maple_leaf(c[0], c[1] - 2, 24, -0.25), fill=LEAF_O, sw=2.5)
    s.end()

    s.begin("syrup-barrel")
    p = P(X(462), 44, F)
    w, h = 44, 104
    body = [(p[0] - w, p[1] - h + 8), (p[0] - w - 10, p[1] - h / 2), (p[0] - w, p[1] - 8), (p[0], p[1] + 4), (p[0] + w, p[1] - 8),
            (p[0] + w + 10, p[1] - h / 2), (p[0] + w, p[1] - h + 8), (p[0], p[1] - h)]
    s.add(smooth(body, tension=0.85), fill=WOOD, sw=4.5)
    for dx in (-22, 0, 22):
        s.curve([(p[0] + dx, p[1] - h + 6), (p[0] + dx * 1.25, p[1] - h / 2), (p[0] + dx, p[1])], sw=2.5, opacity=0.55)
    for yy in (p[1] - h + 22, p[1] - 22):
        s.curve([(p[0] - w - 4, yy), (p[0], yy + 9), (p[0] + w + 4, yy)], sw=7, stroke=OUT)
        s.curve([(p[0] - w - 4, yy), (p[0], yy + 9), (p[0] + w + 4, yy)], sw=3, stroke=METAL)
    s.add(ellipse(p[0], p[1] - h + 6, w - 2, 13), fill=PLANK, sw=4)
    tube(s, [(p[0] + 8, p[1] - 44), (p[0] + 30, p[1] - 40), (p[0] + 32, p[1] - 28)], 8, GOLD, edge=3)
    s.end()


def boiler(s):
    cx, cy = 452.0, 60.0
    s.begin("boiler")
    # The stand and the firewood under it.
    base = F
    for (dx, dy) in [(-44, -30), (44, -30), (-44, 36), (44, 36)]:
        a, b = P(cx + dx, cy + dy, base), P(cx + dx * 0.72, cy + dy * 0.72, base + 70)
        tube(s, [a, b], 9, IRON, edge=3, smooth_it=False)
    for i, (dx, dz) in enumerate([(-26, 0), (4, 0), (30, 0), (-10, 22), (18, 22)]):
        c = P(cx + dx, cy + 30, base + 14 + dz)
        s.add(ellipse(c[0], c[1], 15, 13), fill=PLANK, sw=3)
        s.add(ellipse(c[0], c[1], 7, 6), fill="none", sw=2)
    cylinder(s, cx, cy, base + 66, 62, 10, IRON, IRON_D, sw=4)
    # The tank.
    z0, h, r = base + 76, 190, 56
    cylinder(s, cx, cy, z0, r, h, COPPER, COPPER_L, sw=5, shade=COPPER_D, light=COPPER_L)
    for zz in (z0 + 16, z0 + h - 20):
        arc = front_arc(ring3(cx, cy, zz, r, 40))
        s.curve(arc, sw=3.5)
        for i in range(7):
            q = arc[int((len(arc) - 1) * (0.1 + 0.8 * i / 6))]
            s.fill(ellipse(q[0], q[1] + 8, 2.6, 2.6), COPPER_D)
    # The dome.
    top = P(cx, cy, z0 + h)
    rim_arc = front_arc(ring3(cx, cy, z0 + h, r, 40))
    left, right = rim_arc[0], rim_arc[-1]
    rx = (right[0] - left[0]) / 2
    dome = [lerp(left, right, t) for t in (0, 0.11, 0.35, 0.65, 0.89, 1)]
    dome = [(q[0], q[1] - lift) for q, lift in zip(dome, (0, 34, 54, 54, 34, 0))]
    s.add(smooth(dome, close=False) + " " + poly(list(reversed(rim_arc)), close=False).replace("M", "L", 1) + " Z", fill=COPPER_L, sw=5)
    s.curve([(top[0] - rx * 0.62, top[1] - 12), (top[0] - rx * 0.5, top[1] - 32), (top[0] - rx * 0.2, top[1] - 44)], sw=5, stroke=WHITE, opacity=0.7)
    s.curve(rim_arc, sw=3.5)
    # The pipe from the dome, up through the roof to the chimney.
    neck = (top[0], top[1] - 50)
    up = P(cx, 30, CEIL + 6)
    tube(s, [neck, (neck[0], neck[1] - 30), (up[0], up[1] + 24), up], 28, COPPER_D, edge=4)
    s.line([(neck[0] - 7, neck[1] - 10), (up[0] - 7, up[1] + 10)], sw=4, stroke=COPPER_L)
    s.add(ellipse(neck[0], neck[1] + 2, 25, 9), fill=COPPER, sw=4)
    # A side pipe with a valve wheel, into the wall.
    sp = P(cx + 40, cy - 10, z0 + 120)
    tube(s, [sp, (sp[0] + 34, sp[1] - 6), (sp[0] + 44, sp[1] - 40), (sp[0] + 44, sp[1] - 96)], 12, COPPER_D, edge=3)
    v = (sp[0] + 44, sp[1] - 52)
    s.add(ellipse(v[0], v[1], 15, 15), fill="none", sw=9, stroke=OUT)
    s.add(ellipse(v[0], v[1], 15, 15), fill="none", sw=4, stroke=STRIPE)
    s.line([(v[0] - 13, v[1]), (v[0] + 13, v[1])], sw=3)
    s.line([(v[0], v[1] - 13), (v[0], v[1] + 13)], sw=3)
    # The gauge: this is the timer's dial in the workshop.
    g = P(cx - 22, cy + 46, z0 + 96)
    s.add(ellipse(g[0], g[1], 44, 45), fill=GOLD, sw=4.5)
    s.add(ellipse(g[0], g[1], 33, 34), fill=WHITE, sw=3)
    for i in range(8):
        t = math.tau * i / 8
        s.line([(g[0] + 25 * math.cos(t), g[1] + 26 * math.sin(t)), (g[0] + 31 * math.cos(t), g[1] + 32 * math.sin(t))], sw=2.5)
    s.line([g, (g[0] + 15, g[1] - 19)], sw=4, stroke=STRIPE)
    s.fill(ellipse(g[0], g[1], 4, 4), OUT)
    # The tap, toward the pot.
    tp = P(cx - 54, cy + 30, z0 + 30)
    tube(s, [tp, (tp[0] - 34, tp[1] + 2), (tp[0] - 40, tp[1] + 16)], 10, COPPER_D, edge=3)
    s.add(poly([(tp[0] - 22, tp[1] - 18), (tp[0] - 10, tp[1] - 18), (tp[0] - 12, tp[1] - 6), (tp[0] - 20, tp[1] - 6)]), fill=IRON, sw=3)
    s.line([(tp[0] - 30, tp[1] - 19), (tp[0] - 2, tp[1] - 19)], sw=5, stroke=OUT)
    s.end()


def stove(s, steam=True):
    s.begin("stove")
    x0, x1, y0, y1 = 228.0, 346.0, 22.0, 152.0
    bricks_x(s, x0, y0, y1, F, F + 112)
    bricks_y(s, y1, x0, x1, F, F + 112)
    # The fire door.
    s.add(round_poly(face_y(y1, x0 + 22, x1 - 22, F + 16, F + 88), 6), fill=IRON, sw=4)
    s.add(round_poly(face_y(y1, x0 + 32, x1 - 32, F + 25, F + 79), 5), fill=FIRE, sw=3.5)
    c = P((x0 + x1) / 2, y1, F + 28)
    fl = [(c[0] - 26, c[1] + 12), (c[0] - 22, c[1] - 14), (c[0] - 12, c[1] - 4), (c[0] - 4, c[1] - 34), (c[0] + 8, c[1] - 6), (c[0] + 16, c[1] - 24),
          (c[0] + 26, c[1] - 12)]
    s.add(poly(fl, close=True), fill=FIRE_L, sw=3)
    s.fill(smooth([(c[0] - 10, c[1] + 2), (c[0] - 2, c[1] - 16), (c[0] + 8, c[1] - 8)]), GLOW)
    box(s, x0 - 10, y0 - 8, F + 112, x1 - x0 + 20, y1 - y0 + 18, 14, IRON, IRON_D, IRON_D, sw=4.5)
    s.end()

    s.begin("pot")
    cx, cy, z = 288.0, 86.0, F + 126
    cylinder(s, cx, cy, z, 44, 50, METAL, METAL_L, sw=4.5, shade=METAL_D)
    top = P(cx, cy, z + 50)
    mouth = ring3(cx, cy, z + 50, 44, 40)
    rx = (max(q[0] for q in mouth) - min(q[0] for q in mouth)) / 2
    s.add(smooth(ring3(cx, cy, z + 50, 38, 24)), fill=SYRUP, sw=3.5)
    s.fill(ellipse(top[0] - 12, top[1] + 2, 18, 7), SYRUP_L)
    s.fill(ellipse(top[0] + 22, top[1] - 5, 8, 3.5), SYRUP_L)
    for sx in (-1, 1):
        h = (top[0] + sx * (rx + 6), top[1] + 12)
        s.add(ellipse(h[0], h[1], 11, 7), fill="none", sw=8, stroke=OUT)
        s.add(ellipse(h[0], h[1], 11, 7), fill="none", sw=3, stroke=METAL)
    s.end()
    if steam:
        pot_steam(s)


def pot_steam(s):
    top = P(288.0, 86.0, F + 176)
    s.begin("pot-steam")
    for dx, k in [(-16, 1.0), (14, 0.8), (34, 0.6)]:
        b = (top[0] + dx, top[1] - 16)
        pts = [b, (b[0] - 8 * k, b[1] - 22 * k), (b[0] + 8 * k, b[1] - 44 * k), (b[0] - 4 * k, b[1] - 66 * k)]
        s.add(smooth(pts, close=False), stroke=OUT, sw=11 * k)
        s.add(smooth(pts, close=False), stroke=WHITE, sw=5.5 * k)
    s.end()


def left_counter(s):
    s.begin("counter-left")
    x0, x1, y1, h = 16.0, 206.0, 106.0, 104.0
    box(s, x0, 0, F, x1 - x0, y1, h, PLANK, WOOD_D, WOOD, sw=4.5)
    # Two cupboard doors.
    for a, b in [(x0 + 10, (x0 + x1) / 2 - 5), ((x0 + x1) / 2 + 5, x1 - 10)]:
        s.add(round_poly(face_y(y1, a, b, F + 10, F + h - 14), 5), fill=WOOD_L, sw=3.5)
        s.add(round_poly(face_y(y1, a + 10, b - 10, F + 20, F + h - 24), 3), fill="none", sw=2.2, opacity=0.6)
    for kx in ((x0 + x1) / 2 - 16, (x0 + x1) / 2 + 16):
        c = P(kx, y1, F + h / 2)
        s.add(ellipse(c[0], c[1], 4.5, 4.5), fill=GOLD, sw=2.5)
    box(s, x0 - 4, -2, F + h, x1 - x0 + 8, y1 + 8, 9, PLANK, WOOD_DD, WOOD_D, sw=4)
    top = F + h + 9
    for k in (0.3, 0.62):
        s.line([P(x0, y1 * k, top), P(x1, y1 * k, top)], sw=2.2, opacity=0.4)
    bottle(s, P(96, 26, top), 1.25, SYRUP_L)
    bottle(s, P(150, 36, top), 1.35, SYRUP_D, tall=True)
    jug(s, P(52, 62, top), 1.3, SYRUP)
    jug(s, P(112, 84, top), 1.2, SYRUP_L)
    jug(s, P(180, 74, top), 0.9, SYRUP)
    s.end()


def right_counter(s):
    s.begin("round-window")
    for r, col, sw in [(64, CREAM, 4.5), (50, GLASS, 4)]:
        s.add(smooth(wall_circle("x", LC, 214, F + 236, r, 20)), fill=col, sw=sw)
    s.line([P(LC, 214 - 50, F + 236), P(LC, 214 + 50, F + 236)], sw=9, stroke=OUT)
    s.line([P(LC, 214, F + 186), P(LC, 214, F + 286)], sw=9, stroke=OUT)
    s.line([P(LC, 214 - 50, F + 236), P(LC, 214 + 50, F + 236)], sw=4, stroke=CREAM)
    s.line([P(LC, 214, F + 186), P(LC, 214, F + 286)], sw=4, stroke=CREAM)
    s.line([P(LC, 188, F + 266), P(LC, 202, F + 250)], sw=3.5, stroke=WHITE)
    s.end()

    s.begin("counter-right")
    x0, y0, y1, h = 452.0, 146.0, 332.0, 98.0
    # The top's far part, then the face that looks at us.
    s.add(poly(face_x(x0, y0, y1, F, F + h)), fill=WOOD, sw=4.5)
    # A curtain over the open half.
    cur = face_x(x0, y0 + 8, 226, F + 4, F + h - 6)
    s.add(poly(cur), fill=CREAM, sw=3.5)
    for y in range(int(y0) + 22, 226, 15):
        s.line([P(x0, y, F + 6), P(x0, y - 2, F + h - 8)], sw=2.2, opacity=0.55)
    # Drawers.
    for z in (F + 8, F + 52):
        s.add(round_poly(face_x(x0, 236, y1 - 8, z, z + 38), 4), fill=WOOD_L, sw=3.5)
        c = P(x0, 280, z + 19)
        s.add(ellipse(c[0], c[1], 5, 5), fill=GOLD, sw=2.5)
    # Its near end, where the cut through the van's side passes.
    s.add(poly(face_y(y1, x0, LC, F, F + h)), fill=WOOD_D, sw=4.5)
    s.add(round_poly(face_y(y1, x0 + 10, LC - 10, F + 12, F + h - 14), 4), fill="none", sw=2.5, opacity=0.55)
    s.add(poly([P(x0 - 6, y0 - 4, F + h + 9), P(LC, y0 - 4, F + h + 9), P(LC, y1 + 6, F + h + 9), P(x0 - 6, y1 + 6, F + h + 9)]), fill=PLANK, sw=4)
    s.add(poly(face_x(x0 - 6, y0 - 4, y1 + 6, F + h, F + h + 9)), fill=WOOD_DD, sw=3.5)
    s.add(poly(face_y(y1 + 6, x0 - 6, LC, F + h, F + h + 9)), fill=WOOD_DD, sw=3.5)
    top = F + h + 9
    lantern(s, P(LANTERN[0], LANTERN[1], top), 1.15)
    # The logbook: the study record opens from here.
    s.begin("logbook")
    b = P(LOGBOOK[0], LOGBOOK[1], top)
    s.add(round_poly([(b[0] - 27, b[1] - 36), (b[0] + 23, b[1] - 42), (b[0] + 27, b[1] - 4), (b[0] - 23, b[1] + 2)], 4), fill=STRIPE, sw=3.5)
    s.line([(b[0] - 19, b[1] - 34), (b[0] - 15, b[1])], sw=2.5, opacity=0.6)
    s.add(maple_leaf(b[0] + 3, b[1] - 19, 12, 0.1), fill=GOLD, sw=2)
    s.end()
    s.end()


def bottle_carrier(s):
    """A carrier of bottles on the floor by the rear doors, ready to go out."""
    s.begin("bottle-carrier")
    c = P(CARRIER[0], CARRIER[1], F)
    s.add(poly([(c[0] - 34, c[1] - 22), (c[0] + 34, c[1] - 22), (c[0] + 34, c[1]), (c[0] - 34, c[1])]), fill=WOOD_D, sw=3.5)
    bottle(s, (c[0] - 21, c[1] - 12), 0.9, SYRUP_L, label=False)
    bottle(s, (c[0], c[1] - 12), 0.9, SYRUP, label=False, tall=True)
    bottle(s, (c[0] + 21, c[1] - 12), 0.85, SYRUP_D, label=False)
    s.add(round_poly([(c[0] - 38, c[1] - 24), (c[0] + 38, c[1] - 24), (c[0] + 36, c[1] + 4), (c[0] - 36, c[1] + 4)], 4), fill=WOOD, sw=3.5)
    s.line([(c[0] - 30, c[1] - 10), (c[0] + 30, c[1] - 10)], sw=2.2, opacity=0.5)
    s.add(f"M{f(c[0] - 32)} {f(c[1] - 22)} Q{f(c[0])} {f(c[1] - 104)} {f(c[0] + 32)} {f(c[1] - 22)}", sw=4)
    s.end()


def rug(s):
    s.begin("rug")
    x0, x1, y0, y1 = 96.0, 452.0, 164.0, 326.0
    # Fringe at both ends.
    for xe, sgn in ((x0, -1), (x1, 1)):
        for i in range(12):
            y = y0 + 6 + (y1 - y0 - 12) * i / 11
            s.line([P(xe, y, F + 1), P(xe + sgn * 14, y, F + 1)], sw=2.5)
    s.add(poly(face_z(F + 1, x0, x1, y0, y1)), fill=RUG, sw=4.5)
    s.add(poly(face_z(F + 1, x0 + 14, x1 - 14, y0 + 12, y1 - 12)), fill="none", sw=4, stroke=GOLD)
    s.add(poly(face_z(F + 1, x0 + 26, x1 - 26, y0 + 22, y1 - 22)), fill=RUG_D, sw=2.5)
    mx, my = X((x0 + x1 + STRETCH_ADD) / 2), (y0 + y1) / 2
    lo = [P(x0 + 44, my, F + 1), P(mx - 40, y0 + 34, F + 1), P(mx + 40, y0 + 34, F + 1), P(x1 - 44, my, F + 1), P(mx + 40, y1 - 34, F + 1),
          P(mx - 40, y1 - 34, F + 1)]
    s.add(poly(lo), fill=RUG, sw=3.5, stroke=GOLD)
    s.add(poly([P(mx - 46, my, F + 1), P(mx, my - 26, F + 1), P(mx + 46, my, F + 1), P(mx, my + 26, F + 1)]), fill=GOLD, sw=2.5)
    s.add(poly([P(mx - 20, my, F + 1), P(mx, my - 11, F + 1), P(mx + 20, my, F + 1), P(mx, my + 11, F + 1)]), fill=RUG_D, sw=2)
    for xx in (x0 + 34, x1 - 34):
        for yy in (y0 + 28, y1 - 28):
            c = P(xx, yy, F + 1)
            s.add(poly([(c[0] - 9, c[1]), (c[0], c[1] - 5), (c[0] + 9, c[1]), (c[0], c[1] + 5)]), fill=GOLD, sw=1.8)
    s.end()


def workshop(s, with_pip=True, steam=True):
    """Everything inside, from the back to the front."""
    workshop_shell(s)
    roof_strip(s)
    wall_fittings(s)
    long_wall(s)
    boiler(s)
    right_counter(s)
    stove(s, steam)
    left_counter(s)
    s.begin("hanging-plants")
    hanging_plant(s, 236, 70, 84, 71)
    hanging_plant(s, 330, 76, 50, 75, trail=False)
    hanging_plant(s, 500, 132, 74, 79)
    s.end()
    rug(s)
    bottle_carrier(s)
    # Leaves not yet cooked wait in the basket by the doors.
    c = P(116, 246, F)
    s.begin("leaf-basket", transform=f"translate({f(c[0])} {f(c[1] - 22)}) scale(0.58)")
    basket(s, 0, 0, name="leaf-basket-weave")
    s.end()
    c = P(250, 262, F)
    cat(s, c[0], c[1] - 16, 1.12)
    if with_pip:
        pip_at_home(s)


def pip_at_home(s):
    c = P(X(452), 290, F)
    pip(s, c[0], c[1] + 2, 0.52)


def cab_and_sill(s):
    """The solid front of the van and the low wall under the opening: everything nearer than the workshop."""
    rim(s)
    s.begin("van-body")
    s.add(poly(face_z(F, 0, LC, W - T, W)), fill=CREAM_D, sw=4)
    s.add(poly(face_x(0, 0, W, 0, F)), fill=CREAM_D, sw=5)
    s.add(poly(face_x(0, 0, W, 18, 44)), fill=STRIPE_D, sw=3.5)
    # Tail lights.
    for y in (26, W - 50):
        s.add(round_poly(face_x(0, y, y + 26, 6, 44), 5), fill=STRIPE, sw=3.5)
        s.add(round_poly(face_x(0, y + 5, y + 21, 26, 40), 3), fill=GOLD, sw=2)
    # Under the body.
    s.add(poly(face_y(W, 24, L - 24, -26, 0)), fill=IRON_D, sw=4)
    # The near side: the sill under the opening, and the cab.
    body = side([(0, 0), (L + 4, 0), (L + 4, 214), (784, 252), (700, H), (LC, H), (LC, F), (0, F)])
    d = (f"M{f(body[0][0])} {f(body[0][1])} L{f(body[1][0])} {f(body[1][1])} L{f(body[2][0])} {f(body[2][1])} "
         f"Q{f(P(L + 4, W, 244)[0])} {f(P(L + 4, W, 244)[1])} {f(body[3][0])} {f(body[3][1])} "
         f"L{f(P(716, W, 398)[0])} {f(P(716, W, 398)[1])} Q{f(P(702, W, H)[0])} {f(P(702, W, H)[1])} {f(P(676, W, H)[0])} {f(P(676, W, H)[1])} "
         f"L{f(body[5][0])} {f(body[5][1])} L{f(body[6][0])} {f(body[6][1])} L{f(body[7][0])} {f(body[7][1])} Z")
    s.add(d, fill=CREAM, sw=5.5)
    # Stripes: one along the whole side, a broad one on the cab.
    s.add(poly(side([(0, 18), (L + 4, 18), (L + 4, 44), (0, 44)])), fill=STRIPE, sw=3.5)
    s.add(poly(side([(LC + 10, 74), (L + 4, 74), (L + 4, 128), (LC + 10, 128)])), fill=STRIPE, sw=3.5)
    c = P(646, W, 116)
    s.add(maple_leaf(c[0], c[1], 66, -0.42), fill=STRIPE, sw=4)
    s.add(maple_leaf(c[0], c[1], 66, -0.42), fill="none", sw=4)
    # The cab door: its seam, window and handle.
    seam = side([(542, 60), (542, 400), (690, 400), (770, 240), (770, 60)])
    s.add(poly(seam, close=False), sw=3, opacity=0.75)
    s.add(round_poly(side([(556, 252), (752, 252), (694, 388), (556, 388)]), 14), fill=CREAM_D, sw=4.5)
    glass = side([(566, 262), (738, 262), (688, 378), (566, 378)])
    s.add(round_poly(glass, 10), fill=GLASS, sw=4)
    s.fill(round_poly(side([(566, 262), (738, 262), (724, 296), (566, 296)]), 6), GLASS_D, opacity=0.8)
    s.add(round_poly(side([(600, 264), (650, 264), (650, 322), (600, 322)]), 10), fill=IRON, sw=3, opacity=0.55)
    s.line(side([(590, 366), (640, 300)]), sw=5, stroke=WHITE)
    s.line(side([(612, 368), (646, 322)]), sw=3.5, stroke=WHITE)
    s.add(round_poly(side([(556, 204), (592, 204), (592, 218), (556, 218)]), 4), fill=METAL, sw=3)
    # The mirror.
    a = P(764, W, 316)
    s.line([a, (a[0] + 28, a[1] + 6)], sw=5)
    s.add(round_poly([(a[0] + 22, a[1] - 26), (a[0] + 40, a[1] - 20), (a[0] + 40, a[1] + 34), (a[0] + 22, a[1] + 28)], 5), fill=METAL, sw=3.5)
    # The sloping windscreen and the roof of the cab.
    s.add(poly([P(700, -6, H), P(784, -6, 252), P(784, W, 252), P(700, W, H)]), fill=CREAM_D, sw=5)
    s.add(round_poly([P(712, 14, 404), P(776, 14, 268), P(776, W - 18, 268), P(712, W - 18, 404)], 10), fill=GLASS, sw=4)
    s.line([P(730, 60, 366), P(756, 60, 310)], sw=5, stroke=WHITE)
    s.add(round_poly([P(LC, -8, H), P(702, -8, H), P(702, W, H), P(LC, W, H)], 14), fill=CREAM, sw=5.5)
    # Wheel arches, cut into the side.
    for xw in (212, 684):
        arc = [P(xw + 70 * math.cos(t), W, max(-26, -30 + 70 * math.sin(t))) for t in [math.pi * i / 16 for i in range(17)]]
        s.add(poly(arc), fill=IRON_D, sw=4.5)
    # Bumpers.
    box(s, -18, -8, -20, 20, W + 16, 26, METAL_L, METAL, METAL_D, sw=4)
    c = P(L + 4, W, 150)
    s.add(ellipse(c[0] - 3, c[1], 9, 17), fill=GLOW, sw=3.5)
    s.end()


def wheels(s):
    for i, xw in enumerate((212, 684)):
        s.begin(f"wheel-{i + 1}")
        for r, col, sw in [(54, IRON, 5), (33, METAL, 4), (22, METAL_L, 3), (8, METAL_D, 2.5)]:
            s.add(smooth(wall_circle("y", W + 4, xw, -30, r, 20)), fill=col, sw=sw)
        for j in range(5):
            t = math.tau * j / 5 + 0.3
            c = P(xw + 15 * math.cos(t), W + 4, -30 + 15 * math.sin(t))
            s.fill(ellipse(c[0], c[1], 2.6, 2.6), METAL_D)
        s.add(smooth(wall_circle("y", W + 4, xw, -30, 44, 20)), fill="none", sw=2, opacity=0.45)
        s.end()


def right_door(s):
    s.begin("door-right")
    s.add(poly(face_x(0, W - T, W, F, 414)), fill=CREAM_DD, sw=4)
    s.add(poly(face_x(-112, W - 12, W, 40, 414)), fill=CREAM_DD, sw=4)
    s.add(round_poly(face_y(W, -112, 4, 40, 414), 14), fill=CREAM, sw=5)
    s.add(poly(face_y(W, -112, 4, 74, 128)), fill=STRIPE, sw=3.5)
    s.add(round_poly(face_y(W, -96, -14, 236, 388), 12), fill=CREAM_D, sw=4)
    s.add(round_poly(face_y(W, -86, -24, 246, 378), 8), fill=GLASS, sw=4)
    s.fill(round_poly(face_y(W, -86, -24, 246, 284), 5), GLASS_D, opacity=0.8)
    s.line([P(-74, W, 300), P(-50, W, 352)], sw=4.5, stroke=WHITE)
    s.line([P(-60, W, 298), P(-42, W, 334)], sw=3, stroke=WHITE)
    s.add(round_poly(face_y(W, -102, -80, 176, 190), 4), fill=METAL, sw=3)
    s.end()


def rear_closed(s):
    """The rear doors shut. From this side they would hide half the room, so they are cut away low, as the near wall is."""
    s.begin("doors-closed")
    top = F + 62
    s.add(poly(face_x(0, 0, W, F - 6, top)), fill=CREAM, sw=5)
    s.add(poly(face_x(0, 0, W, F + 6, F + 30)), fill=STRIPE, sw=3.5)
    s.line([P(0, W / 2, F - 6), P(0, W / 2, top)], sw=4)
    for y in (W / 2 - 34, W / 2 + 12):
        s.add(round_poly(face_x(0, y, y + 22, F + 40, F + 52), 3), fill=METAL, sw=3)
    # The cut edge along their tops, and the corner post that carries the roof.
    s.add(poly([P(0, 0, top), P(14, 0, top), P(14, W, top), P(0, W, top)]), fill=CREAM_D, sw=4)
    s.add(poly(face_x(0, -8, 14, F, H)), fill=CREAM_DD, sw=4.5)
    s.end()


def roof_load(s, smoke=True):
    """On the roof: the chimney and its smoke, a rack of crates, a blanket, pots of plants and a pennant."""
    s.begin("chimney")
    a, b = P(452, 30, H), P(452, 30, H + 112)
    tube(s, [a, b], 30, METAL, edge=4, smooth_it=False)
    s.line([(a[0] - 7, a[1] - 8), (b[0] - 7, b[1] + 8)], sw=4, stroke=METAL_L)
    s.add(ellipse(a[0], a[1], 27, 11), fill=METAL_D, sw=4)
    c = P(452, 30, H + 70)
    s.line([(c[0] - 17, c[1]), (c[0] + 17, c[1])], sw=3)
    s.add(poly([(b[0] - 30, b[1] + 4), (b[0] + 30, b[1] + 4), (b[0] + 22, b[1] - 12), (b[0] - 22, b[1] - 12)]), fill=METAL_D, sw=4)
    s.add(poly([(b[0] - 36, b[1] - 12), (b[0] + 36, b[1] - 12), (b[0], b[1] - 54)]), fill=METAL, sw=4.5)
    s.end()

    if smoke:
        chimney_smoke(s)

    s.begin("roof-rack")
    x0, x1, y0, y1, z = 528.0, 704.0, 0.0, 304.0, H + 9
    box(s, x0, y0, z, x1 - x0, y1 - y0, 7, METAL_L, METAL, METAL, sw=4)
    for (px, py) in [(x0 + 5, y1 - 5), (x1 - 5, y1 - 5), (x0 + 5, y0 + 5), (x0 + 5, (y0 + y1) / 2)]:
        tube(s, [P(px, py, z + 7), P(px, py, z + 34)], 5, METAL, edge=2.5, smooth_it=False)
    tube(s, [P(x0 + 5, y0 + 5, z + 34), P(x0 + 5, y1 - 5, z + 34), P(x1 - 5, y1 - 5, z + 34)], 5, METAL, edge=2.5, smooth_it=False)
    s.end()
    top = z + 7

    s.begin("pennant")
    a, b = P(690, 18, top), P(690, 18, top + 190)
    tube(s, [a, b], 5, WOOD_DD, edge=2.5, smooth_it=False)
    fl = [(b[0] + 3, b[1] + 4), (b[0] + 60, b[1] + 10), (b[0] + 108, b[1] + 30), (b[0] + 58, b[1] + 44), (b[0] + 3, b[1] + 56)]
    s.add(smooth(fl, tension=0.7), fill=STRIPE, sw=4.5)
    s.add(ellipse(b[0], b[1] - 3, 6, 6), fill=GOLD, sw=2.5)
    s.end()

    crate(s, 544, 12, top, 104, 100, 74, "roof-crate-1", 0, leaves=False)
    s.begin("roof-cloth")
    ct = top + 74
    s.add(poly([P(550, 18, ct + 4), P(642, 18, ct + 4), P(642, 106, ct + 4), P(550, 106, ct + 4)]), fill=GOLD, sw=4)
    for i in range(1, 6):
        yy = 18 + i * 15
        s.line([P(552, yy, ct + 4), P(640, yy, ct + 4)], sw=2, opacity=0.5)
    s.add(poly([P(544, 112, ct + 2), P(600, 112, ct + 2), P(600, 112, ct - 26), P(544, 112, ct - 26)]), fill=GOLD_L, sw=3.5)
    for i in range(8):
        px = 548 + i * 7
        s.line([P(px, 112, ct - 26), P(px, 112, ct - 38)], sw=2.5)
    s.end()

    crate(s, 556, 124, top, 108, 104, 58, "roof-crate-2", 0, leaves=False)
    s.begin("roof-blanket")
    bt = top + 58
    roll = [P(566, 196, bt + 12), P(656, 196, bt + 12)]
    tube(s, roll, 26, PLANT, edge=4, smooth_it=False)
    s.add(ellipse(roll[0][0], roll[0][1], 9, 14), fill=PLANT_L, sw=3)
    flat = [P(556, 124, bt + 3), P(664, 124, bt + 3), P(664, 184, bt + 3), P(556, 184, bt + 3)]
    hang = [P(556, 130, bt + 3), P(556, 184, bt + 3), P(552, 190, bt - 46), P(552, 126, bt - 40)]
    for shape in (flat, hang):
        s.add(poly(shape), fill=STRIPE, sw=4.5)
    for k in (0.28, 0.6):
        s.line([lerp(flat[0], flat[3], k), lerp(flat[1], flat[2], k)], sw=6, stroke=GOLD)
        s.line([lerp(hang[0], hang[1], k), lerp(hang[3], hang[2], k)], sw=6, stroke=GOLD)
    for k in (0.2, 0.45, 0.7, 0.92):
        s.line([lerp(flat[0], flat[1], k), lerp(flat[3], flat[2], k)], sw=6, stroke=GOLD)
    s.line([lerp(hang[0], hang[3], 0.5), lerp(hang[1], hang[2], 0.5)], sw=6, stroke=GOLD)
    for shape in (flat, hang):
        s.add(poly(shape), sw=4.5)
    s.end()

    s.begin("roof-plants")
    for (px, py, k, seed) in [(672, 250, 1.1, 91), (592, 268, 0.9, 95)]:
        p = P(px, py, top)
        foliage(s, p[0], p[1] - 36 * k, 54 * k, seed, n=11, droop=0.3)
        s.add(round_poly([(p[0] - 25 * k, p[1] - 36 * k), (p[0] + 25 * k, p[1] - 36 * k), (p[0] + 18 * k, p[1]), (p[0] - 18 * k, p[1])], 5),
              fill=TERRA, sw=4)
        s.add(round_poly([(p[0] - 28 * k, p[1] - 42 * k), (p[0] + 28 * k, p[1] - 42 * k), (p[0] + 27 * k, p[1] - 29 * k), (p[0] - 27 * k, p[1] - 29 * k)], 4),
              fill=TERRA_D, sw=3.5)
        foliage(s, p[0], p[1] - 42 * k, 44 * k, seed + 3, n=7, droop=0.2)
        vine(s, [(p[0] + 16 * k, p[1] - 30 * k), (p[0] + 32 * k, p[1] + 12), (p[0] + 26 * k, p[1] + 54), (p[0] + 36 * k, p[1] + 100),
                 (p[0] + 30 * k, p[1] + 140)], seed + 5, size=11)
        vine(s, [(p[0] - 4 * k, p[1] - 24 * k), (p[0] + 4, p[1] + 26), (p[0] + 10, p[1] + 70)], seed + 6, size=10)
    s.end()


def chimney_smoke(s):
    b = P(452, 30, H + 112)
    s.begin("chimney-smoke")
    t = (b[0] + 4, b[1] - 66)
    puff = [(t[0] - 10, t[1] + 4), (t[0] - 6, t[1] - 34), (t[0] + 20, t[1] - 62), (t[0] + 14, t[1] - 100), (t[0] + 40, t[1] - 138),
            (t[0] + 84, t[1] - 150), (t[0] + 118, t[1] - 180), (t[0] + 168, t[1] - 172), (t[0] + 186, t[1] - 132), (t[0] + 160, t[1] - 100),
            (t[0] + 118, t[1] - 96), (t[0] + 92, t[1] - 70), (t[0] + 56, t[1] - 62), (t[0] + 40, t[1] - 24), (t[0] + 14, t[1] + 2)]
    s.add(smooth(puff), fill=SMOKE, sw=4.5)
    s.curve([(t[0] + 58, t[1] - 122), (t[0] + 96, t[1] - 128), (t[0] + 120, t[1] - 150)], sw=3.5, stroke=SMOKE_L)
    s.curve([(t[0] + 10, t[1] - 30), (t[0] + 30, t[1] - 52)], sw=3.5, stroke=SMOKE_L)
    s.end()


def chimney_top():
    """Where the bunting ties on."""
    c = P(452, 30, H + 60)
    return (c[0] - 8, c[1])
