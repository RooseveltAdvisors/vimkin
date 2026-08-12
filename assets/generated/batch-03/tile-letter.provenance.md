# Provenance — tile-letter

- **Asset:** `tile-letter.png` (from master `tile-letter.png` -> cutout `tile-letter-alpha.png`)
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
- **Seed:** 310005

**Iteration:** None — first attempt accepted. The key-cap face rendered completely blank as
required (the app draws the glyph on top), with a faint torn/fibrous deckle edge and a soft
contact shadow, centred on flat ink-navy.

**Transparency:** YES. The ink-navy surround was removed on the Mac with Apple Vision
(`VNGenerateForegroundInstanceMaskRequest` ->
`generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)` ->
`CIContext.pngRepresentation(of:format:.RGBA8,colorSpace:)`). Vision returned exactly 1
foreground instance. `croppedToInstancesExtent` was set to **false** deliberately so the
key-cap keeps its original centring within the 1024 frame instead of being cropped to its
own bounds. Verified after downscale: RGBA, 4 samples/pixel, corner alpha 0.00, centre alpha
1.00, opaque fraction 0.208 (matches the cap's area).

## Prompt

```
A single small blank parchment keycap tile, centred in the frame, seen from directly above. It is a rounded-corner square of warm off-white aged paper, colour #F2EBDD, very slightly raised with a soft thin shadow hugging its lower edge, and faint torn deckled fibrous paper edges. Its face is COMPLETELY BLANK and EMPTY smooth paper — absolutely nothing printed on it, no letter, no glyph, no character, no text, no symbol, no engraving, no marking of any kind on the face. It sits centred on a plain flat solid very dark ink-navy background colour #171A26, with a generous even empty margin all the way around it. One single paper square only. Top-down orthographic view looking straight down from directly above, perfectly flat flat-lay, no perspective, no vanishing point, no horizon line, no tilt, no isometric angle, no 3D camera angle. Flat 2D game tile texture, even flat lighting, no drop shadow outside the tile. No characters, no creatures, no people, no faces, no hands, no animals, no objects, no props. No text, no letters, no words, no numbers, no writing, no lettering, no typography, no symbols, no handwriting, no calligraphy, no watermark, no signature, no logo.
```
