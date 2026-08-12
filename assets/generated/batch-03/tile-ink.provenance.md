# Provenance — tile-ink

- **Asset:** `tile-ink.png` (from master `tile-ink-rr3.png`)
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
- **Seed:** 410022 (shipped); rejected attempts 310002, 410002, 410012

**Iteration: re-rolled three times — the hardest tile in the batch.** All four masters are kept
in this folder for comparison.

| attempt | seed | verdict |
|---|---|---|
| `tile-ink.png` | 310002 | REJECTED — best swirl character and the only one with real plum, but
a corner-to-corner value ramp, and several pale flecks resolved into small **fish-like shapes**
(one has a clear dark eyespot, tapered body and tail on inspection). A creature is a hard
disqualifier for a background tile. |
| `tile-ink-rr1.png` | 410002 | REJECTED — fixed the ramp and the creatures (clean round motes),
but swung strongly magenta/violet and read as a starfield rather than liquid ink. |
| `tile-ink-rr2.png` | 410012 | REJECTED — worst of the set. Crushed nearly to black and the
specks resolved into clearly **insect-like** forms with legs and antennae. |
| `tile-ink-rr3.png` | 410022 | **SHIPPED** — cool blue-grey navy marbled ink, evenly toned,
tiles cleanly, plain featureless round motes, no creatures, no gradient, no perspective. |

The re-roll prompts were driven by **measurement, not eyeballing**. Mean RGB was sampled from
each candidate and compared against the brief's hexes (navy `#171A26` = (23,26,38), plum
`#211C38` = (33,28,56) — both blue-dominant, navy with green >= red):

| image | mean RGB | reading |
|---|---|---|
| attempt 1 | (7.7, 5.2, 12.5) | far too dark, green < red -> magenta lean |
| rr1 | (6.6, 3.8, 12.0) | darker still, stronger magenta lean |
| rr2 | (1.8, 0.5, 8.2) | near-black |
| **rr3 (shipped)** | **(39.9, 45.7, 54.5)** | blue-dominant with green > red — correct hue family |

**Known deviations (accepted, documented rather than hidden):**
- rr3's mean value (~47) sits **lighter** than the brief's darkest hex (~29). A texture whose
  mean equals its deepest specified tone would be nearly black — which is exactly what the
  rejected attempts were. rr3 still reads deep, cold and not-walkable against parchment, but
  if it proves too light in engine, darken at composite time rather than regenerating.
- rr3 lost almost all of the **plum** `#211C38`; it is essentially navy blue-grey. The brief
  asks for navy shading to plum. Every attempt that introduced real plum also introduced
  either magenta cast or creature artifacts. Plum is better reintroduced as a subtle tint.
- The suspended motes in rr3 are a little numerous and uniform in size, which reads slightly
  regular at full resolution. This is much less visible at the shipped 512px.

## Prompt (shipped, rr3)

```
Seamless top-down tile texture of a deep sea of dark ink seen from directly above.
COLOUR IS THE MOST IMPORTANT THING: the ink is a DARK SLATE BLUE-GREY NAVY, hex #171A26 — a cool blue-grey black with a clear BLUE-GREY cast, definitely blue and slightly grey-green, NOT purple. Woven through it are restrained veins of muted dark blue-violet plum, hex #211C38. Overall this is a COOL BLUE-GREY-BLACK ink.
BRIGHTNESS: it must be dark but clearly READABLE, roughly the value of a dark slate stone or deep navy denim in shadow — NOT pitch black, NOT crushed to pure black, NOT an almost-black void. Keep visible mid-dark tonal detail and gentle value variation throughout so the swirls are legible.
FORBIDDEN COLOUR: no magenta, no bright purple, no violet neon, no pink, no lavender, no fuchsia. The purple must never dominate; blue-grey always dominates.
FORM: slow swirling currents and soft eddies of slightly lighter blue-grey turning through the liquid, like marbled ink in still water. A small number of very simple, tiny, soft round pale-grey dust motes suspended in the depths.
ABSOLUTELY FORBIDDEN: no fish, no minnow, no tadpole, no larva, no shrimp, no insect, no moth, no bug, no worm, no snail, no jellyfish, no creature, no animal, no living thing, no eye, no eyespot, no dark dot inside a pale shape, no head, no tail, no fin, no wing, no leg, no antenna, no body. Every pale speck must be a plain featureless round blurry dot with no internal detail whatsoever.
Seamless repeating tileable texture, edges wrap and tile continuously, no border, no frame, no vignette, texture runs off all four edges. Even overall tone, no strong corner-to-corner gradient.
Top-down orthographic view straight down from directly above, perfectly flat, no perspective, no horizon, no tilt. Flat 2D game tile texture, even flat lighting.
No characters, no people, no objects. No text, no letters, no words, no numbers, no writing, no symbols, no watermark, no signature, no logo.
```
