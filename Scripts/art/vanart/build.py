"""Builds the syrup van's home scene as one SVG. Run: python3 -I Scripts/art/build_van_art.py <output folder>"""

from . import outdoor, van
from .core import BG, Svg, poly

W, H = 1600, 2000


def home_scene():
    s = Svg(W, H)
    s.begin("sky")
    s.fill(poly([(0, 0), (W, 0), (W, H), (0, H)]), BG)
    s.end()
    outdoor.ground(s)
    outdoor.trunk(s)
    outdoor.canopy(s)
    outdoor.string_lights(s)
    outdoor.bunting(s, to=van.chimney_top())
    van.shadow(s)
    van.left_door(s)
    van.workshop(s)
    van.cab_and_sill(s)
    outdoor.crate(s, -190, 236, -75, 150, 104, 80, "leaf-crate-1", 61)
    van.right_door(s)
    van.wheels(s)
    van.roof_load(s)
    outdoor.basket(s)
    outdoor.mushrooms(s)
    outdoor.bench(s)
    outdoor.logs(s)
    outdoor.crate(s, -50, 462, -75, 150, 110, 80, "leaf-crate-2", 67)
    outdoor.doormat(s)
    outdoor.drifting_leaves(s)
    return s
