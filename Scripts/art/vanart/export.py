"""Writes the app's image sets: one SVG per layer, with the catalog's Contents.json beside it."""

import json
import pathlib

from . import build, inside


def write_imagesets(catalog: pathlib.Path):
    folder = catalog / "Van"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    written = []
    for layers, box in ((build.home_layers(), build.HOME_BOX), (inside.workshop_layers()[0], inside.BOX)):
        for name, drawing in layers.items():
            imageset = folder / f"{name}.imageset"
            imageset.mkdir(exist_ok=True)
            (imageset / f"{name}.svg").write_text(drawing.text(viewbox=box))
            contents = {
                "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
                "properties": {"preserves-vector-representation": True, "template-rendering-intent": "original"},
            }
            (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
            written.append(name)
    return written
