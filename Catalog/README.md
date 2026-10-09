# Maple leaf catalogue (reference material)

Supplied by the product owner on 2026-10-10. See `HANDOFF.md` for the full description.

- **Source of truth:** `MapleKit/Sources/MapleCore/Resources/species.json` (155 living *Acer* species). Edit it there.
- `leaf-generator.js` is the original drawing code. The app draws leaves natively with a Swift port (`MapleDesign`), so any species can be drawn in any colour and size.
- `svg/summer`, `svg/autumn` are the generator's exports, kept as visual references for checking the Swift port. Known issue: every summer SVG has an invalid stroke value (`#xxxxxx 55%, #000)`), left over from a CSS `color-mix` conversion.
- `reference-atlas.html` is the catalogue page (it loads Google Fonts).
