#!/usr/bin/env python3
"""Draws the icons on home's wooden board, in the van picture's look: thick dark outlines and flat warm colours.

The owner picked drawn icons over windows onto the picture and over cut-outs of it (28 Nov 2026: "B looks better"),
with Pip's face made to look like him ("make the squirel logo look more similiar to pip"). Each is drawn four times
over and scaled down, and written to the `VanIcon…` image sets:

    python3 -I Scripts/art/icons/build_van_icons.py [preview folder]

Needs Pillow and numpy.
"""

import json
import math
import pathlib
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[3]
ASSETS = ROOT / "App/Resources/Assets.xcassets/Van"

SIZE = 144
K = 4
BIG = SIZE * K
LINE = (40, 15, 7)
# Pip's own colours, sampled from the concept picture.
FUR = (188, 84, 57)
PEACH = (244, 178, 132)
EAR = (236, 159, 107)


def catmull(points, steps=10):
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


def loop(points, steps=10):
    """A smooth closed curve through the points."""
    return catmull(points[-2:] + points + points[:2], steps)[2 * steps:-2 * steps]


class Pen:
    """Draws on a square from 0 to 1 at four times the icon's size."""

    def __init__(self):
        self.img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    @staticmethod
    def p(pts):
        return [(x * BIG, y * BIG) for x, y in pts]

    def shape(self, pts, fill, width=0.045):
        pts = self.p(pts)
        self.d.polygon(pts, fill=fill + (255,))
        if width:
            self._stroke(pts + [pts[0]], width, LINE)

    def flat(self, pts, fill):
        self.d.polygon(self.p(pts), fill=fill + (255,))

    def line(self, pts, width=0.04, colour=LINE):
        self._stroke(self.p(pts), width, colour)

    def _stroke(self, pts, width, colour):
        w = round(width * BIG)
        self.d.line(pts, fill=colour + (255,), width=w, joint="curve")
        for x, y in (pts[0], pts[-1]):
            self.d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=colour + (255,))

    def oval(self, cx, cy, rx, ry, fill, width=0.045):
        box = ((cx - rx) * BIG, (cy - ry) * BIG, (cx + rx) * BIG, (cy + ry) * BIG)
        self.d.ellipse(box, fill=fill + (255,) if fill else None, outline=LINE + (255,) if width else None,
                       width=round(width * BIG))

    def clear(self, pts):
        self.d.polygon(self.p(pts), fill=(0, 0, 0, 0))

    def done(self):
        return self.img.resize((SIZE, SIZE), Image.LANCZOS)


def maple_leaf(cx, cy, s, turn=0.0):
    half = [(0, -1.0), (0.13, -0.74), (0.3, -0.84), (0.25, -0.44), (0.5, -0.66), (0.56, -0.52), (0.84, -0.58), (0.74, -0.32),
            (0.9, -0.24), (0.52, 0.08), (0.6, 0.24), (0.08, 0.16), (0.05, 0.5)]
    pts = half + [(-x, y) for x, y in reversed(half)]
    c, si = math.cos(turn), math.sin(turn)
    return [(cx + s * (x * c - y * si), cy + s * (x * si + y * c)) for x, y in pts]


def ellipse_points(cx, cy, rx, ry, n=72):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def leaves():
    """A wicker basket heaped with maple leaves."""
    pen = Pen()
    for leaf, colour, turn in [((0.36, 0.36, 0.2), (232, 120, 52), -0.5), ((0.64, 0.34, 0.2), (240, 170, 60), 0.45),
                               ((0.5, 0.28, 0.22), (214, 84, 48), 0.0)]:
        pen.shape(maple_leaf(*leaf, turn), colour, 0.035)
    body = catmull([(0.14, 0.48), (0.2, 0.78), (0.32, 0.88), (0.68, 0.88), (0.8, 0.78), (0.86, 0.48)])
    pen.shape(body + [(0.86, 0.48), (0.14, 0.48)], (222, 170, 96))
    for y in (0.6, 0.72):
        pen.line(catmull([(0.18, y), (0.5, y + 0.03), (0.82, y)]), 0.022, (150, 98, 52))
    for x in (0.3, 0.42, 0.54, 0.66):
        pen.line([(x, 0.52), (x + 0.01, 0.84)], 0.018, (170, 116, 62))
    pen.shape(catmull([(0.1, 0.44), (0.5, 0.52), (0.9, 0.44), (0.9, 0.52), (0.5, 0.6), (0.1, 0.52)], 6), (236, 192, 120), 0.035)
    return pen.done()


