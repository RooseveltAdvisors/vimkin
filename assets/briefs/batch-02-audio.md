# Asset Batch 02 — Audio (for fleet generation: SFX + Qwen3-TTS narration + MusicGen/Lyria beds)

Follow `style-guide.md` strictly ("cozy arcade": warm, playful, night-desk-lamp world). All original audio — no sampled commercial libraries with restrictive terms, no recognizable game franchise motifs.

**Why the tiers matter:** the juice layer (`Sources/Vimkin/Juice/`) grades every command's feedback off its `CommandEvent.category`, and the sound is half of that grading. A single motion must feel *smaller* than an operator+motion, which must feel *smaller* than the full grammar (`diw`, `ci"`). If the three SFX are equally loud, the pedagogy is gone. Keep the loudness/brightness ladder honest at mixdown.

**Global specs:** 48kHz / 24-bit mono WAV masters (a 44.1kHz mono render is fine too), no dither noise floor, **peak −6 dBFS**, silence trimmed to <5ms of head. Every clip is played back with ±3% random rate jitter by `JuiceAudio`, so leave no artifacts that smear under a small pitch shift. No reverb tails longer than the clip.

---

## 1. The three juice tiers (REQUIRED — these three filenames are wired in code)

The engine looks for these stems in `<bundle>/Contents/Resources/audio/sfx/` and falls back to a synthesized tone when they are absent. Ship these three first; everything else in this brief is enrichment.

1. `juice-whisper.wav` — **single motion / mode change.** Soft mechanical-keyboard *thock*, dampened, close-mic'd, almost felt rather than heard. **40–70ms.** Low-mid body (~150–400Hz), no click transient above 4kHz. This one plays hundreds of times a session — if it is even slightly annoying at rep 200 it has failed. Test it by playing it 60× in 30 seconds.
2. `juice-pop.wav` — **operator+motion (`dw`, `2dd`, `d$`), one-key actions (`x`, `p`, `u`), `:w`.** A pitched marimba pop with a short woody knock underneath. **100–160ms.** Fundamental around G5 (784Hz), one octave partial, fast exponential decay. Satisfying, not sharp.
3. `juice-burst.wav` — **full grammar (`diw`, `ci"`, `ya(`) — the moment the app exists for.** Warm synth + marimba stack: a major triad (C–E–G) with a soft bell shimmer on top and a felt low thump underneath. **< 600ms, target ~420ms.** Rises fast, decays warm. Should read as *"yes — that's the thing"*, never as a slot-machine jackpot (no coin sounds, no fanfare, no ascending arpeggio run).

## 2. Supporting SFX palette

4. `paper-rustle.wav` — document/page transition (drill advances, level loads). Dry paper, 200–350ms, no crinkle spike.
5. `chime-unlock.wav` — a command unlocks in the tutorial. Tiny two-note chime, up a fifth, bell-like, ~500ms.
6. `chime-vimkin-rescued.wav` — a Vimkin's lantern-belly lights up. Warm chime + a soft breathy "whumph" of glow. ~600ms. Cousin of `juice-burst` but rounder and less percussive.
7. `soft-reset.wav` — a wrong key resets the practice page. **Not a buzzer, not a klaxon, never harsh.** A gentle downward paper-and-wood *ptff*, ~180ms. It must read as "here, try again", which is why the coral/soft-alarm rule exists in the style guide.
8. `cursor-dash.wav` — the cursor-spirit's `w`/`b`/`e` jump in the game surface. Airy whoosh with a tiny phosphor tail, 90–140ms.
9. `gate-open.wav` — a skill-gated door in a document world opens (stone-gate header, brace vault). Low wooden slide + resonant open, ~700ms.
10. `locked-shimmer.wav` — a not-yet-learned key was pressed. Friendly, curious, *never* a rejection buzz: a soft glassy shimmer, ~250ms, quiet.
11. `combo-tick.wav` — optional: a barely-there tick layered under `juice-pop`/`juice-burst` as the combo run climbs (the juice layer raises intensity as a run builds). ~30ms, near-subliminal.

## 3. Tutorial narration (fleet Qwen3-TTS)

Voice: **friendly, unhurried, warm, adult, low-key** — a patient friend who already knows you'll get it. No teacher-voice, no hype, no upspeak. Slight smile. Pace slow enough to read along with. Render each line as its own file so lesson data can reference them individually.

Output as `narration/<lesson-id>-<n>.wav`, e.g. `narration/t1-modes-1.wav`.

