#!/usr/bin/env python3
"""Draws the van's icons in the picture's look: thick dark outlines and flat warm colours, drawn by hand.

The owner picked drawn icons over windows onto the picture and over cut-outs of it (28 Nov 2026: "B looks better"),
with Pip's face made to look like him ("make the squirel logo look more similiar to pip"), and then asked for lines that
look drawn rather than ruled ("the lines they are not perfect they feel like they have been drawn they are a bit rough").
So every line here wanders a little and its ink thickens and thins, the same way each time (each icon has its own seed).

Each icon is drawn four times over and scaled down, and written to the `VanIcon…` image sets:

    python3 -I Scripts/art/icons/build_van_icons.py [preview folder]

Needs Pillow and numpy.
"""

import json
import math
import pathlib
import random
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[3]
ASSETS = ROOT / "App/Resources/Assets.xcassets/Van"

# Big enough for home's big buttons (90 points, three pixels to the point) as well as the counters' small ones.
SIZE = 288
K = 4
BIG = SIZE * K
LINE = (40, 15, 7)
CREAM = (255, 244, 226)
# Pip's own colours, sampled from the concept picture.
FUR = (188, 84, 57)
PEACH = (244, 178, 132)
EAR = (236, 159, 107)

# How rough the hand is, in the icon's own units (0 to 1 across): how far a line wanders either side, and how much its
# ink thickens and thins.
WANDER = 0.006
SWELL = 0.22
# The waves they follow along a line: (length of one wave, its share).
WANDER_WAVES = ((0.32, 0.75), (0.13, 0.25))
SWELL_WAVES = ((0.2, 0.7), (0.09, 0.3))


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


def resample(points, spacing, closed):
    """Points along the line about `spacing` apart, so the wander and the swell are as smooth on a long edge as on a
    short one."""
    pts = np.asarray(points, dtype=float)
    if closed:
        pts = np.vstack([pts, pts[:1]])
    seg = np.hypot(*np.diff(pts, axis=0).T)
    total = float(seg.sum())
    if total <= 0:
        return pts[:1], 0.0
    count = max(8, int(round(total / spacing)))
    at = np.linspace(0, total, count, endpoint=not closed)
    cum = np.concatenate([[0], np.cumsum(seg)])
    x = np.interp(at, cum, pts[:, 0])
    y = np.interp(at, cum, pts[:, 1])
    return np.stack([x, y], axis=1), total


def normals(pts, closed):
    if closed:
        before, after = np.roll(pts, 1, axis=0), np.roll(pts, -1, axis=0)
    else:
        before = np.vstack([pts[:1], pts[:-1]])
        after = np.vstack([pts[1:], pts[-1:]])
    d = after - before
    length = np.maximum(1e-9, np.hypot(d[:, 0], d[:, 1]))
    return np.stack([d[:, 1] / length, -d[:, 0] / length], axis=1)


class Pen:
    """Draws on a square from 0 to 1 at four times the icon's size, by hand."""

    def __init__(self, seed=1):
        self.img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.rng = random.Random(seed)

    @staticmethod
    def p(pts):
        return [(x * BIG, y * BIG) for x, y in pts]

    def _wave(self, count, length, closed, waves):
        """A smooth wave along a line, between -1 and 1: a long swell and a smaller ripple. Round a closed line it
        goes a whole number of times, so the line meets itself without a step."""
        t = np.arange(count) / count if closed else np.linspace(0, 1, count)
        wave = np.zeros(count)
        for wavelength, size in waves:
            cycles = length / wavelength
            if closed:
                cycles = max(1, round(cycles))
            wave += size * np.sin(2 * math.pi * cycles * t + self.rng.uniform(0, 2 * math.pi))
        return wave

    def _hand(self, pts, closed):
        """The line as a hand draws it: resampled, then wandering either side of where it was meant to go."""
        line, length = resample(pts, 0.004, closed)
        if len(line) < 3:
            return line, length
        push = WANDER * self._wave(len(line), length, closed, WANDER_WAVES)
        return line + normals(line, closed) * push[:, None], length

    def _ink(self, line, length, width, colour, closed):
        """Ink along the line, `width` wide on average, thicker and thinner as it goes; an open line thins toward its
        ends, as a pen lifts."""
        if len(line) < 2:
            return
        half = width / 2 * (1 + SWELL * self._wave(len(line), length, closed, SWELL_WAVES))
        if not closed:
            along = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(line, axis=0).T))])
            ends = np.minimum(along, along[-1] - along)
            half *= 0.55 + 0.45 * np.minimum(1, ends / 0.03)
        n = normals(line, closed)
        outer = (line + n * half[:, None]) * BIG
        inner = (line - n * half[:, None]) * BIG
        fill = colour + (255,)
        count = len(line) if closed else len(line) - 1
        for i in range(count):
            j = (i + 1) % len(line)
            self.d.polygon([tuple(outer[i]), tuple(outer[j]), tuple(inner[j]), tuple(inner[i])], fill=fill)
        for i in range(len(line)):
            r = half[i] * BIG
            x, y = line[i] * BIG
            self.d.ellipse((x - r, y - r, x + r, y + r), fill=fill)

    def shape(self, pts, fill, width=0.045):
        line, length = self._hand(pts, True)
        self.d.polygon([tuple(q) for q in line * BIG], fill=fill + (255,))
        if width:
            self._ink(line, length, width, LINE, True)

    def flat(self, pts, fill):
        line, _ = self._hand(pts, True)
        self.d.polygon([tuple(q) for q in line * BIG], fill=fill + (255,))

    def line(self, pts, width=0.04, colour=LINE):
        line, length = self._hand(pts, False)
        self._ink(line, length, width, colour, False)

    def ring(self, pts, width=0.04, colour=LINE):
        """A closed outline with nothing inside it."""
        line, length = self._hand(pts, True)
        self._ink(line, length, width, colour, True)

    def oval(self, cx, cy, rx, ry, fill, width=0.045):
        pts = ellipse_points(cx, cy, rx, ry)
        if fill:
            self.shape(pts, fill, width)
        elif width:
            self.ring(pts, width)

    def clear(self, pts):
        self.d.polygon(self.p(pts), fill=(0, 0, 0, 0))

    def done(self):
        return self.img.resize((SIZE, SIZE), Image.LANCZOS)


