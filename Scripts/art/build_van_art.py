#!/usr/bin/env python3
"""Draws the syrup van art. Usage: python3 -I Scripts/art/build_van_art.py <output folder>"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from vanart import build, inside  # noqa: E402

out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
(out / "home-scene.svg").write_text(build.home_scene().text())
(out / "workshop-scene.svg").write_text(inside.workshop_scene().text(viewbox=inside.BOX))
print("wrote", out / "home-scene.svg", "and workshop-scene.svg")
