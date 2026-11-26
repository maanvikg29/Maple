"""The workshop, zoomed in: the same van seen from the front, almost straight on, with both rear doors shut and the room
across the middle of a phone-shaped canvas.

The room is not redrawn for this view. It is `van.workshop`, the room the home scene shows, under another camera, so
whatever stands in the van stands in both pictures. Only the garden round it is drawn here, because the home scene's
garden is a flat picture made for the home camera.
"""

from . import outdoor, van
from .core import *  # noqa: F401,F403
from .pip import pip

# The canvas: a phone's shape (6:13). Its corner is (0, 0), so the app's numbers are the drawing's own.
WIDTH, HEIGHT = 900, 1950
BOX = (0, 0, WIDTH, HEIGHT)

# The camera stands in front of the cut-away side, turned a little toward the rear doors and looking slightly down:
# between a flat dollhouse view and one that shows the window wall (the owner chose between those two).
CAMERA = camera(turn=6, tilt=13.5, ox=35.0, oy=1150.0)

PIP_STANDS = (480.0, 290.0)  # length along the van as drawn, and how far across


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
    for cx, cy, rx, ry in [(560, 1500, 170, 28), (200, 1590, 150, 30), (640, 1700, 210, 34), (230, 1830, 170, 30),
                           (720, 1870, 170, 30)]:
        s.fill(ellipse(cx, cy, rx, ry), GRASS_L, opacity=0.55)
    s.end()
    # A path of stones from the rear doors, round to the front and off the bottom.
    outdoor.stones(s, [(118, 1392, 56, 16, 0.05), (228, 1448, 60, 17, 0.08), (338, 1520, 66, 19, 0.06),
                       (420, 1606, 72, 21, 0.03), (458, 1702, 78, 23, -0.02), (446, 1806, 84, 25, -0.04),
                       (470, 1912, 90, 27, 0.02)])
    s.begin("lawn-tufts")
    outdoor.tufts(s, [(40, 1470), (330, 1420), (540, 1440), (640, 1560), (300, 1640), (60, 1560), (850, 1560),
                      (620, 1790), (310, 1760), (260, 1900), (640, 1900), (860, 1840), (560, 1640), (40, 1930)], 23)
    r = rng(29)
    cols = [LEAF_R, LEAF_O, LEAF_Y]
    for i, (x, y) in enumerate([(430, 1470), (590, 1600), (270, 1560), (700, 1760), (330, 1850), (590, 1850), (250, 1720),
                                (840, 1920)]):
        outdoor.leaf(s, x, y, r.uniform(19, 26), r.uniform(-1.4, 1.4), cols[i % 3], sw=3)
    s.end()
    # A bench and the firewood on one side; a crate of gathered leaves and its mushrooms on the other.
    # (The bench is drawn clear of the van's lengthened slice, then slid along to its place.)
    s.begin("bench-place", transform="translate(404 0)")
    outdoor.bench(s, x=120, y=700, z=van.G + 9)
    s.end()
    outdoor.log_stack(s, 792, 1690)
    outdoor.crate(s, -170, 1560, van.G + 9, 130, 150, 80, "leaf-crate", 67)
    outdoor.mushrooms(s, cx=226, cy=1762)
    s.begin("leaves-in-the-air")
    outdoor.leaf(s, 842, 150, 30, 0.5, LEAF_Y)
    outdoor.small_leaf(s, 640, 330, 22, -0.9, LEAF_O)
    outdoor.small_leaf(s, 560, 560, 18, 0.7, LEAF_Y)
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
