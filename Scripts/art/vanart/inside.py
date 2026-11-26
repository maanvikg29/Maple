"""The workshop, zoomed in: the same van seen from the front, straight on and at eye level, like a dollhouse, with the
room across the middle of a phone-shaped canvas.

The room is not redrawn for this view. It is `van.workshop`, the room the home scene shows, under another camera, so
whatever stands in the van stands in both pictures. Only the garden round it is drawn here, because the home scene's
garden is a flat picture made for the home camera.
"""

from . import outdoor, van
from .core import *  # noqa: F401,F403
from .pip import pip

# The canvas: a phone's shape (6:13). Its corner is (0, 0), so the app's numbers are the drawing's own.
WIDTH, HEIGHT = 852, 1846
BOX = (0, 0, WIDTH, HEIGHT)

# The camera stands straight in front of the cut-away side, at eye level: the floor is a thin strip and the walls at
# either end are edge-on. (The owner chose this from five front views.)
CAMERA = camera(turn=0, tilt=6, ox=30.0, oy=1122.0)
# The grass in front is nearer and lower than the room, so it is seen from a little more above.
GROUND = camera(turn=0, tilt=14, ox=30.0, oy=1061.0)

PIP_STANDS = (500.0, 290.0)  # length along the van as drawn, and how far across


def _canvas():
    return Svg(WIDTH, HEIGHT)


def backdrop(s):
    """The sky, the lawn to the bottom of the canvas, and the maple behind the van."""
    s.begin("sky")
    s.fill(poly([(0, 0), (WIDTH, 0), (WIDTH, HEIGHT), (0, HEIGHT)]), BG)
    s.end()
    s.begin("lawn")
    far = P(van.LC / 2, -560, van.G)[1]
    top = [(-60, far + 24), (WIDTH * 0.25, far + 4), (WIDTH * 0.55, far - 8), (WIDTH * 0.8, far + 2), (WIDTH + 60, far + 20)]
    s.add(smooth(top + [(WIDTH + 60, HEIGHT + 60), (-60, HEIGHT + 60)], tension=0.6), fill=GRASS, sw=5)
    s.end()
    # The maple is the home scene's own drawing, moved so that its foot stands behind the van's rear corner.
    foot = P(60, -230, van.G)
    dx, dy = foot[0] - 330, foot[1] - 1400
    s.begin("maple", transform=f"translate({f(dx)} {f(dy)})")
    outdoor.trunk(s)
    outdoor.canopy(s)
    tie = van.chimney_top()
    outdoor.bunting(s, to=(tie[0] - dx, tie[1] - dy))
    s.end()


def garden(s):
    """The grass in front of the van, where the canvas runs on below it."""
    s.begin("lawn-patches")
    for cx, cy, rx, ry in [(530, 1413, 160, 26), (189, 1500, 142, 28), (606, 1605, 200, 32), (218, 1731, 160, 28),
                           (682, 1769, 160, 28)]:
        s.fill(ellipse(cx, cy, rx, ry), GRASS_L, opacity=0.55)
    s.end()
    # A path of stones from the rear doors, round to the front and off the bottom.
    outdoor.stones(s, [(112, 1309, 53, 15, 0.05), (216, 1363, 57, 16, 0.08), (320, 1432, 62, 18, 0.06),
                       (398, 1515, 68, 20, 0.03), (434, 1607, 74, 22, -0.02), (422, 1707, 80, 24, -0.04),
                       (445, 1809, 85, 26, 0.02)])
    s.begin("lawn-tufts")
    outdoor.tufts(s, [(38, 1384), (312, 1336), (511, 1355), (606, 1471), (284, 1548), (57, 1471), (805, 1471), (587, 1692),
                      (293, 1663), (246, 1798), (606, 1798), (814, 1740), (530, 1548), (38, 1827)], 23)
    r = rng(29)
    cols = [LEAF_R, LEAF_O, LEAF_Y]
    for i, (x, y) in enumerate([(407, 1384), (559, 1509), (256, 1471), (663, 1663), (312, 1750), (559, 1750), (237, 1625),
                                (795, 1817)]):
        outdoor.leaf(s, x, y, r.uniform(19, 26), r.uniform(-1.4, 1.4), cols[i % 3], sw=3)
    s.end()
    # A bench and the firewood on one side; a crate of gathered leaves and its mushrooms on the other.
    with using(GROUND):
        # (The bench is drawn clear of the van's lengthened slice, then slid along to its place.)
        s.begin("bench-place", transform="translate(437 0)")
        outdoor.bench(s, x=120, y=625, z=van.G + 9)
        s.end()
        outdoor.crate(s, -2, 1472, van.G + 9, 130, 150, 80, "leaf-crate", 67)
    outdoor.log_stack(s, 750, 1596)
    outdoor.mushrooms(s, cx=214, cy=1665)
    s.begin("leaves-in-the-air")
    outdoor.leaf(s, 797, 145, 30, 0.5, LEAF_Y)
    outdoor.small_leaf(s, 606, 320, 22, -0.9, LEAF_O)
    outdoor.small_leaf(s, 530, 543, 18, 0.7, LEAF_Y)
    s.end()


def workshop_layers():
    """The layers the app stacks, and where its buttons go (in this drawing's coordinates)."""
    with using(CAMERA):
        room = _canvas()
        backdrop(room)
        van.shadow(room)
        van.workshop(room, with_pip=False, steam=False)
        van.cab_and_sill(room)
        van.rear_closed(room)
        van.wheels(room)
        van.roof_load(room, smoke=False)
        garden(room)

        steam = _canvas()
        van.pot_steam(steam)
        smoke = _canvas()
        van.chimney_smoke(smoke)
        character = _canvas()
        c = P(X(PIP_STANDS[0]), PIP_STANDS[1], van.F)
        pip(character, c[0], c[1] + 2, 0.52)
        top = van.F + 107
        marks = {
            "gauge": P(430, 106, van.F + 172),
            "pot": P(288, 86, van.F + 150),
            "logbook": P(van.LOGBOOK[0], van.LOGBOOK[1], top + 18),
            "basket": P(116, 246, van.F + 30),
        }
    return {"VanWorkshopRoom": room, "VanWorkshopSteam": steam, "VanWorkshopSmoke": smoke, "VanWorkshopPip": character}, marks


def workshop_scene():
    """Everything in one drawing, for looking at outside the app."""
    layers, _ = workshop_layers()
    s = _canvas()
    for name in ("VanWorkshopRoom", "VanWorkshopSteam", "VanWorkshopSmoke", "VanWorkshopPip"):
        s.parts += layers[name].parts
    return s