def maple_leaf(cx, cy, s, turn=0.0, squash=1.0):
    """A maple leaf: `squash` below 1 lays it down, seen from the side."""
    half = [(0, -1.0), (0.13, -0.74), (0.3, -0.84), (0.25, -0.44), (0.5, -0.66), (0.56, -0.52), (0.84, -0.58), (0.74, -0.32),
            (0.9, -0.24), (0.52, 0.08), (0.6, 0.24), (0.08, 0.16), (0.05, 0.5)]
    pts = half + [(-x, y) for x, y in reversed(half)]
    c, si = math.cos(turn), math.sin(turn)
    return [(cx + s * (x * c - y * si), cy + s * squash * (x * si + y * c)) for x, y in pts]


def ellipse_points(cx, cy, rx, ry, n=72):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def turned(pts, cx, cy, turn):
    c, s = math.cos(turn), math.sin(turn)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def leaves():
    """A wicker basket heaped with maple leaves."""
    pen = Pen(11)
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
    pen = Pen(12)
    pen.oval(0.74, 0.5, 0.12, 0.14, None, 0.06)
    jug = catmull([(0.42, 0.18), (0.42, 0.3), (0.22, 0.46), (0.2, 0.78), (0.3, 0.9), (0.7, 0.9), (0.8, 0.78), (0.78, 0.46),
                   (0.58, 0.3), (0.58, 0.18)])
    pen.flat(jug + [(0.42, 0.18)], (246, 236, 214))
    pen.flat(catmull([(0.25, 0.52), (0.5, 0.56), (0.75, 0.52), (0.76, 0.78), (0.68, 0.86), (0.32, 0.86), (0.24, 0.78)], 8),
             (204, 104, 42))
    pen.ring(jug + [(0.42, 0.18)], 0.045)
    pen.shape([(0.39, 0.08), (0.61, 0.08), (0.6, 0.2), (0.4, 0.2)], (176, 118, 70), 0.04)
    pen.oval(0.5, 0.71, 0.12, 0.1, (250, 232, 196), 0.03)
    pen.shape(maple_leaf(0.5, 0.71, 0.075), (200, 70, 40), 0.018)
    pen.line([(0.3, 0.6), (0.3, 0.76)], 0.03, (255, 248, 236))
    return pen.done()


def streak():
    """A flame."""
    pen = Pen(13)
    outer = catmull([(0.5, 0.06), (0.62, 0.3), (0.76, 0.42), (0.8, 0.64), (0.68, 0.86), (0.5, 0.92), (0.32, 0.86), (0.2, 0.64),
                     (0.26, 0.42), (0.36, 0.5), (0.4, 0.28)])
    pen.shape(outer, (234, 110, 46))
    inner = catmull([(0.52, 0.36), (0.62, 0.56), (0.64, 0.72), (0.5, 0.84), (0.38, 0.74), (0.4, 0.58), (0.46, 0.62)])
    pen.shape(inner, (248, 196, 82), 0.035)
    return pen.done()


