# Provenance — app-icon-vimkin

- **Asset:** `app-icon-vimkin.png`
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
- **Seed:** 808808
- **Resolution:** 1024x1024 PNG (RGB, no alpha)
- **Brief:** `assets/briefs/style-guide.md` + `assets/briefs/batch-01-characters.md`
- **Originality:** prompt describes original characters only; no existing IP, franchise, game, or
  named artist/style was referenced.

## Prompt

```
Original app icon design, centered, symmetrical, filling the frame: a dark rounded-square terminal window frame in deep ink navy with a subtle soft inner bevel and a thin warm rim light. Inside the frame, a large round warm amber lantern glow radiates outward from the center like a paper lantern lit at night, with soft golden bloom. To one side of the glow sits a single bold solid rectangular block cursor in bright cyan-teal, crisp and clean. Extremely simple, iconic, graphic, poster-like — only three elements: dark rounded square, amber glow, cyan block. Bold flat shapes, very high contrast, no small details, no clutter, instantly readable at tiny size. Cozy warm arcade mood. Flat vector-like icon illustration, no text, no letters, no words, no numbers, no watermark, no border decoration.
```

## Notes

Rendered on an opaque ink-navy background (Flux outputs RGB, not RGBA). The style guide calls for
PNG with alpha for sprite use — background removal / cutout is a downstream step and has not been
applied here.
