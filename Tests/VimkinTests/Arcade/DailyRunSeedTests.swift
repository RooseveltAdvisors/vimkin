import Foundation
import Testing

@testable import Vimkin

@Suite("Arcade: the calendar day IS the seed")
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

    // MARK: - Gauntlet determinism

    @Test("the same day yields the IDENTICAL drill sequence")
    func sameDaySameRun() throws {
        let (builder, _) = try makeArcadeBuilder()
        let first = builder.gauntlet(day: "2026-08-11", length: 12)
        let second = builder.gauntlet(day: "2026-08-11", length: 12)

        #expect(first.count == 12)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.commandID) == second.map(\.commandID))
        #expect(first.map(\.start) == second.map(\.start))
        #expect(first.map(\.instruction) == second.map(\.instruction))
    }

    @Test("a rebuilt generator yields the identical sequence (survives relaunch)")
    func survivesAFreshGenerator() throws {
        let (builderA, _) = try makeArcadeBuilder()
        let (builderB, _) = try makeArcadeBuilder()
        #expect(
            builderA.gauntlet(day: "2026-08-11", length: 12).map(\.id)
                == builderB.gauntlet(day: "2026-08-11", length: 12).map(\.id)
        )
    }

    @Test("a different day yields a different sequence")
    func differentDayDifferentRun() throws {
        let (builder, _) = try makeArcadeBuilder()
        let today = builder.gauntlet(day: "2026-08-11", length: 12)
        let tomorrow = builder.gauntlet(day: "2026-08-12", length: 12)
        #expect(today.map(\.id) != tomorrow.map(\.id))

        // Not just one lucky pair: across 30 consecutive days every gauntlet is
        // distinct from every other.
        var signatures: Set<String> = []
        var cursor = "2026-08-01"
        for _ in 0..<30 {
            signatures.insert(builder.gauntlet(day: cursor, length: 12).map(\.id).joined(separator: "|"))
            cursor = ArcadeDay.day(cursor, offsetBy: 1, calendar: testCalendar)!
        }
        #expect(signatures.count == 30)
    }

    @Test("practising the dojo does NOT rewrite today's gauntlet")
    func masteryDoesNotSteerTheArcade() throws {
        let store = makeDojoStore(unlocking: arcadeUnlocked)
        let (builder, _) = try makeArcadeBuilder(store: store)
        let before = builder.gauntlet(day: "2026-08-11", length: 12).map(\.id)

        // Hammer mastery all over the place — the adaptive dojo generator would
        // pick differently after this; the arcade must not.
        practiceCorrect(store, "motion.word-forward", times: 8)
        for _ in 0..<5 { store.recordRep(commandID: "grammar.delete-inner-word", outcome: .incorrect) }

        #expect(builder.gauntlet(day: "2026-08-11", length: 12).map(\.id) == before)
    }

    @Test("the unlock gate still holds inside the arcade")
    func onlyUnlockedCommandsAppear() throws {
        let (builder, _) = try makeArcadeBuilder()
        let unlocked = Set(arcadeUnlocked)
        var cursor = "2026-01-01"
        for _ in 0..<40 {
            let ids = Set(builder.gauntlet(day: cursor, length: 12).map(\.commandID))
            #expect(ids.isSubset(of: unlocked), "leaked locked commands: \(ids.subtracting(unlocked))")
            cursor = ArcadeDay.day(cursor, offsetBy: 1, calendar: testCalendar)!
        }
    }

    @Test("nothing unlocked ⇒ no gauntlet (never a locked fallback)")
    func emptyPoolYieldsNoGauntlet() throws {
        let (builder, _) = try makeArcadeBuilder(unlocking: [])
        #expect(builder.gauntlet(day: "2026-08-11", length: 12).isEmpty)
    }

    @Test("every drill in a gauntlet has a unique id")
    func gauntletIDsAreUnique() throws {
        let (builder, _) = try makeArcadeBuilder()
        var cursor = "2026-08-01"
        for _ in 0..<15 {
            let drills = builder.gauntlet(day: cursor, length: 15)
            #expect(Set(drills.map(\.id)).count == drills.count)
            cursor = ArcadeDay.day(cursor, offsetBy: 1, calendar: testCalendar)!
        }
    }

    @Test("every drill in a gauntlet is actually solvable by its own keys")
    func gauntletIsSolvable() throws {
        let (builder, _) = try makeArcadeBuilder()
        for drill in builder.gauntlet(day: "2026-08-11", length: 15) {
            let attempt = try #require(replay(drill.solutionKeys, on: drill))
            #expect(drill.succeeds(attempt), "unsolvable arcade drill: \(drill.id)")
        }
    }
}
