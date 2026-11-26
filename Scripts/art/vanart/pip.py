"""Pip the squirrel, and the cat. Drawn flat, in their own coordinates, and placed by their feet."""

import math

from .core import *  # noqa: F401,F403


class Local:
    """Maps a character's own coordinates onto the page: (ox, oy) in local units lands on (ax, ay)."""

    def __init__(self, ax, ay, ox, oy, k, flip=False):
        self.ax, self.ay, self.ox, self.oy, self.k, self.flip = ax, ay, ox, oy, k, flip

    def __call__(self, x, y):
        dx = (x - self.ox) * self.k
        return (self.ax - dx if self.flip else self.ax + dx, self.ay + (y - self.oy) * self.k)

    def pts(self, pts):
        return [self(x, y) for x, y in pts]


def tube(s, pts, w, colour, edge=4.0, smooth_it=True):
    """A thick line with an outline: handles, pipes, tails."""
    d = smooth(pts, close=False) if smooth_it else poly(pts, close=False)
    s.add(d, stroke=OUT, sw=w + edge * 2)
    s.add(d, stroke=colour, sw=w)


def pip(s, ax, ay, k=0.43, ladle=True, name="pip", flip=False):
    """Pip standing, three-quarters to the right, traced from the concept image (pip-from-van.jpg, in its own pixels).
    (ax, ay) is where the feet stand.

    The body's parts are separate groups (tail, body, head, arm) so later poses can move them.
    """
    m = Local(ax, ay, 500, 668, k, flip)
    w = lambda v: v * k  # noqa: E731
    line = w(8)
    s.begin(name)

    s.begin(f"{name}-tail")
    tail = [(333, 640), (273, 610), (233, 535), (213, 440), (216, 340), (243, 267), (296, 227), (353, 224), (389, 253),
            (396, 300), (382, 350), (362, 430), (352, 535)]
    s.add(smooth(m.pts(tail)), fill=PIP, sw=line)
    # The peach inside: a stripe up the tail that ends in a curl.
    stripe = [(308, 606), (273, 533), (254, 440), (252, 360), (267, 300), (302, 268), (340, 277), (353, 313), (336, 345),
              (304, 347), (288, 322), (301, 303)]
    d = smooth(m.pts(stripe), close=False)
    s.add(d, stroke=OUT, sw=w(25) + line * 1.5)
    s.add(d, stroke=PEACH, sw=w(25))
    s.end()

    s.begin(f"{name}-body")
    body = [(378, 400), (346, 453), (322, 533), (326, 600), (360, 648), (440, 668), (533, 658), (596, 630), (620, 560),
            (616, 467), (606, 404), (490, 380)]
    s.add(smooth(m.pts(body)), fill=PIP, sw=line)
    for cx, cy, rx, ry in [(437, 664, 36, 18), (568, 630, 31, 16)]:
        c = m(cx, cy)
        s.add(ellipse(c[0], c[1], w(rx), w(ry)), fill=PIP, sw=line)
        for dx in (-9, 8):
            s.line([m(cx + dx, cy + 3), m(cx + dx + 2, cy + 15)], sw=w(5))
    c = m(540, 518)
    s.add(ellipse(c[0], c[1], w(68), w(112), -0.06 if not flip else 0.06), fill=PEACH, sw=w(6))
    c = m(548, 508)
    s.add(maple_leaf(c[0], c[1], w(56), 0.1 if not flip else -0.1), fill=LEAF_R, sw=w(5))
    s.line([m(546, 540), m(543, 480)], sw=w(3.5), opacity=0.55)
    s.line([m(545, 520), m(520, 500)], sw=w(3), opacity=0.5)
    s.line([m(545, 520), m(570, 498)], sw=w(3), opacity=0.5)
    # The near paw, resting on the belly.
    paw = [(424, 464), (416, 504), (435, 531), (464, 520), (467, 480)]
    s.add(smooth(m.pts(paw)), fill=PIP, sw=line)
    s.line([m(432, 514), m(440, 526)], sw=w(5))
    s.line([m(446, 518), m(452, 528)], sw=w(5))
    s.end()

    s.begin(f"{name}-head")
    for outer, inner in [([(410, 250), (417, 182), (432, 177), (464, 214)], [(421, 238), (425, 197), (433, 194), (449, 217)]),
                         ([(512, 206), (530, 166), (543, 163), (569, 220)], [(524, 204), (534, 179), (542, 177), (557, 208)])]:
        s.add(smooth(m.pts(outer), tension=0.6), fill=PIP, sw=line)
        s.add(smooth(m.pts(inner), tension=0.6), fill=PEACH, sw=w(5))
    head = [(376, 350), (384, 287), (406, 240), (447, 211), (500, 200), (549, 207), (588, 237), (608, 287), (614, 348),
            (598, 390), (540, 410), (462, 410), (398, 394)]
    s.add(smooth(m.pts(head)), fill=PIP, sw=line)
    # The peach face: a patch round each eye and a broad muzzle, drawn as one shape.
    patches = [(486, 324, 37, 30, -0.25), (568, 309, 33, 28, 0.2), (527, 360, 87, 43, -0.07)]
    for cx, cy, rx, ry, rot in patches:
        c = m(cx, cy)
        s.add(ellipse(c[0], c[1], w(rx), w(ry), rot if not flip else -rot), fill=PEACH, sw=w(4))
    for cx, cy, rx, ry, rot in patches:
        c = m(cx, cy)
        s.fill(ellipse(c[0], c[1], w(rx) - w(2), w(ry) - w(2), rot if not flip else -rot), PEACH)
    for cx, cy, rx, ry in [(491, 320, 12, 15), (565, 304, 11, 14)]:
        c = m(cx, cy)
        s.fill(ellipse(c[0], c[1], w(rx), w(ry)), BLACK)
        h = m(cx - 3, cy - 5)
        s.fill(ellipse(h[0], h[1], w(3.5), w(4)), WHITE)
    nose = m.pts([(540, 331), (558, 329), (549, 341)])
    s.add(smooth(nose, tension=0.6), fill=BLACK, sw=w(3))
    a, b, c2, d2, e = m(532, 351), m(539, 362), m(549, 352), m(557, 361), m(564, 348)
    s.add(f"M{f(a[0])} {f(a[1])} Q{f(b[0])} {f(b[1])} {f(c2[0])} {f(c2[1])} Q{f(d2[0])} {f(d2[1])} {f(e[0])} {f(e[1])}", sw=w(5))
    s.end()

    if ladle:
        s.begin(f"{name}-ladle")
        tube(s, m.pts([(616, 306), (626, 293), (637, 305), (641, 400), (656, 520)]), w(8), METAL, edge=w(4))
        c = m(693, 523)
        s.add(ellipse(c[0], c[1], w(38), w(23)), fill=METAL, sw=line)
        c = m(693, 518)
        s.add(ellipse(c[0], c[1], w(27), w(12)), fill=METAL_D, sw=w(5))
        s.end()

    s.begin(f"{name}-arm")
    arm = [(576, 402), (603, 385), (628, 389), (634, 411), (612, 430), (584, 442)]
    s.add(smooth(m.pts(arm)), fill=PIP, sw=line)
    s.line([m(620, 395), m(628, 407)], sw=w(5))
    s.end()

    s.end()