def syrup():
    """A maple syrup jug with a leaf on its label."""
    pen = Pen()
    pen.oval(0.74, 0.5, 0.12, 0.14, None, 0.06)
    jug = catmull([(0.42, 0.18), (0.42, 0.3), (0.22, 0.46), (0.2, 0.78), (0.3, 0.9), (0.7, 0.9), (0.8, 0.78), (0.78, 0.46),
                   (0.58, 0.3), (0.58, 0.18)])
    pen.shape(jug + [(0.42, 0.18)], (246, 236, 214))
    pen.flat(catmull([(0.25, 0.52), (0.5, 0.56), (0.75, 0.52), (0.76, 0.78), (0.68, 0.86), (0.32, 0.86), (0.24, 0.78)], 8),
             (204, 104, 42))
    pen.line(jug + [(0.42, 0.18)], 0.045)
    pen.shape([(0.39, 0.08), (0.61, 0.08), (0.6, 0.2), (0.4, 0.2)], (176, 118, 70), 0.04)
    pen.oval(0.5, 0.71, 0.12, 0.1, (250, 232, 196), 0.03)
    pen.shape(maple_leaf(0.5, 0.71, 0.075), (200, 70, 40), 0.018)
    pen.line([(0.3, 0.6), (0.3, 0.76)], 0.03, (255, 248, 236))
    return pen.done()


def streak():
    """A flame."""
    pen = Pen()
    outer = catmull([(0.5, 0.06), (0.62, 0.3), (0.76, 0.42), (0.8, 0.64), (0.68, 0.86), (0.5, 0.92), (0.32, 0.86), (0.2, 0.64),
                     (0.26, 0.42), (0.36, 0.5), (0.4, 0.28)])
    pen.shape(outer, (234, 110, 46))
    inner = catmull([(0.52, 0.36), (0.62, 0.56), (0.64, 0.72), (0.5, 0.84), (0.38, 0.74), (0.4, 0.58), (0.46, 0.62)])
    pen.shape(inner, (248, 196, 82), 0.035)
    return pen.done()


def pip():
    """Pip's face, turned a little to his left as in the van picture: a wide head, pointed ears with peach insides,
    peach round the eyes and over the cheeks, dot eyes, a small nose and a "w" smile, and his curled tail behind."""
    pen = Pen()
    # The tail, curling up behind his head on the left, with its peach stripe.
    tail = loop([(0.08, 0.5), (0.04, 0.3), (0.14, 0.12), (0.32, 0.06), (0.46, 0.14), (0.4, 0.34), (0.3, 0.5)])
    pen.shape(tail, FUR)
    pen.line(catmull([(0.16, 0.44), (0.12, 0.28), (0.2, 0.16), (0.32, 0.14), (0.34, 0.24), (0.26, 0.28)], 8), 0.05, PEACH)
    # Ears, round at the tips: the near one bigger.
    pen.shape(loop([(0.26, 0.44), (0.22, 0.24), (0.27, 0.1), (0.36, 0.13), (0.5, 0.34)], 8), FUR, 0.042)
    pen.flat(loop([(0.3, 0.36), (0.28, 0.24), (0.31, 0.17), (0.36, 0.2), (0.42, 0.32)], 8), EAR)
    pen.shape(loop([(0.6, 0.32), (0.68, 0.15), (0.77, 0.08), (0.84, 0.18), (0.88, 0.42)], 8), FUR, 0.042)
    pen.flat(loop([(0.66, 0.3), (0.71, 0.19), (0.77, 0.15), (0.81, 0.22), (0.82, 0.34)], 8), EAR)
    # The head, round with puffed cheeks, and the peach of his face inside it.
    head = loop([(0.13, 0.64), (0.18, 0.42), (0.38, 0.28), (0.64, 0.27), (0.86, 0.38), (0.94, 0.6), (0.86, 0.84),
                 (0.54, 0.94), (0.22, 0.86)])
    pen.flat(head, FUR)
    face = Pen()
    face.oval(0.42, 0.56, 0.115, 0.1, PEACH, 0)
    face.oval(0.72, 0.54, 0.1, 0.09, PEACH, 0)
    face.flat(loop([(0.2, 0.76), (0.34, 0.64), (0.52, 0.62), (0.68, 0.62), (0.88, 0.66), (0.86, 0.84), (0.56, 0.96),
                    (0.28, 0.92)]), PEACH)
    inside = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(inside).polygon(Pen.p(head), fill=255)
    pen.img.paste(face.img, (0, 0), Image.fromarray(np.minimum(np.asarray(inside), np.asarray(face.img.getchannel("A")))))
    pen.line(head + [head[0]], 0.048)
    # Eyes, nose and smile.
    pen.oval(0.43, 0.56, 0.046, 0.056, LINE, 0)
    pen.oval(0.715, 0.545, 0.042, 0.052, LINE, 0)
    pen.shape(loop([(0.585, 0.64), (0.635, 0.63), (0.61, 0.675)], 6), LINE, 0.012)
    pen.line(catmull([(0.52, 0.7), (0.56, 0.74), (0.61, 0.7), (0.66, 0.74), (0.7, 0.7)], 6), 0.026)
    return pen.done()


