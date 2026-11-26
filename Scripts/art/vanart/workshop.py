"""The workshop: the inside of the van seen straight-on, as the member sees it after entering.

A flat elevation, 1200 by 1500. The boiler's gauge is left blank on purpose: the app draws the timer's face on it.
The same pieces as the home scene, drawn for this angle (the design's "two drawings each").
"""

import math

from .core import *  # noqa: F401,F403
from .outdoor import leaf, leaf_pile
from .pip import cat, pip, tube
from .van import bottle, foliage, jug, lantern, round_poly, vine

W_, H_ = 1200, 1500
FLOOR = "#c58a58"
# Where the app lays the timer's face over the gauge: centre and radius, in this drawing's units.
GAUGE = (905.0, 742.0, 104.0)


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def bricks(s, x0, y0, x1, y1, colour=BRICK, row=26.0, length=62.0):
    s.add(poly(rect(x0, y0, x1, y1)), fill=colour, sw=5)
    y, i = y0 + row, 0
    while y < y1 - 2:
        s.line([(x0, y), (x1, y)], sw=2.5, opacity=0.55)
        y += row
    y, i = y0, 0
    while y < y1 - 2:
        x = x0 + (length / 2 if i % 2 else length)
        while x < x1 - 4:
            s.line([(x, y), (x, min(y + row, y1))], sw=2.5, opacity=0.55)
            x += length
        y += row
        i += 1


def shell(s):
    s.begin("workshop-shell")
    # The van's body round the room, then the room itself with its arched top.
    s.add(round_poly(rect(30, 40, 1170, 1420), 120), fill=CREAM, sw=7)
    s.add(poly(rect(30, 1300, 1170, 1340)), fill=STRIPE, sw=4.5)
    room = (f"M78 1250 L78 250 Q78 96 232 96 L968 96 Q1122 96 1122 250 L1122 1250 Z")
    s.add(room, fill=WOOD, sw=7)
    for x in range(150, 1100, 72):
        top = 96 if 232 < x < 968 else 96 + (154 - math.sqrt(max(0, 154 ** 2 - (154 - min(x - 78, 1122 - x)) ** 2)))
        s.line([(x, top + 6), (x, 1064)], sw=3, opacity=0.4)
    # Light falling from the round window and the lantern.
    s.fill(ellipse(250, 330, 190, 170), WOOD_L, opacity=0.5)
    s.end()

    s.begin("workshop-floor")
    s.add(poly(rect(78, 1064, 1122, 1250)), fill=FLOOR, sw=6)
    for y in (1104, 1150, 1200):
        s.line([(80, y), (1120, y)], sw=3, opacity=0.4)
    r = rng(9)
    for y0, y1 in [(1064, 1104), (1104, 1150), (1150, 1200), (1200, 1250)]:
        for _ in range(4):
            x = r.uniform(110, 1090)
            s.line([(x, y0), (x, y1)], sw=3, opacity=0.4)
    s.add(poly(rect(78, 1040, 1122, 1066)), fill=WOOD_D, sw=4.5)
    s.end()


def round_window(s, cx=250, cy=330, r=108):
    s.begin("workshop-window")
    s.add(ellipse(cx, cy, r + 22, r + 22), fill=CREAM, sw=6)
    s.add(ellipse(cx, cy, r, r), fill=GLASS, sw=5)
    # The maple outside.
    s.fill(smooth([(cx - r + 6, cy + 30), (cx - 40, cy - 10), (cx + 20, cy + 20), (cx + r - 6, cy - 6), (cx + r - 14, cy + 54),
                   (cx, cy + r - 4), (cx - r + 22, cy + 62)]), CANOPY_L, opacity=0.9)
    s.fill(smooth([(cx - 60, cy + 60), (cx - 6, cy + 34), (cx + 60, cy + 56), (cx + 40, cy + 96), (cx - 30, cy + 98)]), CANOPY_D, opacity=0.9)
    for a, b in [((cx - r, cy), (cx + r, cy)), ((cx, cy - r), (cx, cy + r))]:
        s.line([a, b], sw=16, stroke=OUT)
        s.line([a, b], sw=8, stroke=CREAM)
    s.add(ellipse(cx, cy, r, r), fill="none", sw=5)
    s.line([(cx - 64, cy - 62), (cx - 30, cy - 86)], sw=6, stroke=WHITE)
    s.end()


