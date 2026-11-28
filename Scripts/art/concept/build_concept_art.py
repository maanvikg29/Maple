#!/usr/bin/env python3
"""Cuts the app's van pictures out of the concept art, pixel for pixel.

The van, the maple and Pip are the concept pictures themselves: nothing here redraws them. The home picture is the
concept file, copied byte for byte. The maple of the session view is the same picture with the van, the bunting and
the smoke painted out in the sky's colour, its trunk carried on down to a patch of the same grass. Pip is cut along
his own outline; the pail in his paw is drawn here.

For home, where Pip moves about (`PipAct`), he is lifted out of the picture in pieces that are still his own pixels
(his body, his tail, one ear, the ladle), and the patch of van that was behind him is made here: the picture's own
lines carried on (the cabinet, the drawers, the rug's edges and fringe), its flat colours spread, and nothing else.
The few things the picture does not have are drawn here in its colours: his closed eyelids, a rake, a heart, a
music note and a "z".

Needs Pillow and numpy (the vector drawings in `Scripts/art/vanart` need neither):

    python3 -I Scripts/art/concept/build_concept_art.py [preview folder]
"""

import json
import pathlib
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[3]
CONCEPTS = ROOT / "docs/design/concepts/2026-11-26-syrup-workshop"
ASSETS = ROOT / "App/Resources/Assets.xcassets/Van"

PEACH = (254, 221, 195)
GRASS = (162, 162, 98)
GRASS_RIM = (124, 124, 74)
BARK = (143, 84, 52)
LINE = (40, 15, 7)
METAL = (176, 176, 174)
METAL_DARK = (122, 122, 122)

# The session view's canvas, in the concept picture's own pixels (`VanCanvas.tree`).
TREE_W, TREE_H = 1200, 2600
# Where the concept's tree is cut off by the van's roof: its own pixels end here.
TREE_CUT = 1000
# Pip in the tree: his sprite's box on that canvas (`VanTreeMarks.pip`).
PIP_SCALE = 0.61
PIP_FEET = (440, 668)


# ---------- small tools ----------

def label(free):
    """4-connected labels of the True pixels."""
    h, w = free.shape
    lab = np.zeros((h, w), np.int32)
    parent = [0]

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for y in range(h):
        row = free[y]
        for x in range(w):
            if not row[x]:
                continue
            left = lab[y, x - 1] if x and row[x - 1] else 0
            up = lab[y - 1, x] if y and free[y - 1, x] else 0
            if left and up:
                a, b = find(left), find(up)
                if a != b:
                    parent[max(a, b)] = min(a, b)
                lab[y, x] = min(a, b)
            elif left or up:
                lab[y, x] = left or up
            else:
                parent.append(len(parent))
                lab[y, x] = len(parent) - 1
    roots = np.array([find(i) for i in range(len(parent))], np.int32)
    return roots[lab]


def as_image(mask):
    return Image.fromarray((mask * 255).astype(np.uint8))


def grow(mask, r):
    return np.asarray(as_image(mask).filter(ImageFilter.MaxFilter(2 * r + 1))) > 0


def shrink(mask, r):
    return np.asarray(as_image(mask).filter(ImageFilter.MinFilter(2 * r + 1))) > 0


def outside(free):
    """The True pixels that reach the picture's edge."""
    lab = label(free)
    edge = set(lab[0].tolist()) | set(lab[-1].tolist()) | set(lab[:, 0].tolist()) | set(lab[:, -1].tolist())
    edge.discard(0)
    return np.isin(lab, list(edge))


def cut_from(image, box, is_ground):
    """A thing on a plain ground, cut out: everything the ground cannot reach from the box's edge."""
    piece = image.crop(box).convert("RGB")
    a = np.asarray(piece).astype(np.int32)
    solid = ~outside(is_ground(a))
    # Whatever runs off the box is a neighbour (a wheel, a shadow), not the thing itself.
    solid &= ~outside(solid)
    out = piece.convert("RGBA")
    out.putalpha(as_image(solid).filter(ImageFilter.GaussianBlur(0.7)))
    return out


def near(colour, limit):
    def test(a):
        return ((a - np.array(colour)) ** 2).sum(axis=2) < limit * limit
    return test


