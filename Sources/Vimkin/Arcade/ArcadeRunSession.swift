// ArcadeRunSession.swift — runs one gauntlet against the clock.
//
// The pressure twin of `DrillSession`, and the differences are the whole point:
//
//   • There IS a clock here, and it can end the run (`timeLimit`).
//   • Attempts are SCORED (`ArcadeScoring`) with a combo that a miss breaks.
//   • It writes NOTHING to `ProgressStore`. Mastery is measured in the calm
//     dojo, deliberately: folding hurried reps into the mastery score would let
//     the pressure surface distort the honest "where do I stand" signal the
//     mastery map reads. The arcade's only persistence is its own leaderboard.
//
// Judging itself is untouched — the same `Drill.evaluate` the dojo uses, so a
// near-miss still gets named rather than buzzed at.

import Foundation

public final class ArcadeRunSession {
    public let drills: [Drill]
    /// Calendar day this gauntlet belongs to.
    public let day: String
    /// False for a practice replay: identical drills, no leaderboard entry.
    public let isScored: Bool
    public let timeLimit: TimeInterval

    /// Index of the drill in front of the player.
    public private(set) var index: Int = 0
    public private(set) var hits: [ArcadeHit] = []
    public private(set) var score: Int = 0
    /// Flawless clears in a row right now. A miss resets it to 0.
    public private(set) var combo: Int = 0
    public private(set) var bestCombo: Int = 0
    public private(set) var attempts: Int = 0
    public private(set) var correctAttempts: Int = 0
    /// Wrong attempts on the drill currently in front of the player.
    public private(set) var currentMisses: Int = 0

    private let now: () -> Date
    private var startedAt: Date
    private var drillStartedAt: Date
    private var endedAt: Date?

    public init(
        drills: [Drill],
        day: String,
        isScored: Bool = true,
        timeLimit: TimeInterval = ArcadeRun.defaultTimeLimit,
        now: @escaping () -> Date = Date.init
    ) {
        self.drills = drills
        self.day = day
        self.isScored = isScored
        self.timeLimit = timeLimit
        self.now = now
        let start = now()
        self.startedAt = start
        self.drillStartedAt = start
        if drills.isEmpty { self.endedAt = start }
    }

    // MARK: - Clock

    /// (Re)starts both clocks — called when the run is actually put in front of
    /// the player, so time spent building the UI is not charged to them.
    public func begin() {
        let start = now()
        startedAt = start
        drillStartedAt = start
    }

    public var elapsed: TimeInterval {
        (endedAt ?? now()).timeIntervalSince(startedAt)
    }

    /// Seconds left on the gauntlet clock, floored at zero.
    public var remaining: TimeInterval {
        max(0, timeLimit - elapsed)
    }

    public var isTimeUp: Bool { remaining <= 0 }

    /// Finished when the drills run out, the clock runs out, or `end()` was called.
    public var isFinished: Bool {
        endedAt != nil || index >= drills.count || isTimeUp
    }

    // MARK: - Position

    public var currentDrill: Drill? {
        isFinished ? nil : drills[index]
    }

    public var drillsCleared: Int { hits.count }

    /// The most recent clear — what the HUD pops.
    public var lastHit: ArcadeHit? { hits.last }

    /// 0…1 through the gauntlet clock, for the timer bar.
    public var clockProgress: Double {
        guard timeLimit > 0 else { return 1 }
        return min(1, max(0, elapsed / timeLimit))
    }

    // MARK: - Attempts

    /// Judges one completed command. On a clear, scores it and advances; on a
    /// miss, breaks the combo and leaves the same drill up (the dojo's calm
    /// retry — here the cost is the clock, not a rejection).
    ///
    /// Returns nil once the run is over, so a late keystroke can never score.
    @discardableResult
    public func submit(_ attempt: DrillAttempt) -> DrillJudgement? {
        guard let drill = currentDrill else {
            endIfNeeded()
            return nil
        }

        let judgement = drill.evaluate(attempt)
        attempts += 1

        guard judgement.isCorrect else {
            currentMisses += 1
            combo = 0
            return judgement
        }

        correctAttempts += 1
        let elapsedOnDrill = now().timeIntervalSince(drillStartedAt)
        let comboLength: Int
        if currentMisses == 0 {
            combo += 1
            bestCombo = max(bestCombo, combo)
            comboLength = combo
        } else {
            combo = 0
            comboLength = 0
        }

        let points = ArcadeScoring.score(
            cleared: true,
            elapsed: elapsedOnDrill,
            misses: currentMisses,
            comboLength: comboLength
        )
        score += points
        hits.append(
            ArcadeHit(
                drillID: drill.id,
                commandID: drill.commandID,
                commandKeys: drill.commandKeys,
                elapsed: elapsedOnDrill,
                misses: currentMisses,
                comboLength: comboLength,
                points: points
            )
        )
        advance()
        return judgement
    }

    /// Moves past the current drill unscored. Breaks the combo — under pressure,
    /// bailing out is a choice with a cost (unlike the dojo, where it is free).
    public func skipCurrentDrill() {
        guard currentDrill != nil else { return }
        combo = 0
        advance()
    }

    /// Ends the run now — the player bailed out mid-gauntlet.
    public func end() {
        guard endedAt == nil else { return }
        endedAt = min(now(), startedAt.addingTimeInterval(timeLimit))
    }

    private func advance() {
        index += 1
        currentMisses = 0
        drillStartedAt = now()
        endIfNeeded()
    }

    private func endIfNeeded() {
        guard endedAt == nil else { return }
        if index >= drills.count {
            endedAt = now()
        } else if isTimeUp {
            // Stop the clock at the limit, never past it.
            endedAt = startedAt.addingTimeInterval(timeLimit)
        }
    }

    // MARK: - Reporting

    public func result() -> ArcadeRunResult {
        ArcadeRunResult(
            day: day,
            score: score,
            drillsCleared: drillsCleared,
            drillsPlanned: drills.count,
            attempts: attempts,
            correctAttempts: correctAttempts,
            bestCombo: bestCombo,
            duration: min(elapsed, timeLimit)
        )
    }
}
