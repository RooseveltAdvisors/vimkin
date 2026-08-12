// ArcadeModels.swift — the value types the daily run and the self-leaderboard
// are built from. Foundation only; everything is Codable so a run result can
// round-trip through the arcade's own JSON store.

import Foundation

/// One cleared drill inside a run — what the HUD pops and the result screen
/// lists. Not persisted (the leaderboard keeps totals, not keystroke history).
public struct ArcadeHit: Equatable, Sendable, Identifiable {
    public let drillID: String
    public let commandID: String
    public let commandKeys: String
    /// Seconds spent on the drill.
    public let elapsed: TimeInterval
    /// Wrong attempts made before clearing it.
    public let misses: Int
    /// Flawless clears in a row including this one (0 when the combo is broken).
    public let comboLength: Int
    /// Points awarded, as shown.
    public let points: Int

    public var id: String { drillID }

    public init(
        drillID: String,
        commandID: String,
        commandKeys: String,
        elapsed: TimeInterval,
        misses: Int,
        comboLength: Int,
        points: Int
    ) {
        self.drillID = drillID
        self.commandID = commandID
        self.commandKeys = commandKeys
        self.elapsed = elapsed
        self.misses = misses
        self.comboLength = comboLength
        self.points = points
    }

    /// True when the drill was cleared first try.
    public var isFlawless: Bool { misses == 0 }
}

/// The recorded outcome of one day's scored run — the leaderboard row.
public struct ArcadeRunResult: Codable, Equatable, Sendable, Identifiable {
    /// Calendar day key ("yyyy-MM-dd"). One run per day, so this is the id.
    public let day: String
    public let score: Int
    public let drillsCleared: Int
    public let drillsPlanned: Int
    public let attempts: Int
    public let correctAttempts: Int
    public let bestCombo: Int
    /// Wall-clock seconds the run took.
    public let duration: TimeInterval

    public var id: String { day }

    public init(
        day: String,
        score: Int,
        drillsCleared: Int,
        drillsPlanned: Int,
        attempts: Int,
        correctAttempts: Int,
        bestCombo: Int,
        duration: TimeInterval
    ) {
        self.day = day
        self.score = score
        self.drillsCleared = drillsCleared
        self.drillsPlanned = drillsPlanned
        self.attempts = attempts
        self.correctAttempts = correctAttempts
        self.bestCombo = bestCombo
        self.duration = duration
    }

    /// Attempt accuracy, 0…1. Zero attempts ⇒ 0.
    public var accuracy: Double {
        attempts > 0 ? Double(correctAttempts) / Double(attempts) : 0
    }

    public var accuracyPercent: Int { Int((accuracy * 100).rounded()) }
}

/// Run-shape constants. A run is a ~3-minute gauntlet: a fixed drill list with
/// a hard clock, and whichever runs out first ends it.
public enum ArcadeRun {
    /// Drills lined up for one run. Sized so a fast player runs out of clock
    /// rather than out of drills.
    public static let defaultLength = 15
    /// The gauntlet clock, in seconds.
    public static let defaultTimeLimit: TimeInterval = 180
}