def is_grass(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (abs(r - g) < 22) & (b < 0.75 * g) & (g > 105)


def curve(points, steps=24):
    """A smooth line through the points (Catmull-Rom)."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(steps):
            t = s / steps
            out.append(tuple(
                0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                       + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * t ** 3) for k in (0, 1)))
    out.append(tuple(points[-1]))
    return out


class Ink:
    """Draws at four times the size and lays the result down smoothly."""

    def __init__(self, size, k=4):
        self.k = k
        self.size = size
        self.layer = Image.new("RGBA", (size[0] * k, size[1] * k), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.layer)

    def pts(self, points):
        return [(x * self.k, y * self.k) for x, y in points]

    def fill(self, points, colour):
        self.d.polygon(self.pts(points), fill=colour + (255,))

    def line(self, points, colour, width):
        w = max(1, round(width * self.k))
        p = self.pts(points)
        self.d.line(p, fill=colour + (255,), width=w, joint="curve")
        for x, y in (p[0], p[-1]):
            self.d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=colour + (255,))

    def ellipse(self, cx, cy, rx, ry, colour, outline=None, width=0):
        k = self.k
        self.d.ellipse([(cx - rx) * k, (cy - ry) * k, (cx + rx) * k, (cy + ry) * k], fill=colour + (255,) if colour else None,
                       outline=outline + (255,) if outline else None, width=round(width * k))

    def onto(self, image, at=(0, 0)):
        small = self.layer.resize(self.size, Image.LANCZOS)
        image.alpha_composite(small, at)


# ---------- the maple, for the session view ----------

def blob(cx, cy, a, b, n=2.6, steps=240):
    import math
    out = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        out.append((cx + a * abs(c) ** (2 / n) * (1 if c >= 0 else -1), cy + b * abs(s) ** (2 / n) * (1 if s >= 0 else -1)))
    return out


def tree_scene(van):
    tree = van.crop((0, 0, TREE_W, TREE_CUT)).copy()
    d = ImageDraw.Draw(tree)
    # Everything that is not the tree, painted out in the sky's colour: the bunting, the wire to the van, the smoke
    # and the chimney. The line runs a few pixels outside the tree's own outline and never crosses it.
    d.polygon([(536, 682), (545, 669), (880, 669), (880, 428), (1012, 428), (1045, 395), (1045, 318), (TREE_W, 318),
               (TREE_W, TREE_CUT), (483, TREE_CUT), (483, 862), (485, 822), (489, 783), (497, 763), (508, 738),
               (524, 704)], fill=PEACH)
    # The one loose leaf the cut would slice.
    d.rectangle([70, 950, 180, TREE_CUT], fill=PEACH)

    scene = Image.new("RGBA", (TREE_W, TREE_H), PEACH + (255,))
    scene.paste(tree, (0, 0))
    # The trunk below the cut is hidden by the van in the concept. Its sides are straight there, so each column of
    # the last clear rows carries straight on down.
    band = np.asarray(tree.crop((228, TREE_CUT - 16, 492, TREE_CUT - 2))).astype(np.float32).mean(axis=0)
    column = Image.fromarray(band.round().astype(np.uint8)[None, :, :])
    scene.paste(column.resize((492 - 228, 1470 - TREE_CUT + 2), Image.NEAREST), (228, TREE_CUT - 2))

    # Where the outline's two dark lines are in that band: the foot's own outline starts on them.
    darkness = 255 - band.mean(axis=1)
    lx = 228 + float(np.average(np.arange(0, 40), weights=np.clip(darkness[:40] - 190, 0, None)))
    rx = 228 + float(np.average(np.arange(224, 264), weights=np.clip(darkness[224:] - 190, 0, None)))

    ink = Ink((TREE_W, TREE_H), k=4)
    ink.fill(blob(600, 1674, 565, 172), GRASS_RIM)
    ink.fill(blob(600, 1640, 565, 172), GRASS)
    # The foot of the trunk, flaring into the grass.
    left = [(lx, 1400)] + curve([(lx, 1440), (lx - 3, 1492), (lx - 20, 1538), (lx - 58, 1566), (lx - 94, 1578)])
    right = [(rx, 1400)] + curve([(rx, 1440), (rx + 3, 1492), (rx + 20, 1538), (rx + 58, 1566), (rx + 94, 1578)])
    foot = curve([(lx - 94, 1578), (lx + 10, 1590), ((lx + rx) / 2, 1594), (rx - 10, 1590), (rx + 94, 1578)])
    ink.fill(left + foot + right[::-1], BARK)
    ink.line(left + foot[1:] + right[::-1][1:], LINE, 3.6)
    ink.onto(scene)

    # Mushrooms and a fallen leaf from the concept's own grass.
    mushrooms = cut_from(van, (1372, 1606, 1502, 1734), is_grass)
    scene.alpha_composite(mushrooms, (700, 1568))
    leaf = cut_from(van, (1632, 1574, 1722, 1660), is_grass)
    scene.alpha_composite(leaf, (250, 1668))
    scene.alpha_composite(leaf.transpose(Image.FLIP_LEFT_RIGHT).rotate(24, resample=Image.BICUBIC, expand=True), (905, 1640))
    return scene.convert("RGB")


# ---------- Pip ----------

PIP_BOX = (190, 135, 800, 715)
# One point inside each closed part of him in his close-up: an ear, the tail, the body, the other ear, and his far
# side and foot.
PIP_PARTS = [(530, 195), (250, 250), (400, 550), (420, 220), (560, 640)]


def pip_mask(src):
    """Pip in his close-up (`pip-from-van.jpg`), as a mask."""
    a = np.asarray(src).astype(np.int32)
    luma = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
    dark = luma < 72
    lab = label(~dark)
    fur = np.zeros(dark.shape, bool)
    for x, y in PIP_PARTS:
        fur |= lab == lab[y, x]
    # His own outline is the dark line hugging those parts; the eyes and the leaf's veins are the holes it leaves.
    mask = fur | (dark & grow(fur, 10))
    mask = mask | ~outside(~mask)
    # Other things' lines touch his outline (the rug's fringe, a drawer): thin stubs, which opening takes off.
    mask = grow(shrink(mask, 4), 4) & mask
    return mask


def pip_cutout():
    src = Image.open(CONCEPTS / "pip-from-van.jpg").convert("RGB")
    out = src.convert("RGBA")
    out.putalpha(as_image(pip_mask(src)).filter(ImageFilter.GaussianBlur(0.8)))
    return out


def pip_with_pail(leaves):
    """Pip as he stands in the concept, the ladle gone, a pail of leaves hanging from the same paw."""
    sprite = pail_alone(leaves)
    sprite.alpha_composite(pip_alone())
    return sprite


def pip_alone():
    """Pip without his pail, in the same square: for the tumble, where the pail flies off on its own."""
    return pip_cutout().crop(PIP_BOX)


def tree_eyelids():
    """His eyes closed, in his close-up's square: each covered in the pale fur round it, with one dark curve. Drawn,
    for blinking in the tree."""
    src = Image.open(CONCEPTS / "pip-from-van.jpg").convert("RGB")
    pixels = np.asarray(src).astype(np.int32)
    x0, y0 = PIP_BOX[0], PIP_BOX[1]
    size = (PIP_BOX[2] - x0, PIP_BOX[3] - y0)
    ink = Ink(size)
    yy, xx = np.mgrid[0:pixels.shape[0], 0:pixels.shape[1]]
    for cx, cy in [(489.5, 316.9), (571.1, 300.8)]:
        # The pale fur in a thin ring just outside the eye, leaving out its dark edge.
        inner = ((xx - cx) / 12) ** 2 + ((yy - cy) / 15) ** 2
        outer = ((xx - cx) / 15) ** 2 + ((yy - cy) / 18) ** 2
        ring = pixels[(inner > 1) & (outer <= 1)]
        ring = ring[(ring[:, 0] * 299 + ring[:, 1] * 587 + ring[:, 2] * 114) // 1000 > 150]
        fur = tuple(int(v) for v in np.median(ring, axis=0))
        ink.ellipse(cx - x0, cy - y0, 12.5, 15.5, fur)
        lid = curve([(cx - 10.5, cy + 1), (cx, cy + 8), (cx + 10.5, cy + 1)])
        ink.line([(x - x0, y - y0) for x, y in lid], LINE, 4.6)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    ink.onto(out)
    return out


# The pail's middle and its mouth's middle, upright, in Pip's square (`PailPose` turns it about the first).
PAIL_MIDDLE = (494, 476)
PAIL_MOUTH = (494, 397)


def pail_alone(leaves):
    """The pail of leaves he holds, drawn by Maple (the leaves are the concept's), in Pip's square."""
    x0, y0 = PIP_BOX[0], PIP_BOX[1]
    size = (PIP_BOX[2] - x0, PIP_BOX[3] - y0)
    sprite = Image.new("RGBA", size, (0, 0, 0, 0))
    at = lambda pts: [(x - x0, y - y0) for x, y in pts]  # noqa: E731
    grip, cx, rim, bottom, half = (636, 430), 684, 532, 690, 80

    back = Ink(size)
    for end in (cx - half + 4, cx + half - 4):
        bend = 10 if end > cx else -6
        handle = curve([(end, rim), ((end + grip[0]) / 2 + bend, (rim + grip[1]) / 2 + 4), grip])
        back.line(at(handle), LINE, 13)
        back.line(at(handle), METAL, 5.5)
    back.ellipse(cx - x0, rim - y0, half, 21, METAL_DARK, LINE, 5)
    back.onto(sprite)
    # The heap: the concept's own leaves.
    for leaf, (lx, ly), turn, k in [(leaves[1], (620, 468), 30, 0.8), (leaves[0], (676, 446), -24, 0.86),
                                    (leaves[2], (634, 476), 4, 0.95), (leaves[0], (700, 472), -52, 0.7)]:
        small = leaf.resize((round(leaf.width * k), round(leaf.height * k)), Image.LANCZOS)
        sprite.alpha_composite(small.rotate(turn, resample=Image.BICUBIC, expand=True), (lx - x0, ly - y0))
    front = Ink(size)
    foot = half - 22
    side = [(cx - half, rim), (cx - foot, bottom - 8)] + curve([(cx - foot, bottom - 8), (cx, bottom + 4), (cx + foot, bottom - 8)]) + [(cx + half, rim)]
    lip = curve([(cx - half, rim), (cx - 40, rim + 17), (cx, rim + 21), (cx + 40, rim + 17), (cx + half, rim)])
    front.fill(at(side + lip[::-1]), METAL)
    front.line(at(side), LINE, 5)
    front.line(at(lip), LINE, 5)
    front.line(at(curve([(cx - 68, rim + 58), (cx, rim + 76), (cx + 68, rim + 58)])), METAL_DARK, 3.5)
    front.onto(sprite)
    return sprite


# ---------- Pip at home, in pieces, and the van behind him ----------

# His close-up's place in the home picture: the pieces are all this size, so they lie on one another as they are.
HOME_BOX = (940, 1310, 1380, 1750)
PATCH_BOX = (1020, 1370, 1340, 1700)
BASKET_BOX = (212, 1668, 422, 1876)


def steps_from(mask, limit=24):
    """How many pixels each pixel is from the mask (about: steps alternate between 4 and 8 neighbours)."""
    far = np.full(mask.shape, limit + 1, np.int32)
    far[mask] = 0
    reached = mask.copy()
    for step in range(1, limit + 1):
        if step % 2:
            wider = reached | np.roll(reached, 1, 0) | np.roll(reached, -1, 0) | np.roll(reached, 1, 1) | np.roll(reached, -1, 1)
        else:
            wider = grow(reached, 1)
        far[wider & ~reached] = step
        reached = wider
    return far


def home_masks():
    """Pip's close-up split into its parts, at the close-up's own size: body, tail, ear, ladle."""
    src = Image.open(CONCEPTS / "pip-from-van.jpg").convert("RGB")
    a = np.asarray(src).astype(np.int32)
    luma = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
    dark = luma < 72
    lab = label(~dark)
    pip = pip_mask(src)
    # The fringe of the rug touches his tail: the cut is evened out there.
    pip = np.asarray(as_image(pip).filter(ImageFilter.GaussianBlur(3))) > 127
    metal = np.zeros(dark.shape, bool)
    for x, y in [(648, 400), (700, 530), (690, 505)]:
        metal |= lab == lab[y, x]
    metal = metal | (dark & grow(metal, 9))
    metal = metal | ~outside(~metal)
    metal = (grow(shrink(metal, 2), 2) & metal) & ~pip

    fills = {seed: lab == lab[seed[1], seed[0]] for seed in PIP_PARTS}

    def part(seed, reach):
        """A closed part of him with its own outline, lifted off. Where the rest of him lies over it the picture
        shows none of it: `under` is that hidden stretch, `reach` pixels in, to be painted in the part's own fur so
        no gap opens when it moves. The line the two share stays with the rest of him."""
        fill = fills[seed]
        others = np.zeros(fill.shape, bool)
        for other, region in fills.items():
            if other != seed:
                others |= region
        to_part, to_rest = steps_from(fill, max(24, 2 * reach)), steps_from(others)
        own = fill | (pip & (to_part <= 14) & (to_rest > 11))
        return own, shrink(pip, 6) & (to_part <= 2 * reach) & ~own

    tail, tail_under = part((250, 250), 20)
    ear, ear_under = part((530, 195), 6)
    body = pip & ~tail & ~ear
    return {"body": body, "tail": tail, "tail under": tail_under, "ear": ear, "ear under": ear_under, "ladle": metal,
            "all": pip | metal}


def small(mask):
    """A close-up mask at the picture's own size, soft at its edge."""
    return as_image(mask).resize((HOME_BOX[2] - HOME_BOX[0], HOME_BOX[3] - HOME_BOX[1]), Image.LANCZOS)


def home_piece(van, mask, under=None):
    """A part of Pip in the picture's own pixels. `under` is the stretch of it the picture hides behind the rest of
    him: that is painted in the part's own fur colour, taken from beside it."""
    out = van.crop(HOME_BOX).convert("RGBA")
    alpha = small(mask)
    if under is not None:
        own = np.asarray(alpha) > 200
        hidden = np.asarray(small(under)) > 30
        pixels = np.asarray(out).copy()
        # The fur nearest the hidden stretch, away from the outline.
        beside = shrink(own, 3) & grow(hidden, 9)
        fur = np.median(pixels[beside][:, :3], axis=0)
        pixels[grow(hidden & ~own, 2), :3] = fur
        out = Image.fromarray(pixels)
        alpha = Image.fromarray(np.maximum(np.asarray(alpha), np.asarray(small(under))))
    out.putalpha(alpha)
    return out


def behind_pip(van_image, masks):
    """The home picture with Pip, his ladle and his shadow gone, and what was behind them put back."""
    van = np.asarray(van_image).astype(np.float32)
    height, width = van.shape[:2]
    luma = (van[..., 0] * 299 + van[..., 1] * 587 + van[..., 2] * 114) / 1000
    yy, xx = np.mgrid[0:height, 0:width]
    inside = np.zeros((height, width), bool)
    inside[HOME_BOX[1]:HOME_BOX[3], HOME_BOX[0]:HOME_BOX[2]] = np.asarray(small(masks["all"])) > 40
    hidden = grow(inside, 5)

    # The picture's straight lines there, measured from the parts of them that show.
    cabinet = lambda x: 1407.5 + (1538.4 - 1407.5) / (1290 - 1052) * (x - 1052)   # the cabinet's foot  # noqa: E731
    drawer_top = lambda x: 1429.62 + 0.555 * (x - 1290)  # noqa: E731
    drawer_mid = lambda x: 1461.48 + 0.553 * (x - 1290)  # noqa: E731
    drawer_foot = lambda x: 1501.16 + 0.559 * (x - 1290)  # noqa: E731
    rug_long = lambda x: 2242.26 - 0.578 * x  # noqa: E731
    sill = lambda x: 1652 - 0.54 * (x - 1215)  # noqa: E731
    points = []
    for x in range(962, 1030, 3):
        guess = 1449 + 0.5 * (x - 960)
        found = np.where(luma[int(guess) - 6:int(guess) + 8, x] < 70)[0]
        if len(found) >= 3:
            points.append((x, int(guess) - 6 + found.mean()))
    slope, start = np.polyfit([p[0] for p in points], [p[1] for p in points], 1)
    rug_short = lambda x: slope * x + start  # noqa: E731
    corner_x = (2242.26 - start) / (slope + 0.578)
    corner_y = rug_long(corner_x)

    below_cabinet = yy > cabinet(xx) + 2.5
    in_rug = (yy > rug_short(xx) - 3) & (yy < rug_long(xx) + 4) & (xx < corner_x + 2)
    on_floor = below_cabinet & (yy < sill(xx) - 3) & (xx < 1319) & ~in_rug & ~((xx < 1105) & (yy > rug_long(xx)))
    is_floor = (abs(van[..., 0] - 199) < 12) & (abs(van[..., 1] - 136) < 12) & (abs(van[..., 2] - 94) < 14)
    # His shadow, and anything else of his on the floor: whatever there is not the floor's own colour.
    near_feet = (xx > 1112) & (xx < 1318) & (yy > 1545) & (yy < 1700) & (yy > cabinet(xx) + 7) & (yy < sill(xx) - 6)
    shadow = grow(on_floor & near_feet & ~hidden & ~is_floor & (luma < 175), 6) & on_floor & (yy < sill(xx) - 4)
    # The last tassels beside his tail are half hidden: they are made again with the rest.
    fringe = (yy - rug_short(xx) > -27) & (yy - rug_short(xx) < 4) & (xx >= 1026) & (xx < 1062)
    hole = hidden | shadow | fringe
    seen = ~hole
    out = van.copy()

    def spread(region, known):
        """The region in the colours around it: nearest first, then evened until it meets them without a seam."""
        box = np.argwhere(region)
        (y0, x0), (y1, x1) = box.min(0) - 3, box.max(0) + 4
        sub = out[y0:y1, x0:x1].copy()
        todo = region[y0:y1, x0:x1].copy()
        have = known[y0:y1, x0:x1] & ~todo

        def around(values, weight):
            total = np.zeros_like(values)
            count = np.zeros(weight.shape, np.float32)
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                total += np.roll(np.roll(values, dy, 0), dx, 1)
                count += np.roll(np.roll(weight, dy, 0), dx, 1)
            return total, count

        sub = sub * have[..., None]
        while todo.any():
            total, count = around(sub, have.astype(np.float32))
            ring = todo & (count > 0)
            if not ring.any():
                break
            sub[ring] = total[ring] / count[ring][:, None]
            have |= ring
            todo &= ~ring
        filled = region[y0:y1, x0:x1] & have
        weight = have.astype(np.float32)
        for _ in range(400):
            total, count = around(sub * weight[..., None], weight)
            sub[filled] = total[filled] / np.maximum(count[filled], 1)[:, None]
        out[y0:y1, x0:x1][filled] = sub[filled]

    def carried(region, dx, dy, source):
        """Each pixel of the region is the picture's own pixel a whole number of steps back along (dx, dy)."""
        ys, xs = np.nonzero(region)
        sx, sy = xs.astype(np.float32), ys.astype(np.float32)
        done = np.zeros(len(xs), bool)
        for _ in range(8):
            sx = np.where(done, sx, sx - dx)
            sy = np.where(done, sy, sy - dy)
            ix = np.clip(np.round(sx).astype(int), 0, width - 2)
            iy = np.clip(np.round(sy).astype(int), 0, height - 2)
            done |= source[iy, ix] & source[iy + 1, ix] & source[iy, ix + 1]
        sx, sy = sx[done], sy[done]
        x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
        fx, fy = (sx - x0)[:, None], (sy - y0)[:, None]
        out[ys[done], xs[done]] = (out[y0, x0] * (1 - fx) * (1 - fy) + out[y0, x0 + 1] * fx * (1 - fy)
                                   + out[y0 + 1, x0] * (1 - fx) * fy + out[y0 + 1, x0 + 1] * fx * fy)

    # 1. The cabinet's pale front: each column carries on down in its own colour.
    panel = hole & (xx >= 1053) & (xx < 1198) & (yy < cabinet(xx) + 3)
    colours = {}
    for x in range(1053, 1198):
        if panel[:, x].any():
            top = int(np.argmax(panel[:, x]))
            above = [van[y, x] for y in range(top - 1, top - 22, -1) if seen[y, x] and luma[y, x] > 158][:5]
            if len(above) == 5:
                colours[x] = np.mean(np.array(above), axis=0)
    known_columns = sorted(colours)
    for x in range(1053, 1198):
        if panel[:, x].any():
            out[panel[:, x], x] = [np.interp(x, known_columns, [colours[k][c] for k in known_columns]) for c in range(3)]
    area = (slice(1380, 1500), slice(1040, 1210))
    soft = np.asarray(Image.fromarray(out[area].clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32)
    inner = shrink(panel, 3)[area]
    out[area][inner] = soft[inner]

    # 2. The drawers' darker wood.
    face = hole & (xx >= 1198) & (xx < 1320) & (yy < cabinet(xx) + 3)
    spread(face, seen & (luma > 112) & (van[..., 0] < 200) & (xx >= 1203) & (xx < 1318)
           & (yy < cabinet(xx) - 4) & (yy > drawer_top(xx) + 4))

    # 3. The floor. Up against the sill, only what is not the sill's own dark line.
    floor = hole & below_cabinet & ~in_rug & (yy < sill(xx) + 1) & ~((xx < 1105) & (yy > rug_long(xx) + 4))
    floor &= ~((yy > sill(xx) - 6) & (luma < 110) & ~hidden)
    spread(floor, seen & is_floor & (yy > cabinet(xx) + 6) & (xx > 990) & (xx < 1320) & (yy < 1705))

    # 4. The rug: its plain red, then its two edges carried on along themselves to the corner they must meet at.
    is_red = (abs(van[..., 0] - 174) < 12) & (abs(van[..., 1] - 68) < 12)
    spread(hole & in_rug, seen & is_red & (xx > 1028) & (xx < 1075) & (yy > 1520) & (yy < 1600))
    mitre = lambda x: corner_y + 0.03 * (corner_x - x)  # noqa: E731
    from_short = yy - rug_short(xx)
    tassel_step = 6.4 * 8
    carried(hole & (from_short > -27) & (from_short < 36) & (xx < corner_x - 1) & ((yy < mitre(xx)) | (from_short < 4))
            & (yy < rug_long(xx) + 2), tassel_step, tassel_step * slope, seen & (xx < 1026))
    from_long = rug_long(xx) - yy
    carried(hole & (from_long > -5) & (from_long < 36) & (xx < corner_x + 3) & (yy >= mitre(xx)) & (yy > rug_short(xx) + 2),
            70, -70 * 0.578, seen & (xx > 990) & (xx < 1066))

    # 5. The lines, drawn where he hid them, in the picture's own line colour and width.
    line = (54, 21, 7)
    x0, y0 = PATCH_BOX[0], PATCH_BOX[1]
    ink = Ink((PATCH_BOX[2] - x0, PATCH_BOX[3] - y0))
    at = lambda pts: [(x - x0, y - y0) for x, y in pts]  # noqa: E731
    ink.line(at([(1052, cabinet(1052)), (1320, cabinet(1320))]), line, 4.6)
    ink.line(at([(1199, 1388), (1199, cabinet(1199))]), line, 4.4)
    ink.line(at([(1210.5, drawer_top(1210.5)), (1210.5, drawer_foot(1210.5))]), line, 4.6)
    ink.line(at([(1210.5, drawer_mid(1210.5)), (1240, drawer_mid(1240))]), line, 4.0)
    ink.line(at([(1210.5, drawer_foot(1210.5)), (1290, drawer_foot(1290))]), line, 4.0)
    # The grain of the pale front: the strokes he cut short, a little longer, and three more like them.
    grain = (118, 72, 40)
    for x, top, bottom in [(1081, 1392, 1411), (1117, 1392, 1422), (1156.5, 1396, 1430), (1099, 1410, 1424),
                           (1137, 1424, 1445), (1176, 1430, 1462)]:
        ink.line(at([(x, top), (x + 0.6, bottom)]), grain, 1.5)
    drawn = np.asarray(ink.layer.resize(ink.size, Image.LANCZOS)).astype(np.float32)
    alpha = drawn[..., 3:] / 255
    sub = out[y0:PATCH_BOX[3], x0:PATCH_BOX[2]]
    here = hole[y0:PATCH_BOX[3], x0:PATCH_BOX[2]]
    sub[here] = (sub * (1 - alpha) + drawn[..., :3] * alpha)[here]

    # The second drawer's knob, which the ladle hangs on: the first one's own pixels.
    kx0, ky0, kx1, ky1 = 1244, 1414, 1272, 1442
    ky, kx = np.mgrid[ky0:ky1, kx0:kx1]
    ring = ((kx - 1257.5) ** 2 + (ky - 1428) ** 2) < 11.5 ** 2
    there = (slice(ky0 + 35, ky1 + 35), slice(kx0 + 6, kx1 + 6))
    ring &= hole[there]
    out[there][ring] = van[ky0:ky1, kx0:kx1][ring]

    # Where the wall ends beside him, its own corner is kept; just behind him it is the same dark line.
    corner = (xx > 1084) & (xx < 1105) & (yy > rug_long(xx) + 4) & hole
    out[corner & inside] = line
    # Only what he and his shadow covered is replaced: everything else stays the picture's own pixel.
    replaced = grow(inside, 2) | shadow | (fringe & ~seen)
    replaced &= ~((xx > 1084) & (xx < 1107) & (yy > 1611) & (yy < 1640) & ~inside)
    patch = Image.fromarray(np.where(replaced[..., None], out, van).clip(0, 255).astype(np.uint8)).convert("RGBA")
    patch.putalpha(as_image(replaced).filter(ImageFilter.GaussianBlur(0.6)))
    return patch.crop(PATCH_BOX)


def eyelids(van):
    """His eyes, closed: each covered in the fur's colour beside it, with one dark curve. Drawn."""
    x0, y0 = HOME_BOX[0], HOME_BOX[1]
    size = (HOME_BOX[2] - x0, HOME_BOX[3] - y0)
    ink = Ink(size)
    pixels = np.asarray(van).astype(np.int32)
    for cx, cy in [(1184.5, 1468.2), (1225.4, 1460.3)]:
        # The pale fur around the eye: the lightest pixels in a ring about it.
        ring = [pixels[round(cy + 10 * np.sin(t)), round(cx + 9 * np.cos(t))] for t in np.linspace(0, 2 * np.pi, 24, endpoint=False)]
        ring = [c for c in ring if c.sum() > 430]
        fur = tuple(int(v) for v in np.median(np.array(ring), axis=0))
        ink.ellipse(cx - x0, cy - y0, 6.6, 8.2, fur)
        lid = curve([(cx - 5.6, cy + 0.5), (cx, cy + 4.2), (cx + 5.6, cy + 0.5)])
        ink.line([(x - x0, y - y0) for x, y in lid], LINE, 2.6)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    ink.onto(out)
    return out


def basket_front(van):
    """The leaf basket's front and the leaves heaped at it, for Pip to pop up behind."""
    piece = van.crop(BASKET_BOX).convert("RGBA")
    parts = label(~is_grass(np.asarray(piece.convert("RGB")).astype(np.int32)))
    solid = parts == parts[1800 - BASKET_BOX[1], 316 - BASKET_BOX[0]]
    piece.putalpha(as_image(solid).filter(ImageFilter.GaussianBlur(0.7)))
    yy, xx = np.mgrid[BASKET_BOX[1]:BASKET_BOX[3], BASKET_BOX[0]:BASKET_BOX[2]]
    # Below a curve through the heap, sagging like the basket's own rim.
    line = 1716 + 30 * np.sqrt(np.clip(1 - ((xx - 316) / 100.0) ** 2, 0, 1))
    alpha = np.asarray(piece.getchannel("A")).astype(np.float32) * np.clip(yy - line, 0, 1)
    piece.putalpha(Image.fromarray(alpha.astype(np.uint8)))
    return piece


def props():
    """The things the picture has none of, drawn in its colours, at twice their size in the picture."""
    import math
    out = {}
    # A heart.
    ink = Ink((96, 88))
    shape = []
    for i in range(80):
        t = 2 * math.pi * i / 80
        shape.append((48 + 38 * math.sin(t) ** 3,
                      40 - 2.45 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))))
    ink.fill(shape, (214, 70, 58))
    ink.line(shape + shape[:1], LINE, 6)
    ink.line(curve([(26, 30), (30, 22), (38, 20)]), (244, 150, 130), 4)
    image = Image.new("RGBA", (96, 88), (0, 0, 0, 0))
    ink.onto(image)
    out["VanPipHeart"] = image
    # A music note.
    ink = Ink((80, 104))
    ink.line([(34, 82), (34, 18), (66, 10), (66, 70)], LINE, 7)
    ink.line([(34, 30), (66, 22)], LINE, 9)
    ink.ellipse(24, 84, 14, 10, LINE)
    ink.ellipse(56, 72, 14, 10, LINE)
    image = Image.new("RGBA", (80, 104), (0, 0, 0, 0))
    ink.onto(image)
    out["VanPipNote"] = image
    # A "z".
    ink = Ink((72, 72))
    ink.line([(14, 16), (56, 16), (16, 56), (58, 56)], LINE, 9)
    image = Image.new("RGBA", (72, 72), (0, 0, 0, 0))
    ink.onto(image)
    out["VanPipZed"] = image
    # A rake, held at the top of its handle: a wooden shaft and a fan of bamboo tines.
    w, h = 240, 600
    ink = Ink((w, h), k=2)
    hub = (120, 470)
    ink.line([(120, 14), hub], LINE, 22)
    ink.line([(120, 14), hub], (190, 128, 74), 12)
    tips = [(hub[0] + 104 * math.sin(math.radians(a)), hub[1] + 104 * math.cos(math.radians(a))) for a in range(-48, 49, 16)]
    for tip in tips:
        ink.line([hub, tip], LINE, 13)
    for tip in tips:
        ink.line([hub, tip], (226, 176, 96), 5.5)
    band = [((hub[0] + t[0]) / 2, (hub[1] + t[1]) / 2 + 4) for t in tips]
    ink.line(curve(band, 6), LINE, 12)
    ink.line(curve(band, 6), (226, 176, 96), 4.5)
    ink.ellipse(hub[0], hub[1], 15, 15, (190, 128, 74), LINE, 5.5)
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ink.onto(image)
    out["VanPipRake"] = image
    return out


# ---------- home, alive ----------

# The pieces of the home picture that move (`VanAmbience`), each cut along its own outline and saved with the box
# it was cut from, so it lies exactly where the picture has it. Those that sway over the sky also get a "gap": the
# piece's shape in the sky's own colour there, laid under the moving copy so the picture's still one never shows.
AMBIENT_BOXES = {
    "Smoke": (1004, 334, 1200, 538),
    "Flag": (1167, 512, 1292, 594),
    "Fire": (808, 1366, 888, 1438),
    "Flame": (1132, 1198, 1164, 1236),
    "Cat": (782, 1572, 992, 1700),
    "SkyLeaf0": (1290, 262, 1406, 372),
    "SkyLeaf1": (1490, 420, 1610, 540),
    "SkyLeaf2": (1640, 770, 1740, 880),
    "SkyLeaf3": (40, 925, 200, 1075),
}
PENNANT_SEEDS = [(580, 735), (650, 760), (735, 765), (800, 745), (880, 735)]
BUNTING_BAND = (550, 672, 915, 812)


def outlined(src_box_pixels, seeds, reach=8, dark_below=72):
    """A part of the picture with its own dark outline: the closed regions round the seeds, the outline that hugs
    them, and anything they enclose."""
    a = src_box_pixels.astype(np.int32)
    luma = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
    dark = luma < dark_below
    lab = label(~dark)
    fill = np.zeros(dark.shape, bool)
    for x, y in seeds:
        if not dark[y, x]:
            fill |= lab == lab[y, x]
    mask = fill | (dark & grow(fill, reach))
    return mask | ~outside(~mask)


def sky_colour(van, box, mask):
    """The sky round a piece: the median of the sky-coloured pixels just outside it."""
    pad = 16
    wide = (box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)
    pixels = np.asarray(van.crop(wide)).astype(np.int32)
    placed = np.zeros(pixels.shape[:2], bool)
    placed[pad:pad + mask.shape[0], pad:pad + mask.shape[1]] = mask
    ring = grow(placed, 12) & ~grow(placed, 3)
    sky = near(PEACH, 30)(pixels) & ring
    chosen = pixels[sky] if sky.sum() > 20 else np.array([PEACH])
    return tuple(int(v) for v in np.median(chosen.reshape(-1, 3), axis=0))


def piece_and_gap(van, box, mask, gap=True, soften=0.7):
    crop = van.crop(box)
    piece = crop.convert("RGBA")
    piece.putalpha(as_image(mask).filter(ImageFilter.GaussianBlur(soften)))
    if not gap:
        return piece, None
    hole = grow(mask, 3)
    colour = sky_colour(van, box, mask)
    filler = Image.new("RGBA", crop.size, colour + (255,))
    filler.putalpha(as_image(hole).filter(ImageFilter.GaussianBlur(1.2)))
    return piece, filler


def home_ambience(van):
    """{name: (image, box)} for every moving piece of home and its gap."""
    out = {}
    is_sky = near(PEACH, 30)

    def crop_pixels(box):
        return np.asarray(van.crop(box)).astype(np.int32)

    # The chimney's smoke and the flag on the roof: whatever is not sky round a point inside them.
    for name, seed in [("Smoke", (1100, 420)), ("Flag", (1225, 545))]:
        box = AMBIENT_BOXES[name]
        pixels = crop_pixels(box)
        parts = label(~is_sky(pixels))
        mask = parts == parts[seed[1] - box[1], seed[0] - box[0]]
        mask = mask | ~outside(~mask)
        piece, gap = piece_and_gap(van, box, mask)
        out[f"VanAmb{name}"] = (piece, box)
        out[f"VanAmb{name}Gap"] = (gap, box)

    # The leaves hanging in the open sky.
    for index in range(4):
        name = f"SkyLeaf{index}"
        box = AMBIENT_BOXES[name]
        pixels = crop_pixels(box)
        solid = ~outside(is_sky(pixels))
        solid &= ~outside(solid)
        piece, gap = piece_and_gap(van, box, solid)
        out[f"VanAmb{name}"] = (piece, box)
        out[f"VanAmb{name}Gap"] = (gap, box)

    # The bunting: each pennant below the line it hangs from, so the line itself never moves or breaks.
    band = BUNTING_BAND
    pixels = crop_pixels(band)
    luma = (pixels[..., 0] * 299 + pixels[..., 1] * 587 + pixels[..., 2] * 114) // 1000
    dark = luma < 80
    line_y = np.full(pixels.shape[1], pixels.shape[0], int)
    for x in range(pixels.shape[1]):
        found = np.nonzero(dark[:, x])[0]
        if len(found):
            line_y[x] = found[0]
    below = np.arange(pixels.shape[0])[:, None] >= (line_y[None, :] + 6)
    for index, seed in enumerate(PENNANT_SEEDS):
        mask = outlined(pixels, [(seed[0] - band[0], seed[1] - band[1])], reach=7, dark_below=80) & below
        ys, xs = np.nonzero(mask)
        box = (int(band[0] + xs.min() - 4), int(band[1] + ys.min() - 2), int(band[0] + xs.max() + 5), int(band[1] + ys.max() + 5))
        # The band with a margin round it, so the box can reach a little past it.
        pad = 12
        padded = np.zeros((mask.shape[0] + 2 * pad, mask.shape[1] + 2 * pad), bool)
        padded[pad:-pad, pad:-pad] = mask
        lines = np.concatenate([np.full(pad, line_y[0]), line_y, np.full(pad, line_y[-1])])
        x0, y0 = box[0] - band[0] + pad, box[1] - band[1] + pad
        local = padded[y0:y0 + box[3] - box[1], x0:x0 + box[2] - box[0]]
        piece, gap = piece_and_gap(van, box, local)
        # The gap never reaches above the line.
        gap_alpha = np.asarray(gap.getchannel("A")).copy()
        top = lines[x0:x0 + box[2] - box[0]] + band[1] - box[1] + 6
        rows = np.arange(gap_alpha.shape[0])[:, None]
        gap_alpha[rows < top[None, :]] = 0
        gap.putalpha(Image.fromarray(gap_alpha))
        out[f"VanAmbPennant{index}"] = (piece, box)
        out[f"VanAmbPennant{index}Gap"] = (gap, box)

    # The stove's fire, the lantern's flame and the cat: they only ever grow from how they are drawn, so no gap.
    for name, seeds, reach in [("Fire", [(852, 1410), (830, 1412), (868, 1392), (840, 1426)], 6),
                               ("Flame", [(1148, 1222)], 4),
                               ("Cat", [(900, 1625), (830, 1650), (960, 1655), (880, 1684), (812, 1624), (845, 1610)], 8)]:
        box = AMBIENT_BOXES[name]
        local = [(x - box[0], y - box[1]) for x, y in seeds]
        mask = outlined(crop_pixels(box), local, reach=reach)
        piece, _ = piece_and_gap(van, box, mask, gap=False)
        out[f"VanAmb{name}"] = (piece, box)
    return out


# The steam the picture paints over the pot: three clean puffs above it (the two lower ones touch the pot's rim and
# stay as they are). Each is cut along its own light edge, so the app can swell it in place and send copies of the
# biggest rising off the pot (`VanAmbience.steamSwell`, `steam`).
STEAM_BOX = (715, 1060, 855, 1200)
STEAM_SEEDS = [(759, 1126), (820, 1132), (777, 1096)]


def pot_steam(van):
    a = np.asarray(van.crop(STEAM_BOX)).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lab = label((r > 220) & (g > 180) & (b > 150))
    out = {}
    for index, (sx, sy) in enumerate(STEAM_SEEDS):
        mask = lab == lab[sy - STEAM_BOX[1], sx - STEAM_BOX[0]]
        # A margin round the box, so the puff's soft edge is never cut.
        pad = 4
        mask = np.pad(grow(mask, 1), pad)
        ys, xs = np.nonzero(mask)
        y0, y1, x0, x1 = int(ys.min()) - 2, int(ys.max()) + 3, int(xs.min()) - 2, int(xs.max()) + 3
        box = (STEAM_BOX[0] + x0 - pad, STEAM_BOX[1] + y0 - pad, STEAM_BOX[0] + x1 - pad, STEAM_BOX[1] + y1 - pad)
        piece, _ = piece_and_gap(van, box, mask[y0:y1, x0:x1], gap=False)
        # The wall's lines show faintly through the painted steam; once the puff moves they would move with it, so
        # they take the puff's own colour.
        px = np.asarray(piece).copy()
        solid = px[..., 3] > 200
        steam = np.median(px[solid][:, :3], axis=0)
        dark = (px[..., 3] > 0) & (px[..., :3].astype(np.int32).sum(axis=2) < steam.sum() - 60)
        px[dark, :3] = steam.astype(np.uint8)
        piece = Image.fromarray(px, "RGBA")
        out[f"VanAmbSteam{index}"] = (piece, box)
    return out


# ---------- the buttons' pictures ----------

# Round windows onto the picture for the buttons and counters over the scene: each a square of the picture, centred
# on one thing in it, which the app shows in a circle with the picture's outline. Nothing is drawn.
HUD_ICONS = {"Basket": (317, 1770, 212), "Jug": (488, 1408, 122), "Fire": (848, 1404, 104), "Leaf": (1548, 474, 140),
             "Pip": (1200, 1468, 142), "Gauge": (1003, 1166, 72), "Tools": (482, 1250, 132), "Pot": (765, 1215, 170),
             "Lantern": (1148, 1182, 150)}


def hud_icons(van):
    out = {}
    for name, (cx, cy, size) in HUD_ICONS.items():
        box = (round(cx - size / 2), round(cy - size / 2), round(cx + size / 2), round(cy + size / 2))
        out["VanIcon" + name] = van.crop(box).resize((144, 144), Image.LANCZOS)
    return out


# ---------- writing ----------

def imageset(name, filename, image=None, copy=None, quality=None):
    folder = ASSETS / f"{name}.imageset"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    if copy:
        shutil.copyfile(copy, folder / filename)
    elif quality:
        image.save(folder / filename, quality=quality, subsampling=0)
    else:
        image.save(folder / filename, optimize=True)
    contents = {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2, sort_keys=True) + "\n")


