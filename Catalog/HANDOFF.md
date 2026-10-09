# Maple leaf collection — handoff for Claude Code

This folder is the full set of real maple species for **Maple**, the digital wellbeing / sleep app (iPhone + Mac) where users collect maple leaves. Use it as the catalogue of collectible leaves.

Before changing anything, read the Maple project first and fit this data into the structures that already exist. Don't create a parallel system if the app already has a leaf or collectible model.

## What's in this folder

| Path | What it is |
|---|---|
| `species.json` | 155 living maple species (genus *Acer*), one object each. The source of truth. |
| `svg/autumn/acer-<id>.svg` | One drawn leaf per species in its autumn colour (155 files). |
| `svg/summer/acer-<id>.svg` | The same leaves in summer green (155 files). |
| `leaf-generator.js` | The JavaScript that drew the leaves from each species' traits. Reference for a native SwiftUI port. |
| `reference-atlas.html` | The finished catalogue page. Open it in a browser to see how every leaf looks. |

SVGs are 512×512, transparent background, plain hex colours, no CSS. They import into an Xcode asset catalogue as vector images (tick **Preserve Vector Data**, set **Scales** to Single Scale).

## species.json fields

```json
{
  "id": "palmatum",               // stable key; also the SVG filename: acer-palmatum.svg
  "name": "Acer palmatum",        // scientific name, show in italics
  "common": "Japanese maple",     // "" when the species has no English name
  "series": "Palmata",            // botanical group within Acer; "Unplaced" if none
  "range": "Japan, Korea, eastern China",
  "regions": ["EA"],              // see region codes below
  "form": "palmate",              // palmate | unlobed | trifoliate | pinnate | palmcompound
  "lobes": 7,                     // lobe count (palmate), or leaflet count for compound forms
  "depth": 0.75,                  // 0–1, how deep the lobes cut (palmate only)
  "margin": 2,                    // 0 smooth edge, 1 toothed, 2 double-toothed
  "evergreen": false,
  "autumn": "S",                  // R crimson, S scarlet, O orange, Y gold, G stays green
  "confidence": "k",              // see below
  "note": "Over a thousand named garden cultivars."   // "" for most species
}
```

**Region codes:** EA East Asia · HM Himalaya · SEA Southeast Asia · WA West & Central Asia · EU Europe · AF North Africa · NA North America · CA Mexico & Central America.

**Autumn hex values:** R `#b3312b`, S `#d2462a`, O `#d9782b`, Y `#d1a020`, G `#3f6d3b`. Summer greens vary slightly per species; take them from the summer SVGs if needed.

**confidence**
- `k` (89 species): leaf form, edge and autumn colour are documented.
- `i` (55): leaf shape follows the typical form of its series; the species itself is little studied.
- `u` (11): only the native range is confirmed; the leaf is a placeholder.

If the app ever shows facts about a leaf, show `i` and `u` leaves as approximate rather than presenting them as exact.

## Ideas that fit the app (decide with the user)

- Rarity could come from range size or `confidence` (the obscure species are naturally the rare finds), with famous ones like sugar maple and Japanese maple as early, easy unlocks.
- Leaves could turn from summer to autumn colour as a user keeps a streak.
- Evergreen species (24) stay green in both sets, which could make them a special category.

## Scope and sources

Living species only, from Kew's Plants of the World Online list. Named hybrids and ~70 fossil species are excluded. Sources: Plants of the World Online (Royal Botanic Gardens, Kew); Maple Society classification (Davis, 2021); Flora of China. The drawings are generated from each species' traits, not traced from photos.
