# Provenance — vimkin-base-trapped

- **Asset:** `vimkin-base-trapped.png`
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
- **Seed:** 303303
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

## Prompt

```
Original game character concept art: a tiny palm-sized creature made of ink and folded paper. Round plump body of warm off-white parchment with visible paper grain and soft ink-brush outlines, one single scruffy tuft of pen-stroke hair curling from the top of its head, big round hopeful eyes looking upward. A round lantern set into its belly is DARK and UNLIT, dull grey, no glow. It is tangled up in a loose messy nest of dark scribbled ink strands that wrap around its body and arms, holding it gently in place. Sweet and slightly scruffy, more wistful than frightened, kids-storybook charm. Cozy hand-drawn game art, soft painterly edges, warm inviting mood. Bold simple silhouette, chunky readable shapes, high contrast, minimal fine detail so it reads clearly when very small. Centered composition, plain flat empty dark ink-navy background, no scenery, no ground, no props, no text, no letters, no words, no watermark.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
