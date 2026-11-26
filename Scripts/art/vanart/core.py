"""Drawing helpers for the syrup van art: an SVG writer, the scene's 2:1 projection, and shape builders.

Every piece of the scene is drawn here in code, as its own named group, so it can be exported, placed and animated on
its own. The look follows docs/design/concepts/2026-11-26-syrup-workshop/syrup-van.jpg: thick dark outlines, flat warm
colours, many small objects.
"""

import math
import random

# The palette, sampled from the concept image.
OUT = "#3a1c0e"          # every outline
BG = "#ffddc2"
CREAM = "#f8e1b7"
CREAM_D = "#ecd09f"
CREAM_DD = "#dcbb88"
STRIPE = "#c75438"
STRIPE_D = "#a9432c"
WOOD = "#d69761"
WOOD_L = "#e4b07a"
WOOD_D = "#b9794a"
WOOD_DD = "#99603a"
PLANK = "#deb888"
PLANK_D = "#c99a66"
COPPER = "#c87445"
COPPER_L = "#e8a471"
COPPER_D = "#a8582f"
BRICK = "#c86a4a"
BRICK_D = "#a9523a"
RUG = "#b04539"
RUG_D = "#8f3229"
GOLD = "#eda04f"
GOLD_L = "#f6c16a"
PIP = "#bb543c"
PIP_D = "#a04530"
PEACH = "#f6b07e"
PEACH_L = "#fbd0a8"
CAT = "#9d887d"
CAT_D = "#84706a"
METAL = "#b9a898"
METAL_L = "#d6c9bc"
METAL_D = "#8f7f73"
IRON = "#5a4138"
IRON_D = "#43302a"
GLASS = "#cfe6e2"
GLASS_D = "#a9cbc8"
GRASS = "#a09f5f"
GRASS_D = "#86884c"
GRASS_L = "#b3b36f"
TRUNK = "#8f5434"
TRUNK_D = "#75422a"
TRUNK_L = "#a8693f"
CANOPY_L = "#f39a50"
CANOPY = "#ec8540"
CANOPY_D = "#dd6a31"
LEAF_R = "#c9552f"
LEAF_O = "#e8782f"
LEAF_Y = "#f2a84c"
PLANT = "#7d9a4e"
PLANT_D = "#5c7a3c"
PLANT_L = "#9db465"
TERRA = "#cf7347"
TERRA_D = "#ad5a34"
SYRUP = "#c9662a"
SYRUP_L = "#e59a45"
SYRUP_D = "#9b4a1f"
FIRE = "#fb7930"
FIRE_L = "#fdc35a"
GLOW = "#fde89e"
SMOKE = "#d9c7bb"
SMOKE_L = "#eadcd2"
WHITE = "#fff4e2"
BLACK = "#24120a"

# The projection. In the van's space x runs along the van (rear to cab), y across it toward the camera, z up.
# The camera looks down on the van from behind its near side: x goes up to the right, y down to the right.
CAM = dict(ox=215.0, oy=1480.0, ax=1.0, ay=-0.5, bx=1.0, by=0.5, zk=1.118)

HOME_CAMERA = dict(CAM)


def camera(turn, tilt, scale=1.15, ox=0.0, oy=0.0):
    """A camera facing the van's cut-away side. `turn` is how far it has swung round toward the rear (0 is straight
    on, 45 is the home view's turn) and `tilt` how far it looks down (0 is eye level, 90 is from above), in degrees.
    The van's rear bottom corner lands on (ox, oy). The drawing order suits turns from 0 to 45."""
    a, e = math.radians(turn), math.radians(tilt)
    return dict(ox=ox, oy=oy, ax=scale * math.cos(a), ay=-scale * math.sin(a) * math.sin(e), bx=scale * math.sin(a),
                by=scale * math.cos(a) * math.sin(e), zk=scale * math.cos(e))


class using:
    """Draw with another camera for a while: `with using(cam): ...`. The home camera comes back afterwards."""

    def __init__(self, cam):
        self.cam = cam

    def __enter__(self):
        self.before = dict(CAM)
        CAM.clear()
        CAM.update(self.cam)

    def __exit__(self, *exc):
        CAM.clear()
        CAM.update(self.before)


# The van was first drawn shorter. It is lengthened by stretching one slice of its length, between the stove and the
# boiler, so everything in front of the slice and behind it keeps its own numbers. Positions inside the new stretch of
# wall are given by `X`, which takes a length along the van as it now is.
STRETCH_FROM, STRETCH_TO, STRETCH_ADD = 356.0, 390.0, 170.0


