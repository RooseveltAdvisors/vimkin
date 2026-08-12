import Foundation
import Testing

@testable import Vimkin

@Suite("Arcade: the calendar day IS the seed", .tags(.unit))
struct DailyRunSeedTests {

    // MARK: - Day keys

    @Test("a date maps to its calendar-day key")
    func dayKey() {
        #expect(ArcadeDay.key(for: day(0), calendar: testCalendar) == "2026-01-01")
        #expect(ArcadeDay.key(for: day(40), calendar: testCalendar) == "2026-02-10")
    }

    @Test("day arithmetic walks the calendar in both directions")
    func dayArithmetic() {
        #expect(ArcadeDay.day("2026-03-01", offsetBy: -1, calendar: testCalendar) == "2026-02-28")
        #expect(ArcadeDay.day("2026-12-31", offsetBy: 1, calendar: testCalendar) == "2027-01-01")
        #expect(ArcadeDay.day("2026-01-01", offsetBy: 0, calendar: testCalendar) == "2026-01-01")
    }

    // MARK: - Seed stability

    @Test("the seed is a pure function of the day, and differs between days")
    func seedIsStableAndDistinct() {
        #expect(ArcadeDay.seed(forDay: "2026-08-11") == ArcadeDay.seed(forDay: "2026-08-11"))

        // 400 consecutive days: every seed distinct. (A per-process hash would
        // still pass this — the cross-launch guarantee is the fixed constant
        // below, which pins the FNV-1a output itself.)
        var seeds: Set<UInt64> = []
        var cursor = "2026-01-01"
        for _ in 0..<400 {
            seeds.insert(ArcadeDay.seed(forDay: cursor))
            cursor = ArcadeDay.day(cursor, offsetBy: 1, calendar: testCalendar)!
        }
        #expect(seeds.count == 400)
    }

    @Test("the seed is pinned — it must survive an app relaunch, not just a run")
    func seedIsPinnedAcrossLaunches() {
        // `String.hashValue` is seeded per process; this literal is the proof
        // the arcade uses a stable hash instead. If this ever changes, every
        // player's "today" quietly becomes a different gauntlet.
        #expect(ArcadeDay.seed(forDay: "2026-08-11") == 14_636_156_114_422_409_149)
    }
}
