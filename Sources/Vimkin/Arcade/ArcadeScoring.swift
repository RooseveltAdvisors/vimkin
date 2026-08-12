// ArcadeScoring.swift — the ONE place in Vimkin where speed counts (plan KTD 5).
//
// The dojo is calm: no clock, no deadline, no "too slow". The arcade is the
// deliberate opposite — a three-minute gauntlet with a visible timer. But the
// pedagogy does not invert with the pressure: ACCURACY STILL DOMINATES.
//
// The scoring shape, and why:
//
//     points = cleared ? multiplier × max(floor, base + speed − misses×penalty)
//                      : 0
//
//   • `base` is paid for correctness ALONE — clearing a drill after three
//     minutes of thinking still earns more than any drill you got wrong.
//   • `speed` is a CONTINUOUS decay `exp(−t/τ)`, never a threshold bonus. A
//     3.9s answer and a 4.1s answer differ by a hair, not by a cliff.
//   • `missPenalty > speedBonusCeiling` — this single inequality is what makes
//     accuracy dominate: the most speed can ever pay (60) is less than what one
//     wrong keystroke costs (70), so no amount of hurrying buys back a miss.
//   • The combo multiplier applies to FLAWLESS clears only. A drill you fumbled
//     scores at ×1 no matter how hot the run was, so a fumbled-but-fast drill
//     can never out-score a clean-but-slow one at ANY combo length.
//
// Everything here is a pure function of its arguments — no clocks, no state.

import Foundation

public enum ArcadeScoring {
    // MARK: - Tunables

    /// Paid for clearing a drill at all, regardless of how long it took.
    public static let basePoints: Double = 100
    /// The most a fast answer can ever add on top of `basePoints`.
    public static let speedBonusCeiling: Double = 60
    /// Speed decay time-constant, in seconds. Continuous — no threshold cliff
    /// (see `rules/karpathy.md` §5).
    public static let speedTau: TimeInterval = 6
    /// Cost of one wrong attempt on a drill. Deliberately GREATER than
    /// `speedBonusCeiling`: that inequality is the accuracy-dominates invariant.
    public static let missPenalty: Double = 70
    /// A cleared drill is always worth something — you did solve it.
    public static let minimumClearedPoints: Double = 10
    /// Multiplier growth per extra flawless clear in a row.
    public static let comboStep: Double = 0.15
    /// Multiplier ceiling, so a long run cannot run away with the scoreboard.
    public static let comboCeiling: Double = 2.0

    // MARK: - Terms

    /// Speed bonus for an answer that took `elapsed` seconds: the ceiling decayed
    /// by `exp(−t/τ)`. Instant ⇒ full ceiling; slow ⇒ smoothly toward zero, but
    /// never negative.
    public static func speedBonus(elapsed: TimeInterval) -> Double {
        let seconds = max(0, elapsed)
        return speedBonusCeiling * exp(-seconds / speedTau)
    }

    /// The multiplier for a clear. `comboLength` is how many flawless clears in
    /// a row this one makes (1 for the first). A drill with any wrong attempt
    /// scores at ×1 — the combo is broken by the miss itself.
    public static func comboMultiplier(comboLength: Int, misses: Int = 0) -> Double {
        guard misses == 0, comboLength > 0 else { return 1 }
        return min(comboCeiling, 1 + comboStep * Double(comboLength - 1))
    }

    /// The multiplier, formatted for a HUD: `×1.3`, `×2`.
    ///
    /// Exists because the run's flame badge used to render the STREAK LENGTH
    /// with a `×` in front of it, which reads as the multiplier and is not: a
    /// streak of three is worth ×1.30, not ×3.
    public static func comboMultiplierLabel(comboLength: Int) -> String {
        let value = comboMultiplier(comboLength: comboLength)
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\u{00D7}\(Int(rounded))"
        }
        return String(format: "\u{00D7}%.2g", rounded)
    }

    // MARK: - Points

    /// Points for one drill.
    ///
    /// - Parameters:
    ///   - cleared: whether the drill was actually solved. An unsolved drill
    ///     (timed out, skipped, abandoned) scores zero — never negative.
    ///   - elapsed: seconds spent on the drill.
    ///   - misses: wrong attempts made before clearing it.
    ///   - comboLength: flawless clears in a row including this one (0 when the
    ///     run's combo is broken).
    public static func points(
        cleared: Bool,
        elapsed: TimeInterval,
        misses: Int,
        comboLength: Int
    ) -> Double {
        guard cleared else { return 0 }
        let raw = basePoints
            + speedBonus(elapsed: elapsed)
            - missPenalty * Double(max(0, misses))
        return max(minimumClearedPoints, raw) * comboMultiplier(comboLength: comboLength, misses: misses)
    }

    /// `points(...)` rounded to the whole number the HUD pops.
    public static func score(
        cleared: Bool,
        elapsed: TimeInterval,
        misses: Int,
        comboLength: Int
    ) -> Int {
        Int(points(cleared: cleared, elapsed: elapsed, misses: misses, comboLength: comboLength).rounded())
    }

    /// The floor of what a CLEAN clear can be worth, at any speed and combo ×1.
    /// Exposed because it is exactly the bar a fumbled drill can never clear —
    /// the accuracy-dominates invariant, as a number.
    public static var slowestCleanClear: Double { basePoints }

    /// The ceiling of what a FUMBLED clear can be worth, at any speed and any
    /// combo (fumbles score at ×1 by construction).
    public static var fastestFumbledClear: Double {
        max(minimumClearedPoints, basePoints + speedBonusCeiling - missPenalty)
    }
}
