# Provenance — tile-island-edge

- **Asset:** `tile-island-edge.png`
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
- **Seed:** 310006

**Iteration:** None — first attempt accepted. Parchment occupies the upper half, a ragged
hand-torn fibrous deckle with loose paper fibres runs across the middle, ink fills the lower
half, and the tear meets both the left and right edges so the rim continues along a row.

**Known minor imperfections (accepted, not blocking):**
- The tear meets the left edge slightly higher than the right edge, so a horizontal run of
  these tiles has a small step at each join rather than a perfectly continuous tear line.
- The paper reads a little brighter/whiter here than `tile-parchment`, and the ink below is
  nearer black than the navy/plum of `tile-ink`. Both are within tolerance for a rim strip
  that sits between the two, but a future pass could tone-match it to its neighbours.

## Prompt

```
Seamless top-down game tile texture of the torn edge where a sheet of parchment meets a sea of ink, seen from directly above. The upper half of the image is warm off-white aged parchment paper colour #F2EBDD with soft fibre grain. Across the middle runs a ragged irregular hand-torn paper edge with a pale feathered fibrous deckle and tiny loose paper fibres. The lower half is deep dark ink navy liquid ink colour #171A26. The torn edge runs horizontally all the way from the extreme left edge of the image to the extreme right edge, meeting both side edges so it continues unbroken into the neighbouring tile. Horizontal band composition, paper above, ink below. Top-down orthographic view looking straight down from directly above, perfectly flat flat-lay, no perspective, no vanishing point, no horizon line, no tilt, no isometric angle, no 3D camera angle. Flat 2D game tile texture, even flat lighting, no drop shadow outside the tile. No characters, no creatures, no people, no faces, no hands, no animals, no objects, no props. No text, no letters, no words, no numbers, no writing, no lettering, no typography, no symbols, no handwriting, no calligraphy, no watermark, no signature, no logo.
```
