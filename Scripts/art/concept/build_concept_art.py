#!/usr/bin/env python3
"""Cuts the app's van pictures out of the concept art, pixel for pixel.

The van, the maple and Pip are the concept pictures themselves: nothing here redraws them. The home picture is the
concept file, copied byte for byte. The maple of the session view is the same picture with the van, the bunting and
the smoke painted out in the sky's colour, its trunk carried on down to a patch of the same grass. Pip is cut along
his own outline; the pail in his paw is the one thing drawn here.

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


def pip_cutout():
    src = Image.open(CONCEPTS / "pip-from-van.jpg").convert("RGB")
    a = np.asarray(src).astype(np.int32)
    luma = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
    dark = luma < 72
    lab = label(~dark)
    fur = np.zeros(dark.shape, bool)
    # One point inside each closed part of him: an ear, the tail, the body, the other ear.
    for x, y in [(530, 195), (250, 250), (400, 550), (420, 220)]:
        fur |= lab == lab[y, x]
    # His own outline is the dark line hugging those parts; the eyes and the leaf's veins are the holes it leaves.
    mask = fur | (dark & grow(fur, 10))
    mask = mask | ~outside(~mask)
    # Other things' lines touch his outline (the rug's fringe, a drawer): thin stubs, which opening takes off.
    mask = grow(shrink(mask, 4), 4) & mask
    out = src.convert("RGBA")
    out.putalpha(as_image(mask).filter(ImageFilter.GaussianBlur(0.8)))
    return out


def pip_with_pail(leaves):
    """Pip as he stands in the concept, the ladle gone, a pail of leaves hanging from the same paw."""
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
    sprite.alpha_composite(pip_cutout().crop(PIP_BOX))
    return sprite


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
    for name, leaf in zip(["VanLeafOrange", "VanLeafYellow", "VanLeafRed"], leaves):
        imageset(name, name.lower() + ".png", leaf)

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
        for i, leaf in enumerate(leaves):
            leaf.save(out / f"leaf-{i}.png")
    print("pip sprite", pip.size, "scene", scene.size, "leaves", [leaf.size for leaf in leaves])


if __name__ == "__main__":
    main()
