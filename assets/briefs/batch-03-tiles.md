# Asset Batch 03 — Tileset for the 2D world (fleet generation via ComfyUI/Flux on gpu)

Follow `style-guide.md`. **Entirely original** — invent our paper-and-ink world; do not imitate any existing game's tile art, motifs, or palette.

The world: **parchment islands floating in a sea of ink**, at night, seen from directly above (top-down, orthographic — no perspective).

Every tile must be **seamlessly tileable** (edges wrap), **512×512**, flat top-down, no drop shadows outside the tile bounds, no text, no characters.

1. `tile-parchment` — blank aged paper ground seen top-down. Warm off-white `#F2EBDD`, subtle fibre grain and faint foxing. Must tile seamlessly and read as calm, walkable ground.
2. `tile-ink` — the surrounding sea of ink. Deep ink navy `#171A26` shading to plum `#211C38`, with slow swirling darker currents and a few suspended flecks. Reads as deep, cold, not-walkable.
3. `tile-ruled-path` — a notebook ruled line running horizontally across parchment: one faint blue-grey rule on the paper ground, edge-to-edge so consecutive tiles form a continuous line.
4. `tile-margin-wall` — a solid block of graph-paper: pale grid squares on slightly greyer card stock, with a subtle raised bevel so it reads as an impassable wall from above.
5. `tile-letter` — a single blank parchment key-cap tile: a small rounded square of paper, very slightly raised, faint torn edge, centred in the tile with transparent-dark surround. The glyph is drawn by the app on top, so leave the face **empty**.
6. `tile-island-edge` — a torn-paper edge strip: parchment on the upper half, ragged fibrous tear, ink below. For rimming islands where paper meets ink.

Output to `assets/generated/batch-03/` with `<name>.provenance.md` sidecars, then cut/copy into `Sources/Vimkin/Content/tiles/` as `<name>.png`.
