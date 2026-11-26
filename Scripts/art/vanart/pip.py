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
    """Pip standing, three-quarters to the right, as in the concept image. (ax, ay) is where the feet stand.

    The body's parts are separate groups (tail, body, head, arm) so later poses can move them.
    """
    m = Local(ax, ay, 490, 668, k, flip)
    w = lambda v: v * k  # noqa: E731
    s.begin(name)

    s.begin(f"{name}-tail")
    tail = [(360, 640), (280, 630), (228, 570), (200, 480), (192, 380), (206, 290), (248, 226), (306, 204), (356, 228),
            (378, 286), (366, 344), (350, 400), (360, 520)]
    s.add(smooth(m.pts(tail)), fill=PIP, sw=w(13))
    stripe = [(310, 606), (268, 530), (250, 430), (254, 340), (284, 276), (322, 272), (334, 306), (312, 326), (292, 310)]
    d = smooth(m.pts(stripe), close=False)
    s.add(d, stroke=OUT, sw=w(40))
    s.add(d, stroke=PEACH, sw=w(26))
    s.end()

    s.begin(f"{name}-body")
    body = [(395, 398), (346, 452), (322, 540), (334, 622), (400, 664), (500, 670), (586, 642), (624, 562), (616, 462),
            (580, 402), (480, 382)]
    s.add(smooth(m.pts(body)), fill=PIP, sw=w(13))
    for cx, cy, rx, ry in [(430, 668, 40, 21), (578, 642, 35, 19)]:
        c = m(cx, cy)
        s.add(ellipse(c[0], c[1], w(rx), w(ry)), fill=PIP, sw=w(12))
        for dx in (-10, 8):
            s.line([m(cx + dx, cy + 4), m(cx + dx + 2, cy + 17)], sw=w(7))
    c = m(526, 528)
    s.add(ellipse(c[0], c[1], w(80), w(110), -0.1 if not flip else 0.1), fill=PEACH, sw=w(10))
    c = m(538, 508)
    s.add(maple_leaf(c[0], c[1], w(58), 0.12 if not flip else -0.12), fill=LEAF_R, sw=w(8))
    s.line([m(540, 545), m(537, 480)], sw=w(5), opacity=0.6)
    s.line([m(539, 522), m(512, 500)], sw=w(4.5), opacity=0.55)
    s.line([m(539, 522), m(566, 498)], sw=w(4.5), opacity=0.55)
    # The near paw, resting on the belly.
    paw = [(442, 468), (424, 508), (444, 538), (472, 522), (470, 482)]
    s.add(smooth(m.pts(paw)), fill=PIP, sw=w(11))
    s.line([m(440, 520), m(448, 532)], sw=w(6))
    s.line([m(454, 524), m(460, 534)], sw=w(6))
    s.end()

    s.begin(f"{name}-head")
    for outer, inner in [([(404, 252), (396, 182), (420, 166), (458, 208)], [(414, 236), (410, 194), (424, 186), (442, 212)]),
                         ([(518, 196), (538, 158), (562, 162), (578, 208)], [(530, 196), (542, 174), (556, 176), (564, 200)])]:
        s.add(smooth(m.pts(outer), tension=0.7), fill=PIP, sw=w(12))
        s.add(smooth(m.pts(inner), tension=0.7), fill=PEACH, sw=w(6))
    head = [(384, 302), (394, 238), (440, 196), (500, 182), (560, 192), (606, 236), (620, 302), (600, 358), (540, 394),
            (470, 396), (410, 366)]
    s.add(smooth(m.pts(head)), fill=PIP, sw=w(13))
    mask = [(432, 318), (446, 288), (480, 276), (512, 292), (536, 306), (560, 278), (594, 280), (610, 314), (598, 360),
            (544, 386), (478, 386), (436, 358)]
    s.add(smooth(m.pts(mask)), fill=PEACH, sw=w(6))
    for cx, cy, rx, ry in [(488, 320, 12, 15), (572, 308, 11, 14)]:
        c = m(cx, cy)
        s.fill(ellipse(c[0], c[1], w(rx), w(ry)), BLACK)
        h = m(cx - 4, cy - 6)
        s.fill(ellipse(h[0], h[1], w(4), w(4.5)), WHITE)
    nose = m.pts([(536, 330), (556, 328), (547, 342)])
    s.add(smooth(nose, tension=0.6), fill=BLACK, sw=w(4))
    a, b, c2, d2, e = m(530, 350), m(538, 362), m(547, 351), m(556, 361), m(564, 347)
    s.add(f"M{f(a[0])} {f(a[1])} Q{f(b[0])} {f(b[1])} {f(c2[0])} {f(c2[1])} Q{f(d2[0])} {f(d2[1])} {f(e[0])} {f(e[1])}", sw=w(7))
    s.end()

    if ladle:
        s.begin(f"{name}-ladle")
        tube(s, m.pts([(628, 300), (640, 288), (652, 300), (654, 400), (660, 498)]), w(9), METAL, edge=w(5))
        c = m(694, 512)
        s.add(ellipse(c[0], c[1], w(42), w(24)), fill=METAL, sw=w(11))
        c = m(694, 506)
        s.add(ellipse(c[0], c[1], w(30), w(13)), fill=METAL_D, sw=w(6))
        s.end()

    s.begin(f"{name}-arm")
    arm = [(588, 432), (622, 398), (650, 392), (662, 410), (640, 440), (606, 474)]
    s.add(smooth(m.pts(arm)), fill=PIP, sw=w(12))
    s.line([m(648, 400), m(656, 412)], sw=w(6))
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