def _along(x):
    if x <= STRETCH_FROM:
        return x
    if x >= STRETCH_TO:
        return x + STRETCH_ADD
    return STRETCH_FROM + (x - STRETCH_FROM) * (STRETCH_TO - STRETCH_FROM + STRETCH_ADD) / (STRETCH_TO - STRETCH_FROM)


def X(length):
    """The x to give `P` for a point `length` along the van as it now is."""
    if length <= STRETCH_FROM:
        return length
    if length >= STRETCH_TO + STRETCH_ADD:
        return length - STRETCH_ADD
    return STRETCH_FROM + (length - STRETCH_FROM) * (STRETCH_TO - STRETCH_FROM) / (STRETCH_TO - STRETCH_FROM + STRETCH_ADD)


def P(x, y, z=0.0):
    """A point in the van's space, on the page."""
    x = _along(x)
    return (CAM["ox"] + CAM["ax"] * x + CAM["bx"] * y, CAM["oy"] + CAM["ay"] * x + CAM["by"] * y - CAM["zk"] * z)


def f(v):
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def poly(pts, close=True):
    d = "M" + " L".join(f"{f(x)} {f(y)}" for x, y in pts)
    return d + (" Z" if close else "")


def smooth(pts, close=True, tension=1.0):
    """A smooth curve through the points (Catmull-Rom, written as cubic Béziers)."""
    n = len(pts)
    if n < 3:
        return poly(pts, close)
    d = f"M{f(pts[0][0])} {f(pts[0][1])}"
    last = n if close else n - 1
    for i in range(last):
        p0 = pts[(i - 1) % n] if (close or i > 0) else pts[0]
        p1 = pts[i % n]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (close or i + 2 < n) else pts[n - 1]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * tension, p1[1] + (p2[1] - p0[1]) / 6 * tension)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * tension, p2[1] - (p3[1] - p1[1]) / 6 * tension)
        d += f" C{f(c1[0])} {f(c1[1])} {f(c2[0])} {f(c2[1])} {f(p2[0])} {f(p2[1])}"
    return d + (" Z" if close else "")


def ellipse_pts(cx, cy, rx, ry, n=28, rot=0.0, a0=0.0, a1=math.tau):
    out = []
    for i in range(n + (0 if abs(a1 - a0 - math.tau) < 1e-6 else 1)):
        t = a0 + (a1 - a0) * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        out.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return out


def ellipse(cx, cy, rx, ry, rot=0.0):
    return smooth(ellipse_pts(cx, cy, rx, ry, 16, rot))


def ring3(cx, cy, z, r, n=32, a0=0.0, a1=math.tau):
    """A circle lying flat at height z, on the page."""
    full = abs(a1 - a0 - math.tau) < 1e-6
    return [P(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n), z)
            for i in range(n + (0 if full else 1))]


def wall_circle(plane, at, c1, c2, r, n=32):
    """A circle standing on a wall. plane 'x': the wall x = at, circle centre (y, z). plane 'y': wall y = at, (x, z)."""
    pts = []
    for i in range(n):
        t = math.tau * i / n
        a, b = c1 + r * math.cos(t), c2 + r * math.sin(t)
        pts.append(P(at, a, b) if plane == "x" else P(a, at, b))
    return pts


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


# A maple leaf, tip up, in a box of about -1...1.
_HALF = [(0, -1.0), (0.13, -0.66), (0.30, -0.74), (0.24, -0.30), (0.50, -0.50), (0.55, -0.37), (0.84, -0.44),
         (0.72, -0.14), (0.88, -0.05), (0.50, 0.24), (0.56, 0.40), (0.07, 0.30), (0.05, 0.36)]


def maple_leaf(cx, cy, size, rot=0.0, stem=True):
    """The outline of a maple leaf as a path. `size` is half its height."""
    right = list(_HALF)
    left = [(-x, y) for x, y in reversed(_HALF[:-1])][:-1]
    pts = right + ([(0.05, 0.78), (-0.05, 0.78)] if stem else []) + [(-0.05, 0.36)] + left
    c, s = math.cos(rot), math.sin(rot)
    return poly([(cx + (x * c - y * s) * size, cy + (x * s + y * c) * size) for x, y in pts])