def cat(s, ax, ay, k=1.0, name="cat"):
    """A grey cat asleep, curled up. (ax, ay) is the middle of where it lies."""
    m = Local(ax, ay, 0, 0, k)
    w = lambda v: v * k  # noqa: E731
    s.begin(name)
    body = [(-78, 6), (-66, -30), (-20, -52), (40, -48), (78, -18), (76, 20), (30, 38), (-40, 36)]
    s.add(smooth(m.pts(body)), fill=CAT, sw=w(5))
    for pts in [[(-6, -48), (2, -30)], [(22, -50), (28, -32)], [(48, -42), (50, -26)]]:
        s.line(m.pts(pts), sw=w(4), stroke=CAT_D)
    # The tail, wrapped round the front.
    d = smooth(m.pts([(74, 8), (60, 34), (10, 44), (-30, 40)]), close=False)
    s.add(d, stroke=OUT, sw=w(24))
    s.add(d, stroke=CAT, sw=w(15))
    # Head.
    for ear in [[(-78, -18), (-84, -46), (-58, -34)], [(-44, -34), (-30, -56), (-22, -26)]]:
        s.add(poly(m.pts(ear)), fill=CAT, sw=w(5))
    for ear in [[(-76, -24), (-79, -38), (-65, -32)], [(-40, -34), (-32, -46), (-27, -30)]]:
        s.fill(poly(m.pts(ear)), PEACH)
    head = [(-86, 2), (-80, -24), (-52, -36), (-24, -24), (-18, 4), (-34, 24), (-66, 24)]
    s.add(smooth(m.pts(head)), fill=CAT, sw=w(5))
    for x in (-66, -40):
        a, b, c = m(x - 8, -4), m(x, 4), m(x + 8, -4)
        s.add(f"M{f(a[0])} {f(a[1])} Q{f(b[0])} {f(b[1])} {f(c[0])} {f(c[1])}", sw=w(3.5))
    s.fill(poly(m.pts([(-56, 6), (-50, 6), (-53, 11)])), PIP)
    a, b, c, d3, e = m(-60, 12), m(-56, 17), m(-53, 12), m(-50, 17), m(-46, 12)
    s.add(f"M{f(a[0])} {f(a[1])} Q{f(b[0])} {f(b[1])} {f(c[0])} {f(c[1])} Q{f(d3[0])} {f(d3[1])} {f(e[0])} {f(e[1])}", sw=w(3))
    for y in (6, 12):
        s.line([m(-80, y), m(-96, y - 3)], sw=w(2.2))
        s.line([m(-26, y), m(-10, y - 3)], sw=w(2.2))
    s.end()
