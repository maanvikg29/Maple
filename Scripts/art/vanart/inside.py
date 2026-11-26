"""The workshop, zoomed in: the same van from the same side as the home scene, with both rear doors shut and the room
in the middle of a phone-shaped canvas.

Nothing is redrawn for this view. It is the home scene's own van and garden, framed closer, so the two pictures agree.
"""

from . import outdoor, van
from .core import *  # noqa: F401,F403

# The canvas, in the home scene's own coordinates: a phone's shape (6:13), centred on the room.
BOX = (150, -80, 1140, 2470)


def _canvas():
    return Svg(BOX[2], BOX[3])


def lawn(s):
    """The grass, running off the bottom of the canvas: close in, the garden is not an island."""
    x0, y0, w, h = BOX
    left, right, bottom = x0 - 60, x0 + w + 60, y0 + h + 60
    s.begin("lawn")
    top = [(left, 1500), (120, 1370), (330, 1290), (640, 1250), (980, 1190), (right, 1110)]
    s.add(smooth(top + [(right, bottom), (left, bottom)], tension=0.6), fill=GRASS, sw=5)
    for cx, cy, rx, ry in [(250, 1650, 120, 40), (700, 1800, 170, 34), (1120, 1960, 190, 44), (420, 2090, 210, 46),
                           (900, 2260, 230, 44), (300, 2330, 150, 34)]:
        s.fill(ellipse(cx, cy, rx, ry), GRASS_L, opacity=0.55)
    # Stepping stones down from the van.
    for cx, cy, rx, ry, rot in [(900, 1950, 62, 26, -0.12), (790, 2040, 68, 28, 0.1), (830, 2150, 72, 30, -0.08),
                                (720, 2250, 76, 31, 0.12), (780, 2360, 80, 32, -0.05)]:
        s.add(ellipse(cx, cy + 7, rx, ry, rot), fill=METAL_D, sw=4)
        s.add(ellipse(cx, cy, rx, ry, rot), fill=METAL_L, sw=4)
        s.line([(cx - rx * 0.4, cy - 4), (cx - rx * 0.1, cy + 3)], sw=2.5, opacity=0.4)
    r = rng(23)
    tufts = [(190, 1770), (420, 1790), (980, 1800), (1130, 1740), (640, 1840), (1230, 1880), (230, 1900), (520, 1960),
             (1010, 2040), (330, 2180), (1180, 2150), (540, 2300), (980, 2330), (220, 2040), (880, 2180), (1240, 2310),
             (430, 2360), (1100, 1610)]
    for x, y in tufts:
        k = r.uniform(0.8, 1.25)
        s.line([(x - 9 * k, y), (x - 12 * k, y - 15 * k)], sw=3)
        s.line([(x, y), (x + 1 * k, y - 20 * k)], sw=3)
        s.line([(x + 9 * k, y), (x + 13 * k, y - 13 * k)], sw=3)
    cols = [LEAF_R, LEAF_O, LEAF_Y]
    for i, (x, y) in enumerate([(300, 1990), (1150, 2060), (520, 2150), (960, 1930), (1060, 2250), (250, 2250),
                                (640, 2060), (420, 2260), (1210, 1790)]):
        outdoor.leaf(s, x, y, r.uniform(20, 27), r.uniform(-1.4, 1.4), cols[i % 3], sw=3)
    s.end()
    outdoor.mushrooms(s, cx=1150, cy=2190)


def workshop_layers():
    """The layers the app stacks, and where its buttons go (in this drawing's coordinates)."""
    room = _canvas()
    lawn(room)
    outdoor.trunk(room)
    outdoor.canopy(room)
    outdoor.string_lights(room)
    outdoor.bunting(room, to=van.chimney_top())
    van.shadow(room)
    van.workshop(room, with_pip=False, steam=False)
    van.cab_and_sill(room)
    van.rear_closed(room)
    van.wheels(room)
    van.roof_load(room, smoke=False)
    outdoor.basket(room)
    outdoor.mushrooms(room)
    outdoor.bench(room)
    outdoor.logs(room)
    outdoor.crate(room, -50, 462, -75, 150, 110, 80, "leaf-crate-2", 67)

    steam = _canvas()
    van.pot_steam(steam)
    smoke = _canvas()
    van.chimney_smoke(smoke)
    pip = _canvas()
    van.pip_at_home(pip)
    marks = {
        "gauge": P(430, 106, van.F + 172),
        "pot": P(288, 86, van.F + 150),
        "logbook": P(490, 226, van.F + 89),
        "basket": P(116, 246, van.F + 30),
    }
    return {"VanWorkshopRoom": room, "VanWorkshopSteam": steam, "VanWorkshopSmoke": smoke, "VanWorkshopPip": pip}, marks


def workshop_scene():
    """Everything in one drawing with its sky, for looking at outside the app."""
    layers, _ = workshop_layers()
    s = _canvas()
    s.begin("sky")
    x, y, w, h = BOX
    s.fill(poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)]), BG)
    s.end()
    for name in ("VanWorkshopRoom", "VanWorkshopSteam", "VanWorkshopSmoke", "VanWorkshopPip"):
        s.parts += layers[name].parts
    return s
