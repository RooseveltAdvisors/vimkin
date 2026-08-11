# Vimkin — Visual & Audio Style Guide (v1)

The single source of truth for every generated asset. All assets must be ORIGINAL — no resemblance to VIM Adventures' art, characters, or world.

## Mood

**"Cozy arcade."** Warm, playful, glowing — a night-time desk-lamp world inside living documents. Think: soft darkness + phosphor glow, paper textures, ink creatures. Fun over slick; charming over corporate.

## Palette

- Background deeps: ink navy `#171A26`, plum dark `#211C38`
- Paper/parchment: warm off-white `#F2EBDD`
- Hero glow: cursor cyan `#7DE8D8`
- Vimkin warm: amber `#FFC46B`
- Accent success: leaf `#8BD97A`; error/soft-alarm: coral `#F2836B` (never harsh red)
- Text/UI: monospace-first typography

## The cast (all original)

- **The Cursor-Spirit (player):** a small luminous block of light with a soft cyan glow and a faint trailing afterimage. No face in idle; blinks like a terminal cursor. Expressive through glow intensity and trail shape, not limbs.
- **Vimkins:** palm-sized ink-and-paper creatures, round-bodied, one tuft of pen-stroke hair, amber lantern-belly that lights up when rescued. Each tier has a variant (navigator Vimkin wears a tiny paper hat; grammar Vimkin carries a quote-mark staff). Cute, slightly scruffy, hand-drawn feel.
- **The Entropy Worm (antagonist, light):** a scribble-worm of tangled strikethrough lines that leaves typos, filler words, and mess in its wake. More mischievous than scary (kids-movie villain energy).

## World

Levels are living documents: Markdown headers are stone gates, YAML keys are hanging signposts, JSON braces are vaulted doors, prose paragraphs are meadow rows. Terrain reads as text first, world second.

## Audio

- SFX: soft mechanical-keyboard thock family, pitched marimba pops for success tiers, paper rustles, tiny chimes. Pitch-randomize ±3%.
- Big-combo chord: warm synth+marimba stack, < 600ms.
- Narration (tutorial): friendly, unhurried voice via fleet Qwen3-TTS; script lines live in lesson data.
- BGM: lo-fi, low-stakes, loopable 2-3min beds (dojo calm; game curious; arcade pulse). Generated via fleet MusicGen (svc:8881) or Lyria.

## Deliverable specs

- Stills: PNG with alpha, 1024px master, sprite-sheet friendly (character on neutral bg).
- Every generated asset gets a sidecar `<name>.provenance.md`: prompt, model, date, generator.
