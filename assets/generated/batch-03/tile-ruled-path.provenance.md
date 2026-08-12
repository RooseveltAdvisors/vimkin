# Provenance — tile-ruled-path

- **Asset:** `tile-ruled-path.png` (from master `tile-ruled-path-rr1.png`)
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
- **Seed:** 410003

**Iteration:** Re-rolled once. The first attempt (seed 310003) drew the rule correctly but
rendered the parchment as a *photographed sheet* — a pale border band and softly rounded
corners framed the tile, which breaks edge-to-edge tiling. The prompt was hardened with
"infinite continuous texture swatch, NOT a photograph of a sheet / no border, no frame,
no rounded corners, no paper edges visible". The re-roll is full-bleed with the single
blue-grey rule running dead-centre from edge to edge, so consecutive tiles form one
continuous line.

## Prompt

```
Seamless top-down game tile texture: aged warm off-white parchment notebook paper, colour #F2EBDD with soft paper fibre grain and faint age mottling, marked by a SINGLE faint pale blue-grey horizontal ruled line. The line runs perfectly straight and perfectly level from the extreme left edge of the image to the extreme right edge, exactly centred vertically, touching and running off both side edges so it continues unbroken into the next tile. The line is thin, soft and slightly uneven like printed notebook ruling. Only ONE horizontal line and nothing else: no vertical lines, no grid, no margin line, no second rule, no dashes.
CRITICAL FRAMING: this is an infinite continuous texture swatch, NOT a photograph of a sheet of paper. Absolutely NO border, NO frame, NO pale edge band, NO rounded corners, NO paper edges visible, NO sheet outline, NO vignette, NO darkened or lightened corners, NO drop shadow, NO background behind the paper. The paper fills the entire square completely and runs right off all four edges. Perfectly even uniform flat lighting, identical brightness at the centre, corners and all edges.
Top-down orthographic view looking straight down from directly above, perfectly flat flat-lay, no perspective, no vanishing point, no horizon line, no tilt, no isometric angle, no 3D camera angle. Flat 2D game tile texture, even flat lighting.
No characters, no creatures, no people, no faces, no hands, no animals, no objects, no props. No text, no letters, no words, no numbers, no writing, no lettering, no typography, no symbols, no handwriting, no watermark, no signature, no logo.
```
