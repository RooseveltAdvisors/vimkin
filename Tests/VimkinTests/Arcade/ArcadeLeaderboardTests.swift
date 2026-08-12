import Foundation
import Testing

@testable import Vimkin

@Suite("Arcade: the self-leaderboard")
struct ArcadeLeaderboardTests {

    // MARK: - Best / average math

    @Test("best and average are correct on a known series")
    func bestAndAverage() {
        let board = makeArcadeLeaderboard()
        #expect(board.bestScore == nil)
        #expect(board.averageScore == nil, "an empty board has NO average — never a 0")
        #expect(board.runCount == 0)

        let scores = [1200, 950, 1480, 1100, 770]  // sum 5500, mean 1100
        for (offset, score) in scores.enumerated() {
            board.record(arcadeResult(day: "2026-08-0\(offset + 1)", score: score))
        }

        #expect(board.runCount == 5)
        #expect(board.bestScore == 1480)
        #expect(board.bestRun?.day == "2026-08-03")
        #expect(board.averageScore == 1100)
        #expect(board.isPersonalBest(score: 1481))
        #expect(!board.isPersonalBest(score: 1480), "tying your best is not beating it")
    }

    @Test("the earliest day keeps a tied record")
    func tiedBestGoesToWhoeverSetItFirst() {
        let board = makeArcadeLeaderboard()
        board.record(arcadeResult(day: "2026-08-05", score: 1000))
        board.record(arcadeResult(day: "2026-08-02", score: 1000))
        #expect(board.bestRun?.day == "2026-08-02")
    }

    @Test("recent runs come back most-recent day first")
    func recentRunsSort() {
        let board = makeArcadeLeaderboard()
        for day in ["2026-08-01", "2026-08-04", "2026-08-02", "2026-08-03"] {
            board.record(arcadeResult(day: day, score: 500))
        }
        #expect(board.recentRuns(limit: 3).map(\.day) == ["2026-08-04", "2026-08-03", "2026-08-02"])
        #expect(board.recentRuns(limit: 99).count == 4)
        #expect(board.recentRuns(limit: 0).isEmpty)
    }

    // MARK: - Days-played streak

    @Test("the days-played streak counts back through consecutive days")
    func streakCountsConsecutiveDays() {
        let board = makeArcadeLeaderboard()
        for day in ["2026-08-08", "2026-08-09", "2026-08-10", "2026-08-11"] {
            board.record(arcadeResult(day: day, score: 500))
        }
        #expect(board.dailyStreak(endingOn: "2026-08-11") == 4)

        // A gap stops the count.
        board.record(arcadeResult(day: "2026-08-05", score: 500))
        #expect(board.dailyStreak(endingOn: "2026-08-11") == 4)
    }

    @Test("today being unplayed does not break the streak — a whole missed day does")
    func streakToleratesAYoungDay() {
        let board = makeArcadeLeaderboard()
        board.record(arcadeResult(day: "2026-08-09", score: 500))
        board.record(arcadeResult(day: "2026-08-10", score: 500))

        // Today (the 11th) is not played yet: the streak still reads 2.
        #expect(board.dailyStreak(endingOn: "2026-08-11") == 2)
        // A whole day has now gone by unplayed: broken.
        #expect(board.dailyStreak(endingOn: "2026-08-12") == 0)
    }

    @Test("an empty board has no streak")
    func emptyStreak() {
        #expect(makeArcadeLeaderboard().dailyStreak(endingOn: "2026-08-11") == 0)
    }

    // MARK: - Persistence

    @Test("the board round-trips across store instances")
    func persistenceRoundTrip() {
        let directory = temporaryDirectory()
        let first = ArcadeLeaderboardStore(directory: directory, calendar: testCalendar)
        first.record(arcadeResult(day: "2026-08-10", score: 880, bestCombo: 6))
        first.record(arcadeResult(day: "2026-08-11", score: 1320, bestCombo: 9))

        let second = ArcadeLeaderboardStore(directory: directory, calendar: testCalendar)
        #expect(second.runCount == 2)
        #expect(second.bestScore == 1320)
        #expect(second.averageScore == 1100)
        #expect(second.result(day: "2026-08-10")?.bestCombo == 6)
        #expect(second.state == first.state)
        #expect(second.dailyStreak(endingOn: "2026-08-11") == 2)
    }

    @Test("a corrupt board file yields a fresh board, never a crash")
    func corruptFileDegradesGracefully() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json at all".utf8).write(
            to: directory.appendingPathComponent(ArcadeLeaderboardStore.fileName)
        )

        let board = ArcadeLeaderboardStore(directory: directory, calendar: testCalendar)
        #expect(board.runCount == 0)
        board.record(arcadeResult(day: "2026-08-11", score: 400))
        #expect(board.runCount == 1)
    }

    @Test("the board lives in its own file, beside progress.json")
    func ownFile() {
        let directory = temporaryDirectory()
        let board = ArcadeLeaderboardStore(directory: directory, calendar: testCalendar)
        #expect(board.fileURL.lastPathComponent == "arcade.json")
        #expect(board.fileURL.lastPathComponent != ProgressStore.fileName)
        #expect(board.fileURL.deletingLastPathComponent() == directory)
    }
}
