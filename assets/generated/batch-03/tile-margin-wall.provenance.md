# Provenance — tile-margin-wall

- **Asset:** `tile-margin-wall.png` (from master `tile-margin-wall-rr1.png`)
- **Date:** 2026-08-11
- **Generator:** local ComfyUI 0.28.0 on `gpu.home.arcs.internal` (NVIDIA RTX 5090)
- **Pipeline:** ComfyUI HTTP API (`POST /prompt`), Flux.2 text-to-image graph
- **Diffusion model:** `flux2_dev_fp8mixed.safetensors` (FLUX.2-dev, fp8 mixed)
- **Text encoder:** `mistral_3_small_flux2_fp4_mixed.safetensors` (CLIPLoader type `flux2`)
- **VAE:** `flux2-vae.safetensors`
- **Sampler:** euler (`KSamplerSelect`) / `Flux2Scheduler`, 28 steps
- **Guidance:** 4.0 (`FluxGuidance`)
- **Master resolution:** 1024x1024 PNG; shipped tile downscaled to 512x512 with `sips -z 512 512`
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-03-tiles.md`
- **Originality:** prompts describe our own parchment-and-ink world only. No existing game, franchise,
  tileset, artist or named style was referenced, imitated or used as input.
- **Seed:** 410004

**Iteration:** Re-rolled once. The first attempt (seed 310004) took the brief's "subtle raised
bevel" literally and built a large recessed tray — a deep inset panel with visibly receding
3D side walls. That is disqualifying perspective, and the surrounding frame meant the tile
could not repeat at all. The prompt was hardened to forbid every form of that reading
(no recessed box, tray, inset panel, rim, side walls, visible thickness, bevel, chamfer, depth).

**Known deviation from brief (deliberate):** the shipped tile therefore has NO bevel. It is a
flat, full-bleed, seamlessly tiling graph-paper card surface. Every attempt to render the
bevel produced perspective, which the brief forbids outright; tileability was treated as the
higher requirement. The "impassable wall" read now comes from the cool grey card stock
contrasting against the warm parchment ground rather than from rendered relief. If a raised
edge is wanted, it is better added by the renderer as a drawn inset border than baked in.

## Prompt

```
Seamless full-bleed top-down tile texture of graph paper card stock seen from directly above. A regular even grid of small pale blue-grey squares printed on slightly greyer, cooler-toned heavy card stock. The grid covers the ENTIRE square image completely, edge to edge to edge to edge, with the same uniform grid at the centre, at all four corners and along every edge, running right off all four sides so it continues seamlessly into the neighbouring tile. The card reads as thick, heavy, dense and solid through its material colour and slight paper tooth alone. Grid squares are crisp, small, evenly spaced and aligned square to the image edges.
CRITICAL GEOMETRY: this is a FLAT full-bleed texture swatch. Absolutely NO recessed box, NO tray, NO inset panel, NO sunken well, NO raised frame, NO border, NO outer margin, NO surrounding rim, NO side walls, NO visible thickness, NO bevel, NO chamfer, NO 3D edges, NO receding inner walls, NO perspective, NO depth, NO shadow gradient across the panel. It is NOT a picture frame and NOT a shallow box seen from above — it is a flat continuous infinite sheet.
CRITICAL LIGHTING: perfectly even flat uniform lighting, identical brightness at the centre, the corners and all edges. NO vignette, NO darkened edges, NO soft glow in the middle, NO drop shadow.
Top-down orthographic view looking straight down from directly above, perfectly flat flat-lay, no perspective, no vanishing point, no tilt, no isometric angle. Flat 2D game tile texture.
No characters, no creatures, no people, no objects, no props. No text, no letters, no words, no numbers, no writing, no lettering, no symbols, no watermark, no signature, no logo.
```
