import Foundation
@testable import Vimkin

// Shared scaffolding for the Arcade suites. `temporaryDirectory()`, `day(_:)`,
// `testCalendar`, `TestClock`, `makeDojoStore`, `replay(_:on:)` and
// `practiceCorrect` all come from the Progress/Dojo support files — same test
// target, so they are reused here rather than redefined.

/// The unlocked set the arcade suites draw their gauntlets from.
let arcadeUnlocked = [
    "motion.word-forward",
    "motion.line-end",
    "action.delete-char",
    "action.delete-line",
    "grammar.delete-inner-word",
]

/// A throwaway leaderboard store on a fixed calendar.
func makeArcadeLeaderboard(directory: URL? = nil) -> ArcadeLeaderboardStore {
    ArcadeLeaderboardStore(
        directory: directory ?? temporaryDirectory(),
        calendar: testCalendar
    )
}

/// A gauntlet builder over the real bundled content.
func makeArcadeBuilder(
    unlocking commandIDs: [String] = arcadeUnlocked,
    store: ProgressStore? = nil
) throws -> (builder: ArcadeRunBuilder, store: ProgressStore) {
    let (generator, store) = try makeDojoGenerator(unlocking: commandIDs, store: store)
    return (ArcadeRunBuilder(generator: generator), store)
}

/// An arcade model over the real content, on an injected clock.
@MainActor
func makeArcadeModel(
    unlocking commandIDs: [String] = arcadeUnlocked,
    clock: TestClock,
    store: ProgressStore? = nil,
    leaderboard: ArcadeLeaderboardStore? = nil,
    length: Int = 4,
    timeLimit: TimeInterval = ArcadeRun.defaultTimeLimit
) throws -> (model: ArcadeModel, store: ProgressStore, leaderboard: ArcadeLeaderboardStore) {
    let content = try dojoContent()
    let store = store ?? makeDojoStore(unlocking: commandIDs, on: clock.now)
    let board = leaderboard ?? makeArcadeLeaderboard()
    let model = ArcadeModel(
        database: content.database,
        documents: content.documents,
        store: store,
        leaderboard: board,
        now: { clock.now },
        calendar: testCalendar,
        length: length,
        timeLimit: timeLimit
    )
    return (model, store, board)
}

/// A run result with sensible filler, for leaderboard math.
func arcadeResult(day: String, score: Int, bestCombo: Int = 3) -> ArcadeRunResult {
    ArcadeRunResult(
        day: day,
        score: score,
        drillsCleared: 10,
        drillsPlanned: 15,
        attempts: 12,
        correctAttempts: 10,
        bestCombo: bestCombo,
        duration: 180
    )
}

/// Clears the drill in front of the player by replaying its solution keys.
@discardableResult
func clearCurrentDrill(_ session: ArcadeRunSession) -> DrillJudgement? {
    guard let drill = session.currentDrill,
          let attempt = replay(drill.solutionKeys, on: drill)
    else { return nil }
    return session.submit(attempt)
}

/// Fumbles the drill in front of the player with a deliberately wrong command.
@discardableResult
func missCurrentDrill(_ session: ArcadeRunSession, keys: String = "j") -> DrillJudgement? {
    guard let drill = session.currentDrill,
          let attempt = replay(keys, on: drill)
    else { return nil }
    return session.submit(attempt)
}
