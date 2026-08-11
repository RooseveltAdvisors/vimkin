import Foundation

// Pure model types for the Progress store. Foundation only — no AppKit/SwiftUI.

/// Complexity class of an executed command, used to tier XP awards (and, later,
/// juice feedback). Mirrors the CommandEvent complexity ladder from the plan:
/// single motion < operator+motion < full grammar (`diw`, `ci"`, ...).
///
/// Defined here (not in Engine) because U9 lands before U2's `CommandEvent` is
/// merged; when the engine lands, `CommandEvent` maps into this enum.
public enum CommandComplexity: String, Codable, Sendable, CaseIterable {
    case singleMotion = "single-motion"
    case operatorMotion = "operator-motion"
    case fullGrammar = "full-grammar"

    /// XP awarded for one successful execution of this complexity class.
    /// XP is celebratory only — it never gates anything (see `UnlockModel`).
    public var xpAward: Int {
        switch self {
        case .singleMotion: return 10
        case .operatorMotion: return 25
        case .fullGrammar: return 60
        }
    }
}

/// Outcome of a single practice repetition of a command.
public enum RepOutcome: String, Codable, Sendable {
    /// Accurate, at (or above) target speed.
    case correct
    /// Accurate but slow. Accuracy-first pedagogy: this still builds mastery,
    /// and costs far less than a wrong rep.
    case slowCorrect = "slow-correct"
    /// Wrong keystroke(s) for the target. Costs more than any correct rep.
    case incorrect
}

/// Derivable learning state of one command.
public enum MasteryState: String, Codable, Sendable {
    /// Never practiced.
    case unlearned
    /// Practiced, but has not yet reached the mastered threshold.
    case learning
    /// Effective score at or above the mastered threshold.
    case mastered
    /// Was mastered once, then decayed below the mastered threshold.
    /// Decay never drops a previously-mastered skill below the learned floor.
    case rusty
}

/// Per-command mastery record: an accuracy-weighted rolling score plus the
/// bookkeeping needed to apply calendar-day decay at read time.
public struct MasteryRecord: Codable, Equatable, Sendable {
    /// Rolling score 0-100 as of `lastPracticedDay` (decay is applied on read).
    public internal(set) var score: Double
    /// Calendar day ("yyyy-MM-dd") of the most recent rep.
    public internal(set) var lastPracticedDay: String
    /// True once the score has ever reached the mastered threshold.
    /// Enables the `rusty` state and the learned decay floor.
    public internal(set) var everMastered: Bool
    /// Total reps recorded (all outcomes).
    public internal(set) var repCount: Int
}

/// Streak bookkeeping. "Any practice today" counts; grace days absorb misses.
public struct StreakState: Codable, Equatable, Sendable {
    /// Number of practiced days in the current unbroken (or grace-bridged) run.
    public internal(set) var current: Int
    /// Banked grace days (start 2, cap 2, regenerate 1 per 7 consecutive
    /// practiced days). A missed day consumes one instead of breaking the streak.
    public internal(set) var graceBank: Int
    /// Consecutive practiced days with NO misses (grace-bridged gaps reset
    /// this), driving grace regeneration.
    public internal(set) var consecutiveRun: Int
    /// Calendar day ("yyyy-MM-dd") of the most recent practice, if any.
    public internal(set) var lastPracticeDay: String?

    public static let initial = StreakState(
        current: 0, graceBank: 2, consecutiveRun: 0, lastPracticeDay: nil
    )
}

/// Trend data for progress-over-perfection messaging ("32 of the last 40 days").
public struct PracticeTrend: Equatable, Sendable {
    /// Days with any practice inside the window.
    public let practicedDays: Int
    /// Window size in days (window ends on, and includes, "today").
    public let windowDays: Int
}

/// The complete persisted state — one JSON document.
public struct ProgressState: Codable, Equatable, Sendable {
    public internal(set) var schemaVersion: Int
    /// Per-command mastery, keyed by `VimCommand.id`.
    public internal(set) var mastery: [String: MasteryRecord]
    /// Command ids whose lesson has been completed (written by the tutorial).
    /// This — and only this — drives unlocks.
    public internal(set) var completedLessons: Set<String>
    /// Additive, celebratory XP. Never read by unlock logic.
    public internal(set) var totalXP: Int
    public internal(set) var streak: StreakState
    /// Every calendar day ("yyyy-MM-dd") with any practice — trend source.
    public internal(set) var practiceDays: Set<String>

    public static let currentSchemaVersion = 1

    public static let empty = ProgressState(
        schemaVersion: currentSchemaVersion,
        mastery: [:],
        completedLessons: [],
        totalXP: 0,
        streak: .initial,
        practiceDays: []
    )
}