| File | Lesson | Line |
|---|---|---|
| `t1-modes-1` | t1-modes | "Normal mode is home. You'll always come back here." |
| `t1-modes-2` | t1-modes | "Escape is the way home. When you're lost, press it. Nothing breaks." |
| `t1-hjkl-1` | t1-hjkl | "Your fingers never leave the home row. H, J, K, L — left, down, up, right." |
| `t1-insert-anywhere-1` | t1-insert-anywhere | "There are five doors into Insert mode. Each one puts you somewhere useful." |
| `t1-save-quit-1` | t1-save-quit | "Colon w writes. Colon q quits. Colon w q does both — and that's how you leave." |
| `t2-words-1` | t2-words | "Letters are slow. Move by words instead." |
| `t2-anchors-1` | t2-anchors | "Every line has two anchors, and so does every file. Learn the four and you can go anywhere." |
| `t2-find-char-1` | t2-find-char | "F is for find. Name a character and fly straight to it." |
| `t3-delete-char-1` | t3-delete-char | "X deletes one character. U undoes it. You can't hurt anything here." |
| `t3-delete-verb-1` | t3-delete-verb | "D isn't a key — it's a verb. It waits for you to say how much." |
| `t3-change-verb-1` | t3-change-verb | "C is delete, and then type. One motion instead of two." |
| `t3-yank-put-1` | t3-yank-put | "Yank is copy. Put is paste. Same grammar as everything else." |
| `t3-counts-1` | t3-counts | "Put a number in front and the command happens that many times." |
| `t4-inner-word-1` | t4-inner-word | "Here's the good part. A text object is a noun that finds its own edges." |
| `t4-quotes-1` | t4-quotes | "Inside the quotes. You don't have to say where they are — Vim already knows." |
| `t4-brackets-paragraphs-1` | t4-brackets-paragraphs | "Brackets, parentheses, whole paragraphs — all nouns, all the same shape." |
| `t4-grammar-click-1` | t4-grammar-click | "Verb, modifier, noun. Change inside quotes. That's the whole language — you just learned Vim." |
| `narration/welcome` | — | "You're a cursor-spirit. The Vimkins keep these documents tidy, and they've been scattered. Let's go get them." |
| `narration/rusty` | — | "This one's gone a little rusty. Let's warm it back up." |
| `narration/streak-grace` | — | "You missed a day. That's fine — the streak's still yours." |

**Tone guard rails (plan R7 — ethical gamification):** never guilt, never urgency, never "don't lose your streak!". No line may imply the player is behind, failing, or about to lose something.

## 4. BGM beds (fleet MusicGen on svc:8881, or Lyria)

Lo-fi, low-stakes, **loopable, 2–3 minutes**, seamless loop point, mixed to sit at −18 LUFS so narration and SFX cut through. No drops, no builds, no vocals, no ticking-clock rhythms anywhere.

1. `bgm-dojo-calm.wav` — the Practice Dojo. Warm Rhodes, brushed low-tempo pulse (~68 BPM), soft tape hiss, room tone. Feels like a desk lamp at 11pm. Absolutely no tension, no timer-like elements — the dojo is explicitly the calm surface.
2. `bgm-game-curious.wav` — the adventure world. Plucked marimba/kalimba motif over a soft pad, ~92 BPM, a light sense of wandering and discovery. Playful, a little mischievous (the Entropy Worm is around), never scary.
3. `bgm-arcade-pulse.wav` — the daily arcade run. Same palette but energized: ~124 BPM, driving but *friendly* synth bass, brighter marimba. Pressure through momentum, not menace. This is the ONLY bed allowed to feel fast, because arcade mode is the only place speed is scored.

Optional stems if the generator supports it: `bgm-*-stem-melody.wav` / `bgm-*-stem-bed.wav`, so the app can duck the melody under narration.

---

## Delivery

Output to `assets/generated/batch-02/` (SFX at the root, `narration/`, `bgm/`), each file with a `<name>.provenance.md` sidecar recording prompt, model, date, and generator, per the style guide.

**Integration note:** copy (or symlink) the three tier files to the app bundle's `audio/sfx/` as `juice-whisper.*`, `juice-pop.*`, `juice-burst.*`. `JuiceAudio` accepts `.wav`, `.aiff`, `.aif`, `.caf`, `.m4a`, `.mp3` and also answers to the stems `whisper`/`pop`/`burst`, `tick`/`thock`, `marimba-pop`, `combo-chord`/`chord`. Until they land, the app synthesizes a tick, a pop and a chord in code — so nothing is blocked on this batch.
