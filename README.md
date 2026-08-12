# Vimkin

**Learn Vim. Rescue the Vimkins. Free forever.**

Vimkin is a native macOS game that teaches Vim motions the way your hands actually learn them — accuracy-first drills, real Markdown/JSON/YAML documents, and an original adventure where the motions you've mastered are your only controls.

> The Vimkins keep the world's documents tidy. The Entropy Worm scattered them.
> You are a cursor-spirit. Go get them back — one motion at a time.

## What's inside

- **Tutorial** — learn the Vim grammar (verbs + modifiers + text objects) one keystroke at a time
- **Practice Dojo** — calm, adaptive drills on real documents that target your weakest skills
- **Adventure** — a document-world game where `w`, `f"`, and `diw` open the way; keys you haven't learned yet are literally locked
- **Daily Run** — a 3-minute date-seeded gauntlet, scored against your own past runs
- **Lookup Overlay** — global hotkey, type "delete inside quotes", get `di"` — from any app

## Install

1. Download the latest `.dmg` from [Releases](../../releases).
2. Drag `Vimkin.app` into `Applications`.
3. First launch: macOS may block the unsigned app — run
   `xattr -dr com.apple.quarantine /Applications/Vimkin.app`
   or right-click → Open.

## Principles

- **Free forever.** No accounts, no ads, no telemetry, no paywall.
- **Accuracy before speed.** Wrong reps train wrong hands; timers only appear after mastery.
- **No dark patterns.** Streaks have grace days. XP never gates anything. We never guilt you.

## Development

SwiftPM project — no Xcode required, and no third-party dependencies:

```bash
swift build                      # build
bash scripts/test.sh             # run all 497 tests
bash scripts/test-tier.sh unit   # or one tier: unit | integration | acceptance
bash scripts/gate.sh             # the full release gate — what CI runs
bash scripts/make-app.sh 0.1.0   # assemble Vimkin.app into dist/
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the three-tier test taxonomy, where a
new test goes, and the zero-dependency / zero-warning rules CI enforces, and
[docs/release-checklist.md](docs/release-checklist.md) for how a release is cut.

## License

MIT — see [LICENSE](LICENSE).
