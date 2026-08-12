# Provenance — vimkin-navigator

- **Asset:** `vimkin-navigator.png`
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
- **Seed:** 515151
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

**Iteration:** Re-rolled once: the first attempt (seed 505505) rendered a furry creature, breaking ink-and-paper cast consistency. Prompt was hardened with explicit folded-paper/not-fur language.

## Prompt

```
Original game character concept art: a tiny palm-sized creature whose entire body is made of smooth crisp FOLDED PAPER and warm off-white parchment, with visible sharp fold creases, flat paper facets and origami-like planes, drawn with soft ink-brush outlines. Its surface is smooth dry paper — completely SMOOTH, NOT fur, NOT furry, NOT fluffy, NOT hairy, no fur texture anywhere on the body. Round plump paper body. On its head sits a small folded-paper hat like a little origami sailor cap, with a single scruffy tuft of dark pen-stroke hair poking out from beneath it. Big friendly round eyes, cheerful confident expression. A round lantern set into its belly glows warm amber, casting golden light on the paper folds. Standing proudly, one paper arm raised and pointing the way ahead. Adventurous little guide, kids-storybook charm. Cozy hand-drawn game art, soft painterly edges, warm inviting glow. Bold simple silhouette, chunky readable shapes, high contrast, minimal fine detail so it reads clearly when very small. Centered composition, plain flat empty dark ink-navy background, no scenery, no ground, no props, no text, no letters, no words, no watermark.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
