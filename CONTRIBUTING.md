# Contributing to Vimkin

Thanks for looking. Vimkin is a native macOS app built with SwiftPM — no Xcode
project, no package manager, no dependencies. Everything below is one command.

---

## Build and run

Requires macOS 15+ and a Swift 6 toolchain (full Xcode, or just the Command Line
Tools — both work).

```sh
git clone https://github.com/RooseveltAdvisors/vimkin.git
cd vimkin

swift build                     # build
bash scripts/test.sh            # run the whole test suite
swift run Vimkin                # run the app

bash scripts/make-app.sh 0.0.0  # assemble dist/Vimkin.app
```

> Use `bash scripts/test.sh`, not bare `swift test`. On a machine with only the
> Command Line Tools installed (no Xcode), the swift-testing cross-import
> overlay needs explicit framework paths or the build fails with "no such
> module". `scripts/test.sh` detects that case and adds them; on a full-Xcode
> machine it runs plain `swift test`. Every extra argument is forwarded, so
> `bash scripts/test.sh --filter WordMotionTests` works as you'd expect.

---

## Before you push: run the gate

```sh
bash scripts/gate.sh
```

This is the whole release gate, and it is exactly what CI runs — the workflow
invokes this same script, so local and CI cannot drift. It takes ~2 minutes cold
and prints PASS/FAIL with a timing per stage:

| # | Stage | Fails when |
|---|---|---|
| 1 | taxonomy | a `@Suite` has no tier tag, two tier tags, or a duplicated type name |
| 2 | dependencies | `Package.swift` or `Package.resolved` gains a third-party package |
| 3 | build | the debug build fails **or emits any warning** (`-warnings-as-errors`) |
| 4 | warnings | the build log contains `warning:` from any tool |
| 5–7 | test:unit / test:integration / test:acceptance | any test in that tier fails |
| 8 | test:all | any test fails, **or** the three tiers don't sum to the full suite |
| 9 | app-bundle | the release build warns or fails, the executable is missing, the bundled `Content` resources are missing, or the ad-hoc signature doesn't verify |
| 10 | info-plist | `plutil -lint` rejects it, a required key is missing, or the version doesn't match |
| 11 | dmg | the DMG fails to build, fails to mount, or lacks `Vimkin.app` / the `/Applications` drop target |
| 12 | checksum | the published `.sha256` doesn't match the DMG |

While iterating you can skip the packaging stages:

```sh
GATE_SKIP_PACKAGING=1 bash scripts/gate.sh   # stages 1-8 only
```

but a PR is only ready when the **full** gate is green.

---

## Test taxonomy

Every test lives in one of three tiers. The tier is a swift-testing tag on the
`@Suite` — that tag is the single source of truth, and everything else (the
per-tier filters, the CI counts, the drift check) is derived from it.

```swift
@Suite("Game: camera follow + clamp", .tags(.unit))
struct TileCameraTests { … }
```

Tags are declared in [`Tests/VimkinTests/TestTiers.swift`](Tests/VimkinTests/TestTiers.swift).

### The three tiers

**`.unit` — pure logic, no I/O.** No filesystem, no bundled content, no
`UserDefaults`, no audio engine; everything the test needs is built inline. The
vim engine itself lives here — it's a pure value type, so driving it with key
strings is still unit testing. Also: scoring, mastery math, terrain
classification, camera clamp, syntax classification, the level-YAML parser.

**`.integration` — cross-seam, real collaborators, no mocks.** Real bundled
content (`commands.json`, the corpus, the World 1 levels, the lesson database),
a real `ProgressStore` writing into a temp directory, real `UserDefaults`
suites, a real `VimEngine` judging real generated drills. Rule of thumb: *if the
test would still pass with the shipped content deleted, it isn't an integration
test.*

**`.acceptance` — headless-checkable UI contracts.** Key→action translation
tables, mode arbitration, the lock filter the keyboard runs through, view-model
and controller state machines, the notification contracts screens talk to each
other over, and the SpriteKit render-spec factories. Acceptance tests may use
real collaborators — that's a feature, not a smell; what makes them acceptance
tests is *what they assert about* (a user-facing contract), not what they're
wired to.

