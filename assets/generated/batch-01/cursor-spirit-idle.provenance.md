# Provenance — cursor-spirit-idle

- **Asset:** `cursor-spirit-idle.png`
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
- **Seed:** 101101
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

## Prompt

```
Original game character concept art: a small luminous floating block of light, a glowing rectangular terminal cursor brought to life as a gentle spirit. Radiant cyan-teal glow, soft bloom halo, a faint translucent afterimage trail streaming behind it like a slow blink. No face, no limbs, no arms, no legs — it expresses itself purely through glow intensity and the shape of its light trail. Three-quarter view, hovering gently, a few tiny sparkle motes drifting around it. Cozy hand-drawn game art, soft painterly edges, warm charming storybook feel, night-time desk-lamp mood. Bold simple silhouette, strong readable shape, high contrast, minimal fine detail so it reads clearly when very small. Centered composition, plain flat empty dark ink-navy background, no scenery, no ground, no props, no text, no letters, no words, no watermark.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