def main():
    van = Image.open(CONCEPTS / "syrup-van.jpg").convert("RGB")
    is_sky = near(PEACH, 30)
    leaves = [cut_from(van, (1474, 410, 1606, 536), is_sky),   # an orange maple leaf
              cut_from(van, (1284, 262, 1396, 356), is_sky),   # a plain yellow one
              cut_from(van, (1632, 1574, 1722, 1660), is_grass)]  # a red maple leaf
    scene = tree_scene(van)
    pip = pip_with_pail(leaves)

    imageset("VanHomePicture", "syrup-van.jpg", copy=CONCEPTS / "syrup-van.jpg")
    imageset("VanTreeScene", "tree-scene.jpg", scene, quality=93)
    imageset("VanTreePip", "pip-pail.png", pip)
    imageset("VanTreePipAlone", "pip-alone.png", pip_alone())
    imageset("VanTreePail", "pail.png", pail_alone(leaves))
    lids = tree_eyelids()
    imageset("VanTreePipLids", "pip-lids.png", lids)
    for name, leaf in zip(["VanLeafOrange", "VanLeafYellow", "VanLeafRed"], leaves):
        imageset(name, name.lower() + ".png", leaf)

    masks = home_masks()
    behind = behind_pip(van, masks)
    pieces = {"VanHomeBehindPip": behind, "VanHomePip": home_piece(van, masks["body"]),
              "VanHomePipTail": home_piece(van, masks["tail"], masks["tail under"]),
              "VanHomePipEar": home_piece(van, masks["ear"], masks["ear under"]),
              "VanHomeLadle": home_piece(van, masks["ladle"]), "VanHomePipLids": eyelids(van),
              "VanHomeBasketFront": basket_front(van)}
    pieces.update(props())
    for name, piece in pieces.items():
        imageset(name, name.lower() + ".png", piece)
    for name, icon in hud_icons(van).items():
        imageset(name, name.lower() + ".png", icon)
    ambience = home_ambience(van)
    ambience.update(pot_steam(van))
    for name, (piece, box) in ambience.items():
        imageset(name, name.lower() + ".png", piece)
    print("ambient boxes:", {name: box for name, (_, box) in ambience.items() if not name.endswith("Gap")})

    if len(sys.argv) > 1:
        out = pathlib.Path(sys.argv[1])
        out.mkdir(parents=True, exist_ok=True)
        whole = scene.convert("RGBA")
        w = round(pip.width * PIP_SCALE)
        small = pip.resize((w, round(pip.height * PIP_SCALE)), Image.LANCZOS)
        # His feet (500, 690 in his own picture) stand on PIP_FEET.
        whole.alpha_composite(small, (round(PIP_FEET[0] - (500 - PIP_BOX[0]) * PIP_SCALE), round(PIP_FEET[1] - (690 - PIP_BOX[1]) * PIP_SCALE)))
        whole.convert("RGB").save(out / "tree-scene.png")
        scene.save(out / "tree-only.png")
        pip.save(out / "pip-pail.png")
        blink = pip.copy()
        blink.alpha_composite(lids)
        blink.crop((200, 100, 480, 260)).resize((840, 480), Image.LANCZOS).save(out / "pip-blink.png")
        for i, leaf in enumerate(leaves):
            leaf.save(out / f"leaf-{i}.png")
        for name, piece in pieces.items():
            piece.save(out / f"{name}.png")
        # Home with Pip gone, and home with his pieces laid back: the second must be the picture itself.
        empty = van.convert("RGBA")
        empty.alpha_composite(behind, PATCH_BOX[:2])
        view = (1000, 1350, 1360, 1740)
        empty.crop(view).resize((1080, 1170), Image.LANCZOS).convert("RGB").save(out / "home-empty.png")
        whole = empty.copy()
        for name in ("VanHomePipTail", "VanHomePipEar", "VanHomePip", "VanHomeLadle"):
            whole.alpha_composite(pieces[name], HOME_BOX[:2])
        whole.crop(view).resize((1080, 1170), Image.LANCZOS).convert("RGB").save(out / "home-whole.png")
        for name in ("tail", "tail under", "ear", "ear under", "ladle", "body"):
            ys, xs = np.nonzero(masks[name])
            print(name, "in the picture: x", HOME_BOX[0] + xs.min() / 2, HOME_BOX[0] + xs.max() / 2, "y", HOME_BOX[1] + ys.min() / 2,
                  HOME_BOX[1] + ys.max() / 2, "middle", HOME_BOX[0] + xs.mean() / 2, HOME_BOX[1] + ys.mean() / 2)
        alive = van.convert("RGBA")
        for name, (piece, box) in ambience.items():
            if name.endswith("Gap"):
                alive.alpha_composite(piece, box[:2])
        alive.save(out / "home-gaps.png")
        for name, (piece, box) in ambience.items():
            piece.save(out / f"{name}.png")
        apart = np.abs(np.asarray(whole.convert("RGB")).astype(int) - np.asarray(van).astype(int)).max(axis=2)
        print("home put back together: differs by more than 12 at", int((apart > 12).sum()), "pixels, most", int(apart.max()))
    print("pip sprite", pip.size, "scene", scene.size, "leaves", [leaf.size for leaf in leaves])


if __name__ == "__main__":
    main()
