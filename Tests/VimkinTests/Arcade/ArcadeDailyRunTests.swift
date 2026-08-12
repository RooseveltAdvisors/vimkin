import Foundation
import Testing

@testable import Vimkin

@Suite("Arcade: one run per day, and it never touches the mastery store")
@MainActor
struct ArcadeDailyRunTests {

    /// Plays a run to the end through the REAL seam — keys into the model's own
    /// editor, so `attachEditor` → `judge` → `presentCurrentDrill` all run, the
    /// same path the SwiftUI surface drives.
    private func play(_ model: ArcadeModel, clock: TestClock, limit: Int = 200) {
        var guardrail = 0
        while model.phase == .running, let drill = model.currentDrill, let editor = model.editor {
            guardrail += 1
            if guardrail > limit { break }
            clock.now.addTimeInterval(2)
            editor.feed(keys: drill.solutionKeys)
            model.tick()
        }
        if model.phase == .running { model.endRun() }
    }

    /// Starts today's scored run and plays it to the end.
    private func playToday(_ model: ArcadeModel, clock: TestClock) {
        model.startDailyRun()
        play(model, clock: clock)
    }

    // MARK: - One run per day

    @Test("completing today records ONE run and then shows the come-back-tomorrow state")
    func oneRunPerDay() throws {
        let clock = TestClock(now: day(0))
        let (model, _, board) = try makeArcadeModel(clock: clock, length: 4)

        #expect(model.canPlayScoredRun)
        playToday(model, clock: clock)

        #expect(model.phase == .result)
        #expect(model.lastResultWasRecorded)
        let recorded = try #require(board.result(day: model.today))
        #expect(recorded.score > 0)
        #expect(board.runCount == 1)
        #expect(!model.canPlayScoredRun)

        // Re-entering the arcade shows the RECORDED result, does not re-score.
        model.reset()
        #expect(model.phase == .idle)
        model.startDailyRun()
        #expect(model.phase == .result)
        #expect(model.session == nil, "no new run was started")
        #expect(model.lastResult == recorded)
        #expect(!model.lastResultWasRecorded, "already-on-the-board is not a fresh record")
        #expect(board.runCount == 1)
        #expect(board.result(day: model.today) == recorded)
    }

    @Test("a practice replay is the same gauntlet, unscored, and leaves the board alone")
    func practiceReplayIsUnscored() throws {
        let clock = TestClock(now: day(0))
        let (model, _, board) = try makeArcadeModel(clock: clock, length: 4)
        playToday(model, clock: clock)
        let recorded = try #require(board.result(day: model.today))

        model.reset()
        model.startPracticeRun()
        #expect(model.phase == .running)
        let practice = try #require(model.session)
        #expect(!practice.isScored)
        // Identical gauntlet — practice is a replay of today, not a new draw.
        #expect(practice.drills.map(\.id) == model.todaysGauntlet.map(\.id))

        play(model, clock: clock)

        #expect(model.phase == .result)
        #expect(!model.lastResultWasRecorded)
        #expect(board.runCount == 1, "the board still holds exactly today's one scored run")
        #expect(board.result(day: model.today) == recorded, "the recorded score is untouched")
    }

    @Test("the store refuses a second run for a day even if asked directly")
    func storeIsTheStructuralBackstop() {
        let board = makeArcadeLeaderboard()
        let first = arcadeResult(day: "2026-08-11", score: 900)
        #expect(board.record(first))
        #expect(!board.record(arcadeResult(day: "2026-08-11", score: 5000)))
        #expect(board.result(day: "2026-08-11") == first)
        #expect(board.runCount == 1)
        #expect(board.bestScore == 900, "a refused run cannot poison best/average")
        #expect(board.averageScore == 900)
    }

