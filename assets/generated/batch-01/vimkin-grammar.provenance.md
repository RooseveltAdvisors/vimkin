# Provenance — vimkin-grammar

- **Asset:** `vimkin-grammar.png`
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
- **Seed:** 606606
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

## Prompt

```
Original game character concept art: a tiny palm-sized creature made of ink and folded paper, holding up a slender little wooden staff. The top of the staff is crowned with two small curved comma-like ink flourishes forming a decorative quotation-mark ornament, glowing faintly. Round plump body of warm off-white parchment with visible paper grain and soft ink-brush outlines, one single scruffy tuft of pen-stroke hair, big round studious eyes, a wise and slightly prim expression. A round lantern set into its belly glows warm amber. Small scholarly wizard energy, kids-storybook charm. Cozy hand-drawn game art, soft painterly edges, warm inviting glow. Bold simple silhouette, chunky readable shapes, high contrast, minimal fine detail so it reads clearly when very small. Centered composition, plain flat empty dark ink-navy background, no scenery, no ground, no props, no text, no letters, no words, no watermark.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