def shelf_and_pegboard(s):
    s.begin("workshop-tasting-shelf")
    # The tasting shelf: one bottle for each special syrup made. Empty places wait as outlines.
    s.add(poly(rect(436, 500, 762, 520)), fill=PLANK, sw=5)
    for x in (462, 736):
        s.add(poly([(x - 12, 520), (x + 12, 520), (x, 558)]), fill=WOOD_DD, sw=4)
    cols = [SYRUP, SYRUP_L, SYRUP_D, LEAF_R]
    for i in range(7):
        x = 470 + i * 43
        if i < 4:
            bottle(s, (x, 500), 1.55, cols[i], tall=(i % 2 == 0))
        else:
            s.add(round_poly(rect(x - 16, 448, x + 16, 500), 7), fill="none", sw=3, opacity=0.4, dash="7 7")
    s.end()

    s.begin("workshop-pegboard")
    s.add(round_poly(rect(120, 560, 420, 800), 10), fill=PLANK, sw=5)
    for x in range(144, 410, 24):
        for y in range(584, 790, 24):
            s.fill(ellipse(x, y, 3, 3), WOOD_DD, opacity=0.6)

    def hang(x, y, length, kind):
        a, b = (x, y), (x, y + length)
        s.fill(ellipse(x, y - 6, 6, 6), IRON)
        if kind == "wrench":
            tube(s, [a, b], 11, METAL, edge=4, smooth_it=False)
            s.add(ellipse(x, y + 8, 17, 19), fill=METAL, sw=4)
            s.fill(poly([(x - 7, y - 14), (x + 7, y - 14), (x + 5, y + 8), (x - 5, y + 8)]), PLANK)
            s.add(ellipse(b[0], b[1], 13, 15), fill=METAL, sw=4)
            s.fill(ellipse(b[0], b[1], 5, 6), PLANK)
        elif kind == "hammer":
            tube(s, [(x, y + 10), b], 11, WOOD_DD, edge=4, smooth_it=False)
            s.add(round_poly([(x - 30, y - 10), (x + 26, y - 14), (x + 28, y + 12), (x - 28, y + 16)], 6), fill=METAL_D, sw=4)
        elif kind == "ladle":
            tube(s, [a, b], 8, METAL, edge=4, smooth_it=False)
            s.add(ellipse(b[0], b[1] + 14, 24, 20), fill=METAL, sw=4)
            s.add(ellipse(b[0], b[1] + 10, 16, 9), fill=METAL_D, sw=3)
        else:
            tube(s, [(x, y + 40), b], 6, METAL, edge=3.5, smooth_it=False)
            s.add(round_poly(rect(x - 11, y, x + 11, y + 48), 7), fill=STRIPE, sw=4)
    hang(170, 600, 130, "wrench")
    hang(234, 600, 150, "ladle")
    hang(300, 600, 120, "driver")
    hang(364, 606, 140, "hammer")
    s.end()