def history():
    """A brass clock: the study record."""
    pen = Pen()
    pen.oval(0.5, 0.5, 0.42, 0.42, (214, 140, 70))
    pen.oval(0.5, 0.5, 0.32, 0.32, (255, 244, 226), 0.035)
    for i in range(12):
        a = i * math.pi / 6
        r0 = 0.25 if i % 3 else 0.22
        pen.line([(0.5 + r0 * math.sin(a), 0.5 - r0 * math.cos(a)), (0.5 + 0.28 * math.sin(a), 0.5 - 0.28 * math.cos(a))], 0.018)
    pen.line([(0.5, 0.5), (0.5, 0.29)], 0.04)
    pen.line([(0.5, 0.5), (0.65, 0.58)], 0.04)
    pen.oval(0.5, 0.5, 0.04, 0.04, (200, 70, 40), 0.02)
    return pen.done()


def machines():
    """A wrench and a screwdriver, crossed."""
    pen = Pen()

    def bar(x0, y0, x1, y1, w):
        dx, dy = x1 - x0, y1 - y0
        n = math.hypot(dx, dy)
        px, py = -dy / n * w, dx / n * w
        return [(x0 + px, y0 + py), (x1 + px, y1 + py), (x1 - px, y1 - py), (x0 - px, y0 - py)]

    pen.shape(bar(0.24, 0.24, 0.78, 0.78, 0.045), (196, 196, 196))
    pen.shape(bar(0.7, 0.7, 0.86, 0.86, 0.08), (226, 92, 52))
    pen.shape(bar(0.76, 0.24, 0.3, 0.7, 0.05), (178, 178, 180))
    pen.shape(ellipse_points(0.7, 0.3, 0.16, 0.16, 30), (196, 196, 196))
    # The wrench's open jaw.
    pen.clear([(0.7, 0.3), (0.86, 0.06), (0.98, 0.2), (0.74, 0.34)])
    pen.line([(0.7, 0.3), (0.83, 0.1)], 0.045)
    pen.line([(0.72, 0.33), (0.93, 0.21)], 0.045)
    pen.shape(bar(0.32, 0.68, 0.16, 0.84, 0.07), (226, 92, 52))
    return pen.done()


ICONS = {"VanIconBasket": leaves, "VanIconJug": syrup, "VanIconFire": streak, "VanIconPip": pip,
         "VanIconGauge": history, "VanIconTools": machines}


def imageset(name, image):
    folder = ASSETS / f"{name}.imageset"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    filename = name.lower() + ".png"
    image.save(folder / filename, optimize=True)
    contents = {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2, sort_keys=True) + "\n")


def main():
    drawn = {name: draw() for name, draw in ICONS.items()}
    for name, image in drawn.items():
        imageset(name, image)
    if len(sys.argv) > 1:
        out = pathlib.Path(sys.argv[1])
        out.mkdir(parents=True, exist_ok=True)
        sheet = Image.new("RGBA", (len(drawn) * (SIZE + 16) + 16, SIZE + 32), (214, 151, 97, 255))
        for i, image in enumerate(drawn.values()):
            sheet.alpha_composite(image, (16 + i * (SIZE + 16), 16))
        sheet.save(out / "van-icons.png")


if __name__ == "__main__":
    main()
