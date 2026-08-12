# Provenance — tile-parchment

- **Asset:** `tile-parchment.png` (from master `tile-parchment-rr1.png`)
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
- **Seed:** 410001

**Iteration:** Re-rolled once. The first attempt (seed 310001) rendered a clear corner
vignette — the paper darkened toward all four edges, which would have produced a visible
checkerboard seam when the tile repeats. The prompt was hardened with explicit
"no vignette / no darkened corners / identical brightness at centre, corners and edges"
language plus "infinite texture swatch, not a photograph of a sheet". The re-roll is
near-uniform and the foxing is distributed evenly across the whole surface.

## Prompt

```
Seamless top-down game ground tile texture of blank aged parchment paper. Warm off-white cream paper, colour #F2EBDD, subtle soft paper fibre grain running through the sheet, faint scattered foxing spots and gentle age mottling evenly and randomly distributed across the entire surface. Calm, clean, restful, even walkable ground surface.
CRITICAL LIGHTING: perfectly even flat uniform lighting edge to edge. The brightness is absolutely identical at the centre, at all four corners and along every edge. Absolutely NO vignette, NO darkened corners, NO darkened edges, NO shadowed border, NO gradient falloff, NO burnt edges, NO scorched border, NO torn or aged edge, NO frame, NO drop shadow, NO glow. The paper does NOT sit on a surface and is NOT photographed as a sheet — it is a flat continuous infinite texture swatch.
Seamless repeating tileable texture, the edges wrap and tile continuously with copies of itself, no border, no frame, no vignette, no rounded corners, texture runs right off all four edges.
Top-down orthographic view looking straight down from directly above, perfectly flat flat-lay, no perspective, no vanishing point, no horizon line, no tilt, no isometric angle, no 3D camera angle. Flat 2D game tile texture, even flat lighting, no drop shadow outside the tile.
No characters, no creatures, no people, no faces, no hands, no animals, no objects, no props. No text, no letters, no words, no numbers, no writing, no lettering, no typography, no symbols, no handwriting, no calligraphy, no watermark, no signature, no logo.
```

## Notes

Opaque RGB (Flux outputs no alpha). Ground tile — no alpha required.