    @Test("tomorrow is playable again, with a different gauntlet")
    func tomorrowIsANewRun() throws {
        let clock = TestClock(now: day(0))
        let (model, _, board) = try makeArcadeModel(clock: clock, length: 4)
        let todaysDrills = model.todaysGauntlet.map(\.id)
        playToday(model, clock: clock)
        #expect(!model.canPlayScoredRun)

        clock.advance(days: 1)
        model.reset()
        #expect(model.canPlayScoredRun)
        #expect(model.todaysGauntlet.map(\.id) != todaysDrills)

        playToday(model, clock: clock)
        #expect(board.runCount == 2)
        #expect(board.dailyStreak(endingOn: model.today) == 2)
    }

    @Test("bailing out still counts as today's run — you played")
    func bailingOutStillCountsAsPlayed() throws {
        let clock = TestClock(now: day(0))
        let (model, _, board) = try makeArcadeModel(clock: clock, length: 6)
        model.startDailyRun()
        clock.now.addTimeInterval(3)
        model.endRun()

        #expect(model.phase == .result)
        #expect(board.runCount == 1)
        #expect(!model.canPlayScoredRun)
    }

    // MARK: - Store isolation

    @Test("an arcade run NEVER mutates mastery, unlocks, XP, streaks or progress.json")
    func arcadeNeverWritesToProgressStore() throws {
        let clock = TestClock(now: day(0))
        let directory = temporaryDirectory()
        let store = ProgressStore(
            directory: directory,
            alternateDirectories: [],
            now: { clock.now },
            calendar: testCalendar
        )
        for id in arcadeUnlocked { store.markLessonCompleted(commandID: id) }
        // Give it real, non-trivial content to corrupt.
        practiceCorrect(store, "motion.word-forward", times: 4)
        store.recordRep(commandID: "grammar.delete-inner-word", outcome: .incorrect)
        store.awardXP(for: .fullGrammar)

        let stateBefore = store.state
        let bytesBefore = try Data(contentsOf: store.fileURL)
        let masteryBefore = arcadeUnlocked.map { store.masteryScore(commandID: $0) }
        let statesBefore = arcadeUnlocked.map { store.masteryState(commandID: $0) }

        let board = ArcadeLeaderboardStore(directory: directory, calendar: testCalendar)
        let (model, _, _) = try makeArcadeModel(
            clock: clock, store: store, leaderboard: board, length: 6
        )
        playToday(model, clock: clock)
        // …and a practice replay on top, with deliberate misses.
        model.reset()
        model.startPracticeRun()
        model.editor?.feed(keys: "j")   // a deliberate miss
        play(model, clock: clock)

        #expect(board.runCount == 1, "the run really happened")
        let bytesAfter = try Data(contentsOf: store.fileURL)
        #expect(store.state == stateBefore, "ProgressStore state mutated")
        #expect(bytesAfter == bytesBefore, "progress.json was rewritten")
        #expect(arcadeUnlocked.map { store.masteryScore(commandID: $0) } == masteryBefore)
        #expect(arcadeUnlocked.map { store.masteryState(commandID: $0) } == statesBefore)
        #expect(store.unlockedCommands == Set(arcadeUnlocked))
        #expect(store.totalXP == stateBefore.totalXP)
        #expect(store.state.practiceDays == stateBefore.practiceDays)
    }

    @Test("nothing unlocked ⇒ an honest empty arcade, not a crash")
    func emptyArcadeIsHonest() throws {
        let clock = TestClock(now: day(0))
        let (model, _, board) = try makeArcadeModel(unlocking: [], clock: clock, length: 6)
        #expect(!model.isReady)
        #expect(model.todaysGauntlet.isEmpty)

        model.startDailyRun()
        #expect(model.phase == .result)
        #expect(model.lastResult?.score == 0)
        #expect(model.lastResult?.drillsPlanned == 0)
        // An empty gauntlet is NOT a run: it must not burn the day or drop a 0
        // on the board, or finishing a lesson later would find today spent.
        #expect(board.runCount == 0)
        #expect(!model.lastResultWasRecorded)
        #expect(model.canPlayScoredRun)
    }
}