def counter(s):
    s.begin("workshop-counter")
    s.add(poly(rect(110, 880, 440, 1066)), fill=WOOD, sw=6)
    for a, b in [(128, 268), (282, 422)]:
        s.add(round_poly(rect(a, 902, b, 1046), 8), fill=WOOD_L, sw=4.5)
        s.add(round_poly(rect(a + 18, 920, b - 18, 1028), 5), fill="none", sw=3, opacity=0.55)
    for x in (254, 296):
        s.add(ellipse(x, 974, 8, 8), fill=GOLD, sw=3.5)
    s.add(round_poly(rect(96, 856, 454, 884), 6), fill=PLANK, sw=5.5)
    jug(s, (166, 856), 1.7, SYRUP)
    bottle(s, (246, 856), 1.9, SYRUP_L, tall=True)
    s.end()

    s.begin("workshop-logbook")
    # The logbook: History and subjects open from here.
    bx, by = 290, 856
    s.add(round_poly([(bx, by - 96), (bx + 124, by - 104), (bx + 132, by - 8), (bx + 8, by)], 6), fill=STRIPE_D, sw=5)
    s.add(round_poly([(bx + 12, by - 88), (bx + 124, by - 96), (bx + 130, by - 12), (bx + 18, by - 6)], 4), fill=CREAM, sw=3)
    s.add(round_poly([(bx - 6, by - 92), (bx + 118, by - 100), (bx + 126, by - 4), (bx + 2, by + 4)], 6), fill=STRIPE, sw=5)
    s.line([(bx + 14, by - 92), (bx + 22, by + 2)], sw=3.5, opacity=0.6)
    leaf(s, bx + 70, by - 50, 28, 0.1, GOLD, sw=3.5)
    s.line([(bx + 96, by - 100), (bx + 100, by - 124), (bx + 110, by - 100)], sw=4, stroke=GOLD)
    s.end()


def stove(s):
    s.begin("workshop-brick")
    bricks(s, 468, 600, 742, 900, BRICK)
    s.end()
    s.begin("workshop-stove")
    bricks(s, 478, 900, 732, 1066, BRICK_D)
    s.add(round_poly(rect(540, 936, 670, 1046), 10), fill=IRON, sw=5)
    s.add(round_poly(rect(556, 952, 654, 1032), 7), fill=FIRE, sw=4.5)
    fl = [(566, 1030), (572, 990), (588, 1006), (604, 962), (622, 1002), (636, 978), (646, 1030)]
    s.add(poly(fl), fill=FIRE_L, sw=4)
    s.fill(smooth([(592, 1028), (604, 996), (618, 1028)]), GLOW)
    s.add(round_poly(rect(460, 868, 750, 904), 6), fill=IRON, sw=5.5)
    s.end()

    s.begin("workshop-pot")
    # The pot: tapping it cooks a leaf into syrup.
    s.add(round_poly(rect(520, 762, 690, 870), 14), fill=METAL, sw=5.5)
    s.fill(round_poly(rect(526, 770, 560, 862), 8), METAL_D, opacity=0.7)
    s.add(ellipse(605, 764, 90, 22), fill=METAL_L, sw=5)
    s.add(ellipse(605, 765, 76, 15), fill=SYRUP, sw=4)
    s.fill(ellipse(586, 766, 26, 6), SYRUP_L)
    for sx in (-1, 1):
        s.add(ellipse(605 + sx * 100, 800, 15, 11), fill="none", sw=11, stroke=OUT)
        s.add(ellipse(605 + sx * 100, 800, 15, 11), fill="none", sw=4, stroke=METAL)
    s.end()
    s.begin("workshop-steam")
    for dx, k in [(-34, 1.0), (10, 0.8), (46, 0.65)]:
        b = (605 + dx, 738)
        pts = [b, (b[0] - 14 * k, b[1] - 40 * k), (b[0] + 14 * k, b[1] - 80 * k), (b[0] - 8 * k, b[1] - 120 * k)]
        s.add(smooth(pts, close=False), stroke=OUT, sw=17 * k)
        s.add(smooth(pts, close=False), stroke=WHITE, sw=8.5 * k)
    s.end()


