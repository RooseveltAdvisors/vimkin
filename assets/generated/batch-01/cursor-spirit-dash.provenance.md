# Provenance — cursor-spirit-dash

- **Asset:** `cursor-spirit-dash.png`
- **Date:** 2026-08-11
- **Generator:** local ComfyUI 0.28.0 on `gpu.home.arcs.internal` (NVIDIA RTX 5090)
- **Pipeline:** ComfyUI HTTP API (`POST /prompt`), Flux.2 text-to-image graph
- **Diffusion model:** `flux2_dev_fp8mixed.safetensors` (FLUX.2-dev, fp8 mixed)
- **Text encoder:** `mistral_3_small_flux2_fp4_mixed.safetensors` (CLIPLoader type `flux2`)
- **VAE:** `flux2-vae.safetensors`
- **Sampler:** euler (`KSamplerSelect`)
- **Scheduler:** `Flux2Scheduler`
- **Steps:** 28
- **Guidance:** 4.0 (`FluxGuidance`)
- **Seed:** 212121
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

**Iteration:** Re-rolled once: the first attempt (seed 202202) rendered an arrowhead instead of a block cursor. Prompt was hardened with explicit rectangle/not-an-arrow language.

## Prompt

```
Original game character concept art: a glowing cyan-teal terminal cursor spirit in motion. Its body is a simple SOLID RECTANGULAR BLOCK of light — a squared-off slab, like a text cursor, with flat blunt ends and four square corners. The rectangle is stretched and elongated horizontally by speed. It is a rectangle, a block, a bar — absolutely NOT an arrow, NOT an arrowhead, NOT a chevron, NOT a triangle, NOT a pointed dart, NOT a comet; the leading edge stays perfectly flat and squared off. Behind it trails a long wake of layered translucent rectangular afterimages, each a fainter copy of the same block, plus soft streaking light ribbons and tiny sparkle motes. Brilliant cyan-teal core with soft bloom halo. No face, no limbs, no arms, no legs. Cozy hand-drawn game art, soft painterly edges, warm charming storybook feel, joyful sense of speed. Bold simple silhouette, high contrast, minimal fine detail so it reads clearly when very small. Centered composition, plain flat empty dark ink-navy background, no scenery, no ground, no props, no text, no letters, no words, no watermark.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