def pip():
    """Pip's face, turned a little to his left as in the van picture: a wide head, pointed ears with peach insides,
    peach round the eyes and over the cheeks, dot eyes, a small nose and a "w" smile, and his curled tail behind."""
    pen = Pen(14)
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
    face = Pen(15)
    face.flat(ellipse_points(0.42, 0.56, 0.115, 0.1), PEACH)
    face.flat(ellipse_points(0.72, 0.54, 0.1, 0.09), PEACH)
    face.flat(loop([(0.2, 0.76), (0.34, 0.64), (0.52, 0.62), (0.68, 0.62), (0.88, 0.66), (0.86, 0.84), (0.56, 0.96),
                    (0.28, 0.92)]), PEACH)
    inside = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(inside).polygon(Pen.p(head), fill=255)
    pen.img.paste(face.img, (0, 0), Image.fromarray(np.minimum(np.asarray(inside), np.asarray(face.img.getchannel("A")))))
    pen.ring(head, 0.048)
    # Eyes, nose and smile.
    pen.flat(ellipse_points(0.43, 0.56, 0.046, 0.056), LINE)
    pen.flat(ellipse_points(0.715, 0.545, 0.042, 0.052), LINE)
    pen.shape(loop([(0.585, 0.64), (0.635, 0.63), (0.61, 0.675)], 6), LINE, 0.012)
    pen.line(catmull([(0.52, 0.7), (0.56, 0.74), (0.61, 0.7), (0.66, 0.74), (0.7, 0.7)], 6), 0.026)
    return pen.done()


def record():
    """A notebook with a leaf on its cover and a ribbon marking the page: the study record."""
    pen = Pen(16)
    # The pages, peeping out at the right and the bottom.
    pen.shape([(0.26, 0.14), (0.82, 0.16), (0.82, 0.88), (0.26, 0.88)], CREAM, 0.035)
    for x in (0.795, 0.77):
        pen.line([(x, 0.2), (x, 0.84)], 0.012, (196, 170, 130))
    # The ribbon, hanging out of the bottom.
    pen.shape([(0.58, 0.8), (0.66, 0.8), (0.66, 0.97), (0.62, 0.92), (0.58, 0.97)], (200, 70, 40), 0.03)
    # The cover, with a darker spine.
    pen.shape([(0.18, 0.1), (0.76, 0.1), (0.76, 0.84), (0.18, 0.84)], (122, 138, 74))
    pen.shape([(0.18, 0.1), (0.29, 0.1), (0.29, 0.84), (0.18, 0.84)], (92, 106, 54), 0.035)
    # The label and its two lines of writing, and the leaf.
    pen.shape([(0.37, 0.2), (0.68, 0.2), (0.68, 0.37), (0.37, 0.37)], CREAM, 0.03)
    pen.line([(0.42, 0.26), (0.63, 0.26)], 0.016)
    pen.line([(0.42, 0.31), (0.57, 0.31)], 0.016)
    pen.shape(maple_leaf(0.525, 0.6, 0.13, 0.15), (232, 120, 52), 0.03)
    return pen.done()


def alarm_clock():
    """A round alarm clock with two bells on top and little feet: the timer."""
    pen = Pen(17)
    gold = (240, 176, 70)
    # Feet.
    pen.line([(0.3, 0.8), (0.21, 0.93)], 0.07)
    pen.line([(0.7, 0.8), (0.79, 0.93)], 0.07)
    # The hammer and its knob, between the bells.
    pen.line([(0.5, 0.21), (0.5, 0.1)], 0.045)
    pen.oval(0.5, 0.08, 0.05, 0.04, gold, 0.03)
    # The bells: domes tipped out to either side.
    for cx, turn in ((0.27, -0.6), (0.73, 0.6)):
        dome = [(cx + 0.15 * math.cos(a), 0.24 - 0.13 * math.sin(a)) for a in np.linspace(0, math.pi, 24)]
        pen.shape(turned(dome, cx, 0.24, turn), gold, 0.04)
    # The body and its face.
    pen.oval(0.5, 0.54, 0.34, 0.34, (214, 90, 50))
    pen.line(catmull([(0.25, 0.42), (0.32, 0.3), (0.44, 0.24)], 6), 0.03, (240, 150, 110))
    pen.oval(0.5, 0.54, 0.255, 0.255, CREAM, 0.035)
    for i in range(12):
        a = i * math.pi / 6
        r0 = 0.19 if i % 3 else 0.165
        pen.line([(0.5 + r0 * math.sin(a), 0.54 - r0 * math.cos(a)), (0.5 + 0.215 * math.sin(a), 0.54 - 0.215 * math.cos(a))],
                 0.02 if i % 3 else 0.026)
    pen.line([(0.5, 0.54), (0.5, 0.38)], 0.042)
    pen.line([(0.5, 0.54), (0.63, 0.6)], 0.042)
    pen.oval(0.5, 0.54, 0.035, 0.035, (200, 70, 40), 0.02)
    return pen.done()