def boiler(s):
    gx, gy, gr = GAUGE
    s.begin("workshop-boiler")
    # Firewood and the stand.
    for i, (x, y) in enumerate([(826, 1040), (880, 1040), (934, 1040), (988, 1040), (853, 996), (907, 996), (961, 996)]):
        s.add(ellipse(x, y, 27, 24), fill=PLANK, sw=4.5)
        s.add(ellipse(x, y, 14, 12), fill="none", sw=3)
        s.fill(ellipse(x, y, 4, 4), WOOD_D)
    for x in (786, 1024):
        tube(s, [(x, 1064), (x + (10 if x < 900 else -10), 944)], 14, IRON, edge=4.5, smooth_it=False)
    s.add(round_poly(rect(766, 924, 1044, 952), 8), fill=IRON, sw=5.5)
    # The pipe to the roof, behind the dome.
    tube(s, [(905, 470), (905, 100)], 46, COPPER_D, edge=5.5, smooth_it=False)
    s.line([(893, 460), (893, 110)], sw=6, stroke=COPPER_L)
    for y in (200, 330):
        s.line([(878, y), (932, y)], sw=4)
    # The tank and its dome.
    s.add(round_poly(rect(778, 520, 1032, 928), 20), fill=COPPER, sw=6.5)
    s.fill(round_poly(rect(784, 528, 836, 920), 14), COPPER_D, opacity=0.8)
    s.line([(990, 560), (990, 890)], sw=10, stroke=COPPER_L)
    dome = [(778, 540), (792, 470), (850, 428), (905, 418), (960, 428), (1018, 470), (1032, 540)]
    s.add(smooth(dome, close=False) + " L1032 548 L778 548 Z", fill=COPPER_L, sw=6.5)
    s.curve([(806, 500), (838, 454), (884, 436)], sw=8, stroke=WHITE, opacity=0.7)
    for y in (566, 884):
        s.line([(780, y), (1030, y)], sw=4.5)
        for i in range(9):
            s.fill(ellipse(800 + i * 26.5, y + 14 if y < 700 else y - 14, 4.5, 4.5), COPPER_D)
    # The side pipe and its valve.
    tube(s, [(1030, 640), (1076, 640), (1090, 600), (1090, 100)], 20, COPPER_D, edge=5)
    s.add(ellipse(1090, 500, 26, 26), fill="none", sw=14, stroke=OUT)
    s.add(ellipse(1090, 500, 26, 26), fill="none", sw=6, stroke=STRIPE)
    s.line([(1066, 500), (1114, 500)], sw=4.5)
    s.line([(1090, 476), (1090, 524)], sw=4.5)
    # The tap over the pot.
    tube(s, [(780, 860), (736, 860), (722, 880)], 18, COPPER_D, edge=5)
    s.line([(744, 838), (776, 838)], sw=9, stroke=OUT)
    s.end()

    s.begin("workshop-gauge")
    # The gauge is the Focus button. Its face is blank here; the app writes the time on it.
    s.fill(ellipse(gx, gy, gr + 30, gr + 30), GLOW, opacity=0.28)
    s.add(ellipse(gx, gy, gr + 12, gr + 12), fill=GOLD, sw=7)
    s.add(ellipse(gx, gy, gr - 8, gr - 8), fill=WHITE, sw=5)
    for i in range(12):
        t = math.tau * i / 12
        a = (gx + (gr - 30) * math.sin(t), gy - (gr - 30) * math.cos(t))
        b = (gx + (gr - 16) * math.sin(t), gy - (gr - 16) * math.cos(t))
        s.line([a, b], sw=5 if i % 3 == 0 else 3)
    for t in (0.6, 2.2, 3.9, 5.4):
        s.add(ellipse(gx + (gr + 2) * math.sin(t), gy - (gr + 2) * math.cos(t), 5, 5), fill=GOLD_L, sw=2.5)
    s.end()


def hanging(s):
    s.begin("workshop-hanging")
    for x, drop, seed, k in [(500, 170, 71, 1.5), (660, 120, 75, 1.25)]:
        top, pot = (x, 100), (x, 100 + drop)
        for dx in (-22 * k, 0, 22 * k):
            s.line([top, (pot[0] + dx, pot[1])], sw=3.5)
        s.add(ellipse(x, 102, 6, 6), fill=IRON, sw=3)
        foliage(s, pot[0], pot[1] - 2, 52 * k, seed, n=11, droop=0.5)
        s.add(round_poly([(pot[0] - 30 * k, pot[1] - 6), (pot[0] + 30 * k, pot[1] - 6), (pot[0] + 21 * k, pot[1] + 34 * k), (pot[0] - 21 * k, pot[1] + 34 * k)], 7),
              fill=TERRA, sw=4.5)
        s.line([(pot[0] - 28 * k, pot[1] + 6), (pot[0] + 28 * k, pot[1] + 6)], sw=3.5)
        vine(s, [(pot[0] - 24 * k, pot[1] + 4), (pot[0] - 38 * k, pot[1] + 50), (pot[0] - 28 * k, pot[1] + 96), (pot[0] - 38 * k, pot[1] + 140)], seed + 1, size=15)
        vine(s, [(pot[0] + 24 * k, pot[1] + 4), (pot[0] + 36 * k, pot[1] + 44), (pot[0] + 30 * k, pot[1] + 84)], seed + 2, size=14)
    # A lantern on a hook by the boiler.
    s.line([(770, 100), (770, 152)], sw=4)
    lantern(s, (770, 268), 1.5)
    s.end()


