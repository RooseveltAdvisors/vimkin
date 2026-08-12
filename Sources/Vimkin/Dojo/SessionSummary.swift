// SessionSummary.swift — what the learner sees at the end of a dojo set.
//
// Accuracy-first (plan KTD 5): accuracy is the headline; time is reported as a
// gentle fact ("you practiced for 3 minutes"), never as a score, a rank, or a
// deadline that was missed. There is no "too slow" outcome anywhere.

import Foundation

/// One judged attempt inside a session.
public struct AttemptRecord: Equatable, Sendable {
    public let drillID: String
    public let commandID: String
    public let outcome: RepOutcome
    public let judgement: DrillJudgement
    /// Seconds spent on the drill when this attempt landed. Recorded, never
    /// used to fail anything.
    public let elapsed: TimeInterval

    public init(
        drillID: String,
        commandID: String,
        outcome: RepOutcome,
        judgement: DrillJudgement,
        elapsed: TimeInterval
    ) {
        self.drillID = drillID
        self.commandID = commandID
        self.outcome = outcome
        self.judgement = judgement
        self.elapsed = elapsed
    }

    public var isCorrect: Bool { outcome != .incorrect }
}

/// Per-command roll-up for one session.
public struct SkillSummary: Equatable, Sendable {
    public let commandID: String
    public let commandKeys: String
    public let attempts: Int
    public let correct: Int
    public let incorrect: Int
    /// Effective mastery score before the session (0-100).
    public let masteryBefore: Double
    /// Effective mastery score after the session (0-100).
    public let masteryAfter: Double

    public init(
        commandID: String,
        commandKeys: String,
        attempts: Int,
        correct: Int,
        incorrect: Int,
        masteryBefore: Double,
        masteryAfter: Double
    ) {
        self.commandID = commandID
        self.commandKeys = commandKeys
        self.attempts = attempts
        self.correct = correct
        self.incorrect = incorrect
        self.masteryBefore = masteryBefore
        self.masteryAfter = masteryAfter
    }

    /// 0…1; 0 when the skill saw no attempts.
    public var accuracy: Double {
        attempts > 0 ? Double(correct) / Double(attempts) : 0
    }

    /// Mastery movement across the session (positive = improved).
    public var masteryDelta: Double { masteryAfter - masteryBefore }
}

/// The end-of-session picture.
public struct SessionSummary: Equatable, Sendable {
    public let drillsPlanned: Int
    public let drillsCompleted: Int
    public let drillsSkipped: Int
    public let totalAttempts: Int
    public let correctAttempts: Int
    public let incorrectAttempts: Int
    /// Wall-clock seconds. Shown as encouragement, never as pressure.
    public let duration: TimeInterval
    /// Correct attempts that took longer than the generous speed threshold.
    /// Surfaced only as "these are getting there", never as a failure.
    public let unhurriedAttempts: Int
    /// Per-command roll-ups, ordered weakest accuracy first.
    public let skills: [SkillSummary]

    public init(
        drillsPlanned: Int,
        drillsCompleted: Int,
        drillsSkipped: Int,
        totalAttempts: Int,
        correctAttempts: Int,
        incorrectAttempts: Int,
        duration: TimeInterval,
        unhurriedAttempts: Int,
        skills: [SkillSummary]
    ) {
        self.drillsPlanned = drillsPlanned
        self.drillsCompleted = drillsCompleted
        self.drillsSkipped = drillsSkipped
        self.totalAttempts = totalAttempts
        self.correctAttempts = correctAttempts
        self.incorrectAttempts = incorrectAttempts
        self.duration = duration
        self.unhurriedAttempts = unhurriedAttempts
        self.skills = skills
    }

    /// Session accuracy, 0…1. Zero attempts ⇒ 0 (nothing was practiced).
    public var accuracy: Double {
        totalAttempts > 0 ? Double(correctAttempts) / Double(totalAttempts) : 0
    }

    /// Whole-percent accuracy for display.
    public var accuracyPercent: Int {
        Int((accuracy * 100).rounded())
    }

    /// The one skill worth naming as "practice this next": most wrong attempts,
    /// then lowest accuracy, then lowest mastery, then id (stable).
    /// `nil` when nothing went wrong — a clean set gets no scolding.
    public var weakestSkill: SkillSummary? {
        skills
            .filter { $0.incorrect > 0 }
            .sorted { lhs, rhs in
                if lhs.incorrect != rhs.incorrect { return lhs.incorrect > rhs.incorrect }
                if lhs.accuracy != rhs.accuracy { return lhs.accuracy < rhs.accuracy }
                if lhs.masteryAfter != rhs.masteryAfter { return lhs.masteryAfter < rhs.masteryAfter }
                return lhs.commandID < rhs.commandID
            }
            .first
    }

    /// Skills whose mastery went up this session, biggest gain first.
    public var improved: [SkillSummary] {
        skills
            .filter { $0.masteryDelta > 0.01 }
            .sorted { lhs, rhs in
                lhs.masteryDelta != rhs.masteryDelta
                    ? lhs.masteryDelta > rhs.masteryDelta
                    : lhs.commandID < rhs.commandID
            }
    }

    /// What to line up next: weakest accuracy first, then lowest mastery.
    public var practiceNext: [SkillSummary] {
        skills
            .sorted { lhs, rhs in
                if lhs.accuracy != rhs.accuracy { return lhs.accuracy < rhs.accuracy }
                if lhs.masteryAfter != rhs.masteryAfter { return lhs.masteryAfter < rhs.masteryAfter }
                return lhs.commandID < rhs.commandID
            }
    }

    public static let empty = SessionSummary(
        drillsPlanned: 0, drillsCompleted: 0, drillsSkipped: 0,
        totalAttempts: 0, correctAttempts: 0, incorrectAttempts: 0,
        duration: 0, unhurriedAttempts: 0, skills: []
    )
}
