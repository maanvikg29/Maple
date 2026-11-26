"""The workshop: the same van and the same pieces, with the camera turned to face the cut-away side.

Nothing is redrawn by hand for this view. The van is built in its own space (x along it, y across, z up), so setting
the side camera turns every wall, shelf and machine at once; the flat pieces (Pip, the cat, bottles, plants) stand
where their feet are. The tall canvas leaves room above for the maple and below for the grass.
"""

from . import outdoor, van
from .core import *  # noqa: F401,F403

# The canvas: a phone's shape, with the workshop filling its width.
BOX = (-20, -905, 680, 1473)


def backdrop(s):
    s.begin("side-tree", transform="translate(-480 -1290)")
    outdoor.trunk(s)
    outdoor.canopy(s)
    s.end()
    s.begin("side-ground")
    top = [(-100, 96), (60, 80), (260, 58), (460, 44), (640, 30), (800, 22)]
    s.add(smooth(top + [(800, 760), (-100, 760)], tension=0.6), fill=GRASS, sw=5)
    for cx, cy, rx, ry in [(120, 420, 150, 40), (560, 520, 170, 44), (320, 620, 200, 36)]:
        s.fill(ellipse(cx, cy, rx, ry), GRASS_L, opacity=0.5)
    r = rng(17)
    for x, y in [(-30, 330), (80, 500), (250, 560), (430, 430), (600, 400), (660, 600), (150, 640), (520, 650), (360, 480)]:
        k = r.uniform(0.9, 1.3)
        s.line([(x - 9 * k, y), (x - 12 * k, y - 15 * k)], sw=3)
        s.line([(x, y), (x + 1 * k, y - 20 * k)], sw=3)
        s.line([(x + 9 * k, y), (x + 13 * k, y - 13 * k)], sw=3)
    s.end()


def workshop_layers():
    set_camera(SIDE_CAMERA)
    try:
        room = Svg(BOX[2], BOX[3])
        backdrop(room)
        van.shadow(room)
        van.left_door(room)
        van.workshop(room, with_pip=False, steam=False)
        van.cab_and_sill(room)
        van.wheels(room)
        van.roof_load(room, smoke=False)
        outdoor.crate(room, 30, 440, -84, 150, 110, 80, "side-leaf-crate", 67)

        steam = Svg(BOX[2], BOX[3])
        van.pot_steam(steam)
        smoke = Svg(BOX[2], BOX[3])
        van.chimney_smoke(smoke)
        pip = Svg(BOX[2], BOX[3])
        van.pip_in_workshop(pip)
        # Where the app puts its buttons, in this drawing's own coordinates.
        marks = {
            "gauge": P(430, 106, van.F + 172),
            "pot": P(288, 86, van.F + 150),
            "logbook": P(490, 226, van.F + 107 - 18),
            "basket": P(60, 232, van.F + 30),
        }
    finally:
        set_camera(HOME_CAMERA)
    return {"VanWorkshopRoom": room, "VanWorkshopSteam": steam, "VanWorkshopSmoke": smoke, "VanWorkshopPip": pip}, marks


def workshop_scene():
    """Everything in one drawing with its sky, for looking at outside the app."""
    layers, _ = workshop_layers()
    s = Svg(BOX[2], BOX[3])
    s.begin("sky")
    s.fill(poly([(BOX[0], BOX[1]), (BOX[0] + BOX[2], BOX[1]), (BOX[0] + BOX[2], BOX[1] + BOX[3]), (BOX[0], BOX[1] + BOX[3])]), BG)
    s.end()
    for name in ("VanWorkshopRoom", "VanWorkshopSteam", "VanWorkshopSmoke", "VanWorkshopPip"):
        s.parts += layers[name].parts
    return s
