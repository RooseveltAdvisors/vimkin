// DrillSession.swift — runs a drill list, judges attempts, records reps into
// the mastery store, and produces the end-of-set summary.
//
// THE ACCURACY-FIRST RULE (plan KTD 5), enforced here:
//   • There is no countdown, no deadline, and no API that can fail a drill for
//     slowness. `slowAfter` only chooses between `.correct` and `.slowCorrect`
//     — both of which BUILD mastery (see MasteryModel).
//   • A skipped drill records nothing at all: skipping is not a wrong rep.

import Foundation

public final class DrillSession {
    /// Generous speed threshold. Above it a correct answer is still correct —
    /// it is recorded as `.slowCorrect`, which still raises mastery.
    public static let defaultSlowAfter: TimeInterval = 20

    public let drills: [Drill]
    /// Index of the drill currently in front of the learner.
    public private(set) var index: Int = 0
    public private(set) var attempts: [AttemptRecord] = []
    public private(set) var skipped: Int = 0

    private let store: ProgressStore
    private let now: () -> Date
    private let slowAfter: TimeInterval
    private let startedAt: Date
    private var drillStartedAt: Date
    private var finishedAt: Date?
    private let masteryBefore: [String: Double]

    public init(
        drills: [Drill],
        store: ProgressStore,
        now: @escaping () -> Date = Date.init,
        slowAfter: TimeInterval = DrillSession.defaultSlowAfter
    ) {
        self.drills = drills
        self.store = store
        self.now = now
        self.slowAfter = slowAfter
        let start = now()
        self.startedAt = start
        self.drillStartedAt = start
        self.masteryBefore = Dictionary(
            uniqueKeysWithValues: Set(drills.map(\.commandID))
                .map { ($0, store.masteryScore(commandID: $0)) }
        )
        if drills.isEmpty { self.finishedAt = start }
    }

    // MARK: - Position

    public var currentDrill: Drill? {
        index < drills.count ? drills[index] : nil
    }

    public var isFinished: Bool { index >= drills.count }

    /// Drills fully solved (planned − remaining − skipped).
    public var completedCount: Int { index - skipped }

    /// 0…1 progress through the set, for the progress dots.
    public var progress: Double {
        drills.isEmpty ? 1 : Double(index) / Double(drills.count)
    }

    /// Per-drill outcome so far, for the progress dots: nil = not reached.
    public var dotStates: [DrillDotState] {
        drills.enumerated().map { offset, drill in
            if offset > index { return .upcoming }
            if offset == index && !isFinished { return .current }
            let drillAttempts = attempts.filter { $0.drillID == drill.id }
            if drillAttempts.isEmpty { return .skipped }
            return drillAttempts.contains(where: { !$0.isCorrect }) ? .struggled : .clean
        }
    }

    /// Restarts the clock for the drill in front of the learner. Called when a
    /// drill is presented (and after a reset), so elapsed time reflects the
    /// current attempt rather than how long the app sat open.
    public func beginCurrentDrill() {
        drillStartedAt = now()
    }

    // MARK: - Attempts

    /// Judges one completed command, records the rep, and advances on success.
    /// Returns nil when the session is already finished.
    @discardableResult
    public func submit(_ attempt: DrillAttempt) -> DrillJudgement? {
        guard let drill = currentDrill else { return nil }

        let judgement = drill.evaluate(attempt)
        let elapsed = now().timeIntervalSince(drillStartedAt)
        let outcome: RepOutcome = judgement.isCorrect
            ? (elapsed > slowAfter ? .slowCorrect : .correct)
            : .incorrect

        store.recordRep(commandID: drill.commandID, outcome: outcome)
        attempts.append(
            AttemptRecord(
                drillID: drill.id,
                commandID: drill.commandID,
                outcome: outcome,
                judgement: judgement,
                elapsed: elapsed
            )
        )

        if judgement.isCorrect { advance() }
        return judgement
    }

    /// Moves past the current drill without judging it. Records nothing —
    /// skipping is a choice, not a mistake.
    public func skipCurrentDrill() {
        guard currentDrill != nil else { return }
        skipped += 1
        advance()
    }

    private func advance() {
        index += 1
        drillStartedAt = now()
        if isFinished { finishedAt = now() }
    }

    // MARK: - Reporting

    /// Accuracy for one command inside this session (0…1; 0 with no attempts).
    public func accuracy(forCommandID commandID: String) -> Double {
        let own = attempts.filter { $0.commandID == commandID }
        guard !own.isEmpty else { return 0 }
        return Double(own.filter(\.isCorrect).count) / Double(own.count)
    }

    public func summary() -> SessionSummary {
        let correct = attempts.filter(\.isCorrect).count
        let unhurried = attempts.filter { $0.outcome == .slowCorrect }.count

        var skills: [SkillSummary] = []
        for commandID in Set(attempts.map(\.commandID)) {
            let own: [AttemptRecord] = attempts.filter { $0.commandID == commandID }
            let correctCount: Int = own.filter { $0.isCorrect }.count
            let keys: String = drills.first { $0.commandID == commandID }?.commandKeys ?? ""
            skills.append(
                SkillSummary(
                    commandID: commandID,
                    commandKeys: keys,
                    attempts: own.count,
                    correct: correctCount,
                    incorrect: own.count - correctCount,
                    masteryBefore: masteryBefore[commandID] ?? 0,
                    masteryAfter: store.masteryScore(commandID: commandID)
                )
            )
        }
        skills.sort { lhs, rhs in
            lhs.accuracy != rhs.accuracy
                ? lhs.accuracy < rhs.accuracy
                : lhs.commandID < rhs.commandID
        }

        return SessionSummary(
            drillsPlanned: drills.count,
            drillsCompleted: completedCount,
            drillsSkipped: skipped,
            totalAttempts: attempts.count,
            correctAttempts: correct,
            incorrectAttempts: attempts.count - correct,
            duration: (finishedAt ?? now()).timeIntervalSince(startedAt),
            unhurriedAttempts: unhurried,
            skills: skills
        )
    }
}

/// Progress-dot state for one drill in the set.
public enum DrillDotState: Equatable, Sendable {
    case upcoming
    case current
    /// Solved with no wrong attempts.
    case clean
    /// Solved, but took a wrong turn on the way.
    case struggled
    case skipped
}
