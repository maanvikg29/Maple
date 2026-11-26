"""Builds the syrup van's home scene, whole and as layers. Run: python3 -I Scripts/art/build_van_art.py <output folder>"""

from . import outdoor, van
from .core import BG, Svg, poly

W, H = 1600, 2000


HOME_BOX = (0, -1120, 1600, 3460)


def home_layers():
    """The home view as layers, back to front. The sky is not drawn: the app paints it, edge to edge."""
    scene = Svg(W, H)
    outdoor.ground(scene)
    outdoor.trunk(scene)
    outdoor.canopy(scene)
    outdoor.string_lights(scene)
    outdoor.bunting(scene, to=van.chimney_top())
    van.shadow(scene)
    van.left_door(scene)
    van.workshop(scene, with_pip=False)
    van.cab_and_sill(scene)
    outdoor.crate(scene, -190, 236, -75, 150, 104, 80, "leaf-crate-1", 61)
    van.right_door(scene)
    van.wheels(scene)
    van.roof_load(scene, smoke=False)
    outdoor.basket(scene)
    outdoor.mushrooms(scene)
    outdoor.bench(scene)
    outdoor.logs(scene)
    outdoor.crate(scene, -50, 462, -75, 150, 110, 80, "leaf-crate-2", 67)
    outdoor.doormat(scene)

    smoke = Svg(W, H)
    van.chimney_smoke(smoke)
    leaves = Svg(W, H)
    outdoor.drifting_leaves(leaves)
    pip = Svg(W, H)
    van.pip_at_home(pip)
    return {"VanHomeScene": scene, "VanHomeSmoke": smoke, "VanHomeLeaves": leaves, "VanHomePip": pip}


def home_scene():
    """Everything in one drawing with its sky, for looking at outside the app."""
    s = Svg(W, H)
    s.begin("sky")
    s.fill(poly([(0, 0), (W, 0), (W, H), (0, H)]), BG)
    s.end()
    layers = home_layers()
    for name in ("VanHomeScene", "VanHomeSmoke", "VanHomePip", "VanHomeLeaves"):
        s.parts += layers[name].parts
    return s
