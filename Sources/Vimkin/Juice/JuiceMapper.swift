// JuiceMapper.swift — the one place a CommandEvent becomes feedback (plan U8).
//
// Pure and total: no clocks, no randomness, no state. The same event always
// yields the same JuiceEvent, which is what lets both renderers, the audio
// layer, and the tests agree about what a command "should feel like".
//
// The combo boost (a run of composed commands feeling progressively better)
// deliberately lives NEXT DOOR in `JuiceCombo`, so this function stays pure.

import Foundation

public enum JuiceMapper {
    /// Every category the engine can emit. Kept as data (rather than relying on
    /// a `CaseIterable` conformance on the engine's enum) so the Juice layer
    /// never reaches into Engine/ to add conformances.
    public static let allCategories: [CommandEvent.Category] = [
        .singleMotion,
        .operatorMotion,
        .fullGrammar,
        .action,
        .mode,
        .commandLine,
    ]

    /// The graded table. Base intensities leave headroom for the combo boost
    /// (`JuiceCombo.Configuration.weight`) so a hot run tops out at exactly 1.0.
    private static let table: [CommandEvent.Category: (tier: JuiceTier, base: Double)] = [
        // You moved. A tick and a breath of glow.
        .singleMotion: (.whisper, 0.30),
        // You changed mode. The quietest thing in the app — Esc must never chirp.
        .mode: (.whisper, 0.15),
        // You edited with a motion (`dw`, `2dd`, `d$`).
        .operatorMotion: (.pop, 0.55),
        // A one-key action (`x`, `p`, `u`) — real, but not composed.
        .action: (.pop, 0.45),
        // `:w` / `:wq` — a small, satisfying commit.
        .commandLine: (.pop, 0.50),
        // The grammar clicked (`diw`, `ci"`, `ya(`). This is the moment the
        // whole app exists to produce.
        .fullGrammar: (.burst, 0.75),
    ]

    /// A count nudge, so `3dw` lands harder than `dw` without changing tier.
    private static let countStep = 0.03
    private static let countCeiling = 0.12

    /// Maps one completed command to its feedback.
    ///
    /// Returns `nil` only for a category with no table entry — i.e. a category
    /// added to the engine later (registers, macros, marks in World 2) that
    /// nobody has graded yet. Silence beats guessing a tier.
    public static func juice(for event: CommandEvent) -> JuiceEvent? {
        guard let row = table[event.category] else { return nil }
        let countBoost = min(Double(max(event.count - 1, 0)) * countStep, countCeiling)
        return JuiceEvent(tier: row.tier, intensity: row.base + countBoost)
    }

    /// Maps a batch (one `EditorSession.onEvents` delivery) to a single piece of
    /// feedback: the loudest member wins, so a batch never machine-guns the
    /// speakers. `nil` for an empty or entirely unmapped batch.
    public static func juice(for events: [CommandEvent]) -> JuiceEvent? {
        events
            .compactMap(juice(for:))
            .max { lhs, rhs in
                (lhs.tier, lhs.intensity) < (rhs.tier, rhs.intensity)
            }
    }

    /// True for the composed commands the combo tracker rewards: an operator
    /// applied to something (`dw`) or the full grammar (`diw`). Bare motions and
    /// mode flips are not "wrong" — they simply do not build the run.
    public static func isComposed(_ event: CommandEvent) -> Bool {
        switch event.category {
        case .operatorMotion, .fullGrammar: return true
        case .singleMotion, .action, .mode, .commandLine: return false
        }
    }
}
