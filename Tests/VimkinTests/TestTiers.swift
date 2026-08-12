import Testing

// The three-tier test taxonomy.
//
// EVERY @Suite in this target carries EXACTLY ONE of these tags. The rule is
// enforced mechanically by `scripts/tiers.sh check`, which parses this tree and
// fails if a suite is untagged or double-tagged, and by `scripts/gate.sh`,
// which proves the three tiers partition the suite exactly (unit + integration
// + acceptance test counts must sum to the full-run count).
//
// Tiers are runnable independently:
//
//     bash scripts/test-tier.sh unit
//     bash scripts/test-tier.sh integration
//     bash scripts/test-tier.sh acceptance
//
// which is `swift test --filter <regex of that tier's suite type names>`, with
// the regex derived from the tags below — see `scripts/tiers.sh filter <tier>`.
// Nothing is hand-maintained: the tag on the suite IS the source of truth.
//
// Where to put a new test: see CONTRIBUTING.md § "Test taxonomy".

extension Tag {
    /// Tier 1 — pure logic, no I/O.
    ///
    /// No filesystem, no bundled content, no `UserDefaults`, no audio engine.
    /// Everything the test needs is constructed inline. The vim engine itself
    /// lives here: it is a pure value type, so driving it with key strings is
    /// still unit testing. Also: scoring math, mastery math, terrain
    /// classification, camera clamp, syntax classification, YAML parsing.
    @Tag static var unit: Self

    /// Tier 2 — cross-seam behaviour with real collaborators, no mocks.
    ///
    /// Real bundled content (`commands.json`, the corpus, World 1 levels, the
    /// lesson database), a real `ProgressStore` writing to a temp directory, a
    /// real `VimEngine` judging real generated drills, real `UserDefaults`
    /// suites. If the test would still pass with the shipped content deleted,
    /// it is not an integration test.
    @Tag static var integration: Self

    /// Tier 3 — UI / acceptance contracts that are checkable headlessly.
    ///
    /// Key→action translation tables, mode arbitration, the lock filter the
    /// keyboard runs through, view-model / controller state machines, the
    /// notification contracts screens talk to each other over, and the
    /// SpriteKit render-spec factories.
    ///
    /// HONEST LIMIT: this tier does NOT cover pixels. Nothing here proves a
    /// view lays out, draws, animates, or is legible — that is manual visual
    /// QA, and `docs/release-checklist.md` lists the surfaces to eyeball.
    @Tag static var acceptance: Self
}