def crescent(c1, r1, c2, r2, n=180):
    """The part of the circle round `c1` outside the circle round `c2`, as one closed outline."""
    def outside(p):
        return math.hypot(p[0] - c2[0], p[1] - c2[1]) > r2

    def inside(p):
        return math.hypot(p[0] - c1[0], p[1] - c1[1]) < r1

    outer = [(c1[0] + r1 * math.cos(2 * math.pi * i / n), c1[1] + r1 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    inner = [(c2[0] + r2 * math.cos(2 * math.pi * i / n), c2[1] + r2 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    # Start each arc just after it comes into the crescent, so it runs in one piece.
    start = next(i for i in range(n) if not outside(outer[i - 1]) and outside(outer[i]))
    arc = [outer[(start + i) % n] for i in range(n) if outside(outer[(start + i) % n])]
    start = next(i for i in range(n) if not inside(inner[i - 1]) and inside(inner[i]))
    back = [inner[(start + i) % n] for i in range(n) if inside(inner[(start + i) % n])]
    return arc + list(reversed(back))


def zzz():
    """A sleepy crescent moon and three Zs drifting up from it: wind-down."""
    pen = Pen(18)
    pen.shape(crescent((0.32, 0.62), 0.27, (0.46, 0.52), 0.23), (240, 176, 70), 0.045)
    z = [(0, 0), (1, 0), (1, 0.24), (0.42, 0.76), (1, 0.76), (1, 1), (0, 1), (0, 0.76), (0.58, 0.24), (0, 0.24)]
    for (x, y, s, turn) in ((0.6, 0.56, 0.24, -0.15), (0.78, 0.33, 0.18, -0.05), (0.9, 0.13, 0.14, 0.08)):
        pts = [(x + s * (px - 0.5), y + s * (py - 0.5)) for px, py in z]
        pen.shape(turned(pts, x, y, turn), CREAM, 0.03)
    return pen.done()


def leaves_falling():
    """Two leaves coming down, with the swing of their fall behind them: the scene moving (calm off)."""
    pen = Pen(19)
    pen.line(catmull([(0.06, 0.1), (0.14, 0.2), (0.2, 0.16)], 6), 0.03)
    pen.line(catmull([(0.04, 0.26), (0.12, 0.32)], 4), 0.03)
    pen.shape(maple_leaf(0.34, 0.32, 0.24, -0.45), (232, 120, 52), 0.04)
    pen.line(catmull([(0.42, 0.58), (0.5, 0.66), (0.56, 0.62)], 6), 0.03)
    pen.line(catmull([(0.4, 0.72), (0.47, 0.76)], 4), 0.03)
    pen.shape(maple_leaf(0.7, 0.7, 0.22, 0.5), (214, 84, 48), 0.04)
    return pen.done()


def leaves_still():
    """A leaf lying still on the grass: the scene resting (calm on)."""
    pen = Pen(20)
    pen.shape(catmull([(0.08, 0.86), (0.2, 0.74), (0.5, 0.7), (0.8, 0.74), (0.92, 0.86)], 8) + [(0.92, 0.9), (0.08, 0.9)],
              (160, 159, 95), 0.035)
    for x in (0.22, 0.34, 0.68, 0.8):
        pen.line([(x, 0.8), (x + 0.02, 0.74)], 0.016, (110, 112, 60))
    pen.shape(maple_leaf(0.5, 0.64, 0.34, 0.25, squash=0.42), (232, 120, 52), 0.04)
    return pen.done()


def machines():
    """A wrench and a screwdriver, crossed."""
    pen = Pen(21)

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
         "VanIconRecord": record, "VanIconClock": alarm_clock, "VanIconSleep": zzz, "VanIconTools": machines,
         "VanIconLeavesFalling": leaves_falling, "VanIconLeavesStill": leaves_still}
# Icons this script used to draw, and no longer does.
RETIRED = ["VanIconGauge"]


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
    for name in RETIRED:
        folder = ASSETS / f"{name}.imageset"
        if folder.exists():
            shutil.rmtree(folder)
    if len(sys.argv) > 1:
        out = pathlib.Path(sys.argv[1])
        out.mkdir(parents=True, exist_ok=True)
        cell = SIZE // 2
        sheet = Image.new("RGBA", (len(drawn) * (cell + 16) + 16, cell + 32), (255, 221, 194, 255))
        for i, image in enumerate(drawn.values()):
            sheet.alpha_composite(image.resize((cell, cell), Image.LANCZOS), (16 + i * (cell + 16), 16))
        sheet.save(out / "van-icons.png")


if __name__ == "__main__":
    main()