class Svg:
    """Collects the drawing. Shapes go into named groups, one per piece of the scene."""

    def __init__(self, width, height):
        self.w, self.h = width, height
        self.parts = []
        self.depth = 0

    def begin(self, name, transform=None):
        extra = f' transform="{transform}"' if transform else ""
        self.parts.append(f'{"  " * self.depth}<g id="{name}"{extra}>')
        self.depth += 1

    def end(self):
        self.depth -= 1
        self.parts.append(f'{"  " * self.depth}</g>')

    def add(self, d, fill="none", stroke=OUT, sw=5.0, opacity=None, cap="round", rule=None, dash=None):
        a = [f'd="{d}"', f'fill="{fill}"']
        if stroke:
            a += [f'stroke="{stroke}"', f'stroke-width="{f(sw)}"', 'stroke-linejoin="round"', f'stroke-linecap="{cap}"']
        if opacity is not None:
            a.append(f'opacity="{opacity}"')
        if rule:
            a.append(f'fill-rule="{rule}"')
        if dash:
            a.append(f'stroke-dasharray="{dash}"')
        self.parts.append(f'{"  " * self.depth}<path {" ".join(a)}/>')

    def fill(self, d, fill, opacity=None, rule=None):
        self.add(d, fill=fill, stroke=None, opacity=opacity, rule=rule)

    def line(self, pts, sw=3.0, stroke=OUT, opacity=None, close=False):
        self.add(poly(pts, close), stroke=stroke, sw=sw, opacity=opacity)

    def curve(self, pts, sw=3.0, stroke=OUT, opacity=None):
        self.add(smooth(pts, close=False), stroke=stroke, sw=sw, opacity=opacity)

    def text(self, viewbox=None):
        x, y, w, h = viewbox or (0, 0, self.w, self.h)
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{f(x)} {f(y)} {f(w)} {f(h)}" '
                f'width="{f(w)}" height="{f(h)}">')
        return "\n".join([head] + self.parts + ["</svg>"]) + "\n"


# Solid shapes in the van's space. Only the three faces the camera sees are drawn: the top, the rear (-x) face and
# the near (+y) face.

def box(s, x, y, z, dx, dy, dz, top, rear, near, sw=4.0):
    s.add(poly([P(x, y, z), P(x, y + dy, z), P(x, y + dy, z + dz), P(x, y, z + dz)]), fill=rear, sw=sw)
    s.add(poly([P(x, y + dy, z), P(x + dx, y + dy, z), P(x + dx, y + dy, z + dz), P(x, y + dy, z + dz)]), fill=near, sw=sw)
    s.add(poly([P(x, y, z + dz), P(x + dx, y, z + dz), P(x + dx, y + dy, z + dz), P(x, y + dy, z + dz)]), fill=top, sw=sw)


def face_x(x, y0, y1, z0, z1):
    """A rectangle on the wall x = const (it faces the rear)."""
    return [P(x, y0, z0), P(x, y1, z0), P(x, y1, z1), P(x, y0, z1)]


def face_y(y, x0, x1, z0, z1):
    """A rectangle on the wall y = const (it faces the camera's right)."""
    return [P(x0, y, z0), P(x1, y, z0), P(x1, y, z1), P(x0, y, z1)]


def face_z(z, x0, x1, y0, y1):
    return [P(x0, y0, z), P(x1, y0, z), P(x1, y1, z), P(x0, y1, z)]


def hull(points):
    """The convex outline of a set of points."""
    pts = sorted(set((round(x, 2), round(y, 2)) for x, y in points))
    if len(pts) < 3:
        return pts

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (p[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(p)
        return out
    lower, upper = half(pts), half(reversed(pts))
    return lower[:-1] + upper[:-1]


def front_arc(ring):
    """The part of a flat ring nearest the camera, from its left end to its right end."""
    n = len(ring)
    lo = min(range(n), key=lambda i: ring[i][0])
    hi = max(range(n), key=lambda i: ring[i][0])
    a = [ring[(lo + k) % n] for k in range((hi - lo) % n + 1)]
    b = [ring[(lo - k) % n] for k in range((lo - hi) % n + 1)]
    return a if sum(p[1] for p in a) / len(a) > sum(p[1] for p in b) / len(b) else b


def cylinder(s, cx, cy, z, r, h, side, top, sw=4.0, shade=None, light=None):
    """An upright cylinder, under whichever camera is set. The side is drawn first, then the top."""
    lower, upper = ring3(cx, cy, z, r, 40), ring3(cx, cy, z + h, r, 40)
    outline = poly(hull(lower + upper))
    s.add(outline, fill=side, sw=sw)
    fl, fu = front_arc(lower), front_arc(upper)
    if shade:
        k = max(2, int(len(fl) * 0.3))
        s.fill(poly(fu[:k] + list(reversed(fl[:k]))), shade)
        s.add(outline, sw=sw)
    if light:
        a, b = fu[int(len(fu) * 0.8)], fl[int(len(fl) * 0.8)]
        s.line([(a[0], a[1] + 12), (b[0], b[1] - 12)], sw=6, stroke=light)
    s.add(smooth(upper), fill=top, sw=sw)


def rng(seed):
    return random.Random(seed)