def floor_things(s, with_pip=True):
    s.begin("workshop-rug")
    for i in range(16):
        x = 250 + i * 46
        s.line([(x, 1108), (x, 1094)], sw=3.5)
        s.line([(x, 1236), (x, 1250)], sw=3.5)
    s.add(round_poly(rect(232, 1106, 968, 1238), 8), fill=RUG, sw=5.5)
    s.add(round_poly(rect(252, 1120, 948, 1224), 5), fill="none", sw=5, stroke=GOLD)
    s.add(poly([(330, 1172), (600, 1132), (870, 1172), (600, 1212)]), fill=RUG_D, sw=3.5)
    s.add(poly([(520, 1172), (600, 1150), (680, 1172), (600, 1194)]), fill=GOLD, sw=3)
    s.end()

    s.begin("workshop-leaf-basket")
    # Leaves not yet cooked wait here.
    cx, cy = 150, 1196
    s.add(f"M{cx - 62} {cy - 76} C{cx - 60} {cy - 170} {cx + 60} {cy - 170} {cx + 62} {cy - 76}", stroke=OUT, sw=20)
    s.add(f"M{cx - 62} {cy - 76} C{cx - 60} {cy - 170} {cx + 60} {cy - 170} {cx + 62} {cy - 76}", stroke=GOLD, sw=9)
    s.add(ellipse(cx, cy - 74, 84, 30), fill=LEAF_R, sw=5)
    leaf_pile(s, cx, cy - 90, 56, 151, n=11)
    body = [(cx - 86, cy - 72), (cx - 68, cy + 26), (cx - 30, cy + 44), (cx + 30, cy + 44), (cx + 68, cy + 26), (cx + 86, cy - 72), (cx + 40, cy - 46),
            (cx, cy - 40), (cx - 40, cy - 46)]
    s.add(smooth(body, tension=0.8), fill=GOLD, sw=5.5)
    for i, yy in enumerate([cy - 36, cy - 10, cy + 16]):
        s.curve([(cx - 78 + i * 5, yy - 12), (cx - 30, yy + 6), (cx + 30, yy + 6), (cx + 78 - i * 5, yy - 12)], sw=3.5)
    for i in range(-3, 4):
        s.line([(cx + i * 22, cy - 44 + abs(i) * -3), (cx + i * 19, cy + 38 - abs(i) * 5)], sw=3, opacity=0.6)
    s.end()

    cat(s, 400, 1190, 1.35, name="workshop-cat")
    if with_pip:
        pip(s, 700, 1244, 0.6, ladle=True, name="workshop-pip", flip=True)


def workshop_scene(with_pip=True):
    s = Svg(W_, H_)
    s.begin("workshop-backdrop")
    s.fill(poly(rect(0, 0, W_, H_)), BG)
    s.fill(smooth([(0, 1380), (300, 1360), (900, 1360), (1200, 1380), (1200, 1500), (0, 1500)]), GRASS)
    s.end()
    s.begin("workshop-wheels")
    for x in (250, 950):
        for r, col, sw in [(92, IRON, 6), (56, METAL, 5), (36, METAL_L, 4), (13, METAL_D, 3)]:
            s.add(ellipse(x, 1420, r, r), fill=col, sw=sw)
    s.end()
    shell(s)
    round_window(s)
    shelf_and_pegboard(s)
    hanging(s)
    stove(s)
    boiler(s)
    counter(s)
    floor_things(s, with_pip)
    return s
