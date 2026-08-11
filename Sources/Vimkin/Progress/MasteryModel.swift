import Foundation

/// Pure mastery math: accuracy-weighted rolling score with calendar-day decay.
/// All functions are deterministic; the store injects dates.
///
/// Tunables are named constants (plan: exact constants tuned in U6/U9 with
/// real play data) — every curve is continuous, no policy cliffs beyond the
/// two named state thresholds.
public enum MasteryModel {
    // MARK: - Tunables

    /// Effective score at or above this ⇒ mastered.
    public static let masteredThreshold: Double = 80
    /// Decay floor for a skill that has EVER been mastered: it may go rusty,
    /// but never drops below "learned" (plan rule).
    public static let learnedFloor: Double = 40
    /// Points of decay per unused calendar day (after the free days).
    public static let decayPerDay: Double = 2
    /// Unused days before decay starts (a weekend off is not punished).
    public static let decayFreeDays: Int = 2

    /// EWMA update: score moves toward `target` by fraction `rate`.
    /// Wrong reps pull hard toward 0; slow-correct reps pull gently toward a
    /// mid-high target — so a wrong rep always costs more than a slow one.
    static func update(for outcome: RepOutcome) -> (target: Double, rate: Double) {
        switch outcome {
        case .correct: return (target: 100, rate: 0.30)
        case .slowCorrect: return (target: 70, rate: 0.25)
        case .incorrect: return (target: 0, rate: 0.35)
        }
    }

    // MARK: - Score math

    /// The rolling score after one rep, from a pre-decayed current score.
    public static func updatedScore(from score: Double, outcome: RepOutcome) -> Double {
        let (target, rate) = update(for: outcome)
        return clamp(score + rate * (target - score))
    }

    /// Score after `daysSincePractice` unused calendar days.
    /// `everMastered` skills never decay below `learnedFloor`.
    public static func decayedScore(
        from score: Double, daysSincePractice: Int, everMastered: Bool
    ) -> Double {
        guard daysSincePractice > decayFreeDays else { return score }
        let decayingDays = Double(daysSincePractice - decayFreeDays)
        let floor = everMastered ? min(learnedFloor, score) : 0
        return clamp(max(score - decayPerDay * decayingDays, floor))
    }

    /// Learning state derived from an effective (already-decayed) score.
    public static func state(effectiveScore: Double, everMastered: Bool, repCount: Int) -> MasteryState {
        if repCount == 0 { return .unlearned }
        if effectiveScore >= masteredThreshold { return .mastered }
        return everMastered ? .rusty : .learning
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
