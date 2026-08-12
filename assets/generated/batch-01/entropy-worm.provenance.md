# Provenance — entropy-worm

- **Asset:** `entropy-worm.png`
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
- **Seed:** 707707
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

## Prompt

```
Original game creature concept art: a long mischievous worm whose entire body is made of tangled, looping, scribbled ink strikethrough lines — a snarl of crossed-out pen strokes coiling into a serpentine shape. Two big googly cartoon eyes and a wide crooked grin peek out from the scribble at the front. Its tail unravels into loose messy scrawl, and a few small scattered ink smudges and blots trail behind it in its wake. Playful troublemaker energy, gleeful and impish, a cheeky kids-cartoon villain, absolutely not scary, not menacing, not horror. Soft coral and dark ink tones. Cozy hand-drawn game art, loose sketchy brush lines, warm charming mood. Bold simple silhouette, strong readable shape, high contrast, minimal fine detail so it reads clearly when very small. Centered composition, plain flat empty dark ink-navy background, no scenery, no ground, no props, no text, no letters, no words, no watermark.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
