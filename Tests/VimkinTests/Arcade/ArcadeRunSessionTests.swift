import Foundation
import Testing

@testable import Vimkin

@Suite("Arcade: running the gauntlet against the clock", .tags(.integration))
struct ArcadeRunSessionTests {

    private func makeSession(
        clock: TestClock,
        length: Int = 5,
        timeLimit: TimeInterval = ArcadeRun.defaultTimeLimit,
        scored: Bool = true
    ) throws -> ArcadeRunSession {
        let (builder, _) = try makeArcadeBuilder()
        let session = ArcadeRunSession(
            drills: builder.gauntlet(day: "2026-08-11", length: length),
            day: "2026-08-11",
            isScored: scored,
            timeLimit: timeLimit,
            now: { clock.now }
        )
        session.begin()
        return session
    }

    // MARK: - Scoring a run

    @Test("clearing every drill cleanly scores, builds combo, and ends the run")
    func cleanRunScores() throws {
        let clock = TestClock(now: day(0))
        let session = try makeSession(clock: clock, length: 5)
        #expect(session.drills.count == 5)

        for expected in 1...5 {
            clock.now.addTimeInterval(2)
            let judgement = clearCurrentDrill(session)
            #expect(judgement?.isCorrect == true)
            #expect(session.combo == expected)
        }

        #expect(session.isFinished)
        #expect(session.drillsCleared == 5)
        #expect(session.bestCombo == 5)
        #expect(session.attempts == 5)
        #expect(session.correctAttempts == 5)
        #expect(session.score > 0)
        // The combo multiplier means later clears are worth more than the first.
        let points = session.hits.map(\.points)
        #expect(points.last! > points.first!)
    }

    @Test("a miss breaks the combo, keeps the same drill up, and costs points")
    func missBreaksCombo() throws {
        let clock = TestClock(now: day(0))
        let session = try makeSession(clock: clock, length: 5)

        clock.now.addTimeInterval(2)
        clearCurrentDrill(session)
        clock.now.addTimeInterval(2)
        clearCurrentDrill(session)
        #expect(session.combo == 2)

        let fumbled = try #require(session.currentDrill)
        let verdict = missCurrentDrill(session)
        #expect(verdict?.isCorrect == false)
        #expect(session.combo == 0)
        #expect(session.currentMisses == 1)
        // Same drill still in front of the player — the calm retry, but the
        // clock is running.
        #expect(session.currentDrill?.id == fumbled.id)

        clock.now.addTimeInterval(1)
        clearCurrentDrill(session)
        let hit = try #require(session.hits.last)
        #expect(hit.misses == 1)
        #expect(hit.comboLength == 0)
        #expect(!hit.isFlawless)
        // A fumbled clear can never beat the floor of a clean one.
        #expect(Double(hit.points) < ArcadeScoring.slowestCleanClear)
    }

    @Test("a hurried fumble scores below an unhurried clean clear, in a real run")
    func accuracyDominatesInARealRun() throws {
        let cleanClock = TestClock(now: day(0))
        let clean = try makeSession(clock: cleanClock, length: 3)
        for _ in 0..<3 {
            cleanClock.now.addTimeInterval(30)  // deliberately slow
            clearCurrentDrill(clean)
        }

        let fumbleClock = TestClock(now: day(0))
        let fumbled = try makeSession(clock: fumbleClock, length: 3)
        for _ in 0..<3 {
            missCurrentDrill(fumbled)           // instant, and wrong
            clearCurrentDrill(fumbled)          // instant, and right
        }

        #expect(clean.drillsCleared == fumbled.drillsCleared)
        #expect(clean.score > fumbled.score)
    }

    // MARK: - The clock

    @Test("the run ends when the gauntlet clock runs out")
    func clockEndsTheRun() throws {
        let clock = TestClock(now: day(0))
        let session = try makeSession(clock: clock, length: 15, timeLimit: 180)

        clock.now.addTimeInterval(5)
        clearCurrentDrill(session)
        #expect(!session.isFinished)
        #expect(session.remaining == 175)

        clock.now.addTimeInterval(200)
        #expect(session.isTimeUp)
        #expect(session.isFinished)
        #expect(session.remaining == 0)
        #expect(session.currentDrill == nil)

        // A late keystroke cannot score after the horn.
        let scoreAtHorn = session.score
        let stale = try #require(replay("dw", on: session.drills[1]))
        #expect(session.submit(stale) == nil)
        #expect(session.score == scoreAtHorn)
        #expect(session.result().duration == 180, "duration is clamped to the limit")
    }

    @Test("bailing out mid-gauntlet ends the run where it stood")
    func endStopsTheRun() throws {
        let clock = TestClock(now: day(0))
        let session = try makeSession(clock: clock, length: 8)
        clock.now.addTimeInterval(3)
        clearCurrentDrill(session)
        clock.now.addTimeInterval(4)
        session.end()

        #expect(session.isFinished)
        let result = session.result()
        #expect(result.drillsCleared == 1)
        #expect(result.drillsPlanned == 8)
        #expect(abs(result.duration - 7) < 0.001)
    }

    @Test("skipping costs the combo but never points")
    func skipBreaksCombo() throws {
        let clock = TestClock(now: day(0))
        let session = try makeSession(clock: clock, length: 5)
        clock.now.addTimeInterval(2)
        clearCurrentDrill(session)
        let scoreBefore = session.score

        session.skipCurrentDrill()
        #expect(session.combo == 0)
        #expect(session.score == scoreBefore)
        #expect(session.drillsCleared == 1)
    }

    @Test("an empty gauntlet is finished on arrival and reports honestly")
    func emptyGauntlet() {
        let clock = TestClock(now: day(0))
        let session = ArcadeRunSession(
            drills: [], day: "2026-08-11", timeLimit: 180, now: { clock.now }
        )
        #expect(session.isFinished)
        #expect(session.currentDrill == nil)
        let result = session.result()
        #expect(result.score == 0)
        #expect(result.drillsPlanned == 0)
        #expect(result.accuracy == 0)
    }

    @Test("the result carries the run's shape")
    func resultShape() throws {
        let clock = TestClock(now: day(0))
        let session = try makeSession(clock: clock, length: 4)
        clock.now.addTimeInterval(2)
        clearCurrentDrill(session)
        missCurrentDrill(session)
        clock.now.addTimeInterval(2)
        clearCurrentDrill(session)
        session.end()

        let result = session.result()
        #expect(result.day == "2026-08-11")
        #expect(result.drillsCleared == 2)
        #expect(result.drillsPlanned == 4)
        #expect(result.attempts == 3)
        #expect(result.correctAttempts == 2)
        #expect(result.accuracyPercent == 67)
        #expect(result.bestCombo == 1)
    }
}