> **What this tier does not cover, honestly:** pixels. Nothing headless proves a
> view lays out, draws, animates, or is legible. That is manual visual QA, and
> the surfaces to walk are enumerated in
> [`docs/release-checklist.md`](docs/release-checklist.md) § 3.

### Current shape

| Tier | Suites | Tests |
|---|---|---|
| unit | 32 | 250 |
| integration | 31 | 202 |
| acceptance | 7 | 45 |
| **total** | **70** | **497** |

Ask the source rather than trusting this table:

```sh
bash scripts/tiers.sh counts            # suite counts per tier
bash scripts/tiers.sh list integration  # which suites are in a tier
bash scripts/tiers.sh check             # the invariant: exactly one tag per suite
```

### Running one tier

```sh
bash scripts/test-tier.sh unit
bash scripts/test-tier.sh integration
bash scripts/test-tier.sh acceptance
```

That's `swift test --filter <regex>`, where the regex is the tier's suite type
names joined with `|` and anchored with a trailing `/` (the separator between
suite and test in a swift-testing ID — the anchor is what stops
`TerrainMapTests` from also matching `TerrainMapContentTests`). Print it with
`bash scripts/tiers.sh filter unit` if you want to hand it to `swift test`
yourself.

### Where does my new test go?

Answer in order; the first "yes" wins.

1. Does it assert on something a **user interacts with** — a key mapping, a mode
   transition, what a screen's model does in response — rather than on a
   calculation? → **`.acceptance`**
2. Does it touch the **filesystem, `UserDefaults`, or the shipped content** in
   `Sources/Vimkin/Content/`? → **`.integration`**
3. Otherwise → **`.unit`**.

Put the file next to its siblings by domain (`Tests/VimkinTests/Engine/`,
`Game/`, `Dojo/`, …). Tier is a tag, not a directory.

**A suite belongs to exactly one tier.** If a suite has genuinely mixed tests,
split it — the codebase does this in several places, and the split file names
the two halves after each other (`TerrainMapTests` unit / `TerrainMapContentTests`
integration; `MasteryMathTests` unit / `MasteryModelTests` integration). Don't
pick the "closest" tag for a mixed suite; stage 8 of the gate exists to catch
tests that fall between tiers, and a mis-tagged suite defeats the point of
being able to run a tier on its own.

---

## The rules that CI enforces

**Zero third-party dependencies.** Vimkin depends on nothing but the platform.
This isn't taste — it's what lets anyone clone and build offline in one command,
and what keeps a free, no-telemetry app honest about what's inside it. The gate
fails on any `.package(...)` in `Package.swift` or any pin in
`Package.resolved`. If you think something genuinely needs a dependency, open an
issue and make the case first; a PR that adds one will be red before it's read.

**Zero build warnings.** The tree is warning-clean and stays that way: the gate
builds with `-warnings-as-errors` and additionally fails on any `warning:` in
the log. Fix the warning; don't silence it with `#warning`-adjacent tricks or a
suppression. A warning you introduce is yours to clear before the PR lands.

**Every feature ships with tests, in the right tier.** A PR that adds behaviour
and no tests is incomplete. Concretely:

- new logic → `.unit` tests for the branches, including the edge cases
- new content (a level, a lesson, a corpus document, a command record) →
  `.integration` tests, and note that the existing content sweeps (every level
  beatable, every lesson completable, every drill solvable) will judge your new
  content automatically — make sure they still pass
- new UI wiring (a key binding, a view model, a screen-to-screen hand-off) →
  `.acceptance` tests for the contract
- a bug fix → a test that **fails on `main`** and passes with your fix. Write it
  first. A test that only passes after the fix, written after the fix, proves
  nothing about the bug.

---

## Pull requests

- One change per PR; keep the diff traceable to the thing you're fixing.
- Match the surrounding style. The codebase comments the *why*, not the *what* —
  keep that.
- Run `bash scripts/gate.sh` before pushing; CI will run the same thing.
- If the change is visible on screen, say which of the
  [release-checklist](docs/release-checklist.md) § 3 surfaces you walked and
  what you saw. CI cannot see pixels; you can.
- Add a line to `## Unreleased` in [`CHANGELOG.md`](CHANGELOG.md), written for a
  player.

## License

MIT. By contributing you agree your contribution is licensed under it. See
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
