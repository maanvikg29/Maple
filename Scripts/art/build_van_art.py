#!/usr/bin/env python3
"""Draws the syrup van art into the asset catalog. Usage: python3 -I Scripts/art/build_van_art.py [preview folder]

With a folder, it also writes the workshop whole (workshop-scene.svg) for looking at outside the app. Home and the
session's maple are not drawn here: they are the concept pictures, cut by Scripts/art/concept/build_concept_art.py.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from vanart import export, inside  # noqa: E402

repo = pathlib.Path(__file__).resolve().parents[2]
names = export.write_imagesets(repo / "App" / "Resources" / "Assets.xcassets")
print("image sets:", ", ".join(names))
if len(sys.argv) > 1:
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    (out / "workshop-scene.svg").write_text(inside.workshop_scene().text(viewbox=inside.BOX))
    print("previews in", out)
