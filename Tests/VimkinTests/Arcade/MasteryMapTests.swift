import Foundation
import Testing

@testable import Vimkin

@Suite("Mastery map: where do I stand")
struct MasteryMapTests {

    /// A store seeded into a known standing, on a known day:
    ///   • `motion.word-forward`    → MASTERED (practised hard, practised today)
    ///   • `action.delete-line`     → RUSTY    (was mastered, then left to decay)
    ///   • `grammar.delete-inner-word` → LEARNING (practised, never mastered)
    ///   • `motion.line-end`        → UNLEARNED (unlocked, never drilled)
    private func seededStore() -> (store: ProgressStore, clock: TestClock) {
        let clock = TestClock(now: day(0))
        let store = ProgressStore(
            directory: temporaryDirectory(),
            alternateDirectories: [],
            now: { clock.now },
            calendar: testCalendar
        )
        for id in arcadeUnlocked { store.markLessonCompleted(commandID: id) }

        // Day 0: master two commands.
        practiceCorrect(store, "motion.word-forward", times: 8)
        practiceCorrect(store, "action.delete-line", times: 8)
        // …and get one to "learning" without ever mastering it.
        store.recordRep(commandID: "grammar.delete-inner-word", outcome: .correct)
        store.recordRep(commandID: "grammar.delete-inner-word", outcome: .incorrect)

        // 30 days later: only the word motion gets kept up, so the delete-line
        // decays into rusty.
        clock.advance(days: 30)
        practiceCorrect(store, "motion.word-forward", times: 4)
        return (store, clock)
    }

    private func map() throws -> MasteryMap {
        let (store, _) = seededStore()
        return MasteryMap.build(database: try CommandDatabase.load(), store: store)
    }

    // MARK: - States

    @Test("a seeded store lands each command in the state its history implies")
    func statesMatchTheStore() throws {
        let map = try map()
        let byID = Dictionary(uniqueKeysWithValues: map.allSkills.map { ($0.commandID, $0) })

        #expect(byID["motion.word-forward"]?.state == .mastered)
        #expect(byID["action.delete-line"]?.state == .rusty)
        #expect(byID["grammar.delete-inner-word"]?.state == .learning)
        #expect(byID["motion.line-end"]?.state == .unlearned)
        #expect(byID["motion.line-end"]?.score == 0)
        #expect(byID["action.delete-char"]?.state == .unlearned)

        #expect(map.count(of: .mastered) == 1)
        #expect(map.count(of: .rusty) == 1)
        #expect(map.count(of: .learning) == 1)
        #expect(map.count(of: .unlearned) == 2)
        #expect(map.unlockedCount == arcadeUnlocked.count)
    }

    @Test("the rusty command is visually distinct — it is the one asking for a pass")
    func rustyIsTheCallToAction() throws {
        let map = try map()
        #expect(map.rustySkills.map(\.commandID) == ["action.delete-line"])
        #expect(map.allSkills.filter(\.needsAttention).count == 1)
    }

    // MARK: - Tier grouping

    @Test("commands land in the right curriculum tier buckets")
    func tierGrouping() throws {
        let database = try CommandDatabase.load()
        let map = try map()

        #expect(map.tiers.map(\.tier) == map.tiers.map(\.tier).sorted(), "tiers ascend")
        #expect(map.tiers.first?.title == "Survive")

        for group in map.tiers {
            // Every listed skill really belongs to this tier…
            for skill in group.skills {
                #expect(skill.tier == group.tier)
                #expect(database.command(id: skill.commandID)?.tier == group.tier)
            }
            // …and the bucket accounts for every command the database has there.
            #expect(group.totalCommands == database.commands(tier: group.tier).count)
            // Curriculum order within the tier.
            #expect(group.skills.map(\.lesson) == group.skills.map(\.lesson).sorted())
        }

        // Nothing is lost or double-counted across the buckets.
        #expect(map.allSkills.count + map.lockedCount == database.commands.count)
        #expect(Set(map.allSkills.map(\.commandID)).count == map.allSkills.count)
    }

    @Test("only UNLOCKED commands are listed; the rest are counted as the road ahead")
    func lockedCommandsAreCountedNotListed() throws {
        let map = try map()
        #expect(Set(map.allSkills.map(\.commandID)) == Set(arcadeUnlocked))
        #expect(map.lockedCount > 0)

        for group in map.tiers where group.isUntouched {
            #expect(group.skills.isEmpty)
            #expect(group.lockedCount == group.totalCommands)
            #expect(group.fill == 0)
        }
    }

    @Test("tier fill is the mean mastery of its unlocked skills")
    func tierFill() throws {
        let (store, _) = seededStore()
        let database = try CommandDatabase.load()
        let map = MasteryMap.build(database: database, store: store)
        for group in map.tiers where !group.skills.isEmpty {
            let expected = group.skills.reduce(0.0) { $0 + $1.score }
                / Double(group.skills.count) / 100
            #expect(abs(group.fill - expected) < 1e-9)
            #expect(group.fill >= 0 && group.fill <= 1)
        }
    }

    // MARK: - Practise next

    @Test("RUSTY commands are surfaced FIRST in the practise-next affordance")
    func rustyFirst() throws {
        let map = try map()
        let order = map.practiceNext.map(\.commandID)

        #expect(order.first == "action.delete-line", "the rusty skill must lead")
        #expect(order.count == arcadeUnlocked.count)
        // Rusty → learning → unlearned → mastered, and mastered brings up the rear.
        #expect(order.firstIndex(of: "action.delete-line")!
            < order.firstIndex(of: "grammar.delete-inner-word")!)
        #expect(order.firstIndex(of: "grammar.delete-inner-word")!
            < order.firstIndex(of: "motion.line-end")!)
        #expect(order.last == "motion.word-forward", "what you already own sorts last")
    }

    @Test("within a band, the weakest score comes first, and ties are stable")
    func practiceNextOrderingIsStable() throws {
        let clock = TestClock(now: day(0))
        let store = ProgressStore(
            directory: temporaryDirectory(), alternateDirectories: [],
            now: { clock.now }, calendar: testCalendar
        )
        for id in arcadeUnlocked { store.markLessonCompleted(commandID: id) }
        // Two learning skills at clearly different scores.
        practiceCorrect(store, "motion.word-forward", times: 2)
        store.recordRep(commandID: "action.delete-char", outcome: .incorrect)

        let map = MasteryMap.build(database: try CommandDatabase.load(), store: store)
        let learning = map.practiceNext.filter { $0.state == .learning }.map(\.commandID)
        #expect(learning == ["action.delete-char", "motion.word-forward"])

        // Rebuilding gives the identical order (no set-iteration nondeterminism).
        let database = try CommandDatabase.load()
        for _ in 0..<5 {
            let rebuilt = MasteryMap.build(database: database, store: store)
            #expect(rebuilt.practiceNext.map(\.commandID) == map.practiceNext.map(\.commandID))
            #expect(rebuilt == map)
        }
    }

    @Test("no rusty skills is a GOOD state, reported as such rather than as a nag")
    func noRustySkills() throws {
        let clock = TestClock(now: day(0))
        let store = ProgressStore(
            directory: temporaryDirectory(), alternateDirectories: [],
            now: { clock.now }, calendar: testCalendar
        )
        for id in arcadeUnlocked { store.markLessonCompleted(commandID: id) }
        for id in arcadeUnlocked { practiceCorrect(store, id, times: 8) }

        let map = MasteryMap.build(database: try CommandDatabase.load(), store: store)
        #expect(map.rustySkills.isEmpty)
        #expect(map.count(of: .mastered) == arcadeUnlocked.count)
        #expect(map.practiceNext.count == arcadeUnlocked.count, "the list is still complete")
    }

    // MARK: - Honest streak + trend + XP

    @Test("the map carries the honest trend, streak and XP from the store")
    func trendStreakAndXP() throws {
        let clock = TestClock(now: day(0))
        let store = ProgressStore(
            directory: temporaryDirectory(), alternateDirectories: [],
            now: { clock.now }, calendar: testCalendar
        )
        store.markLessonCompleted(commandID: "motion.word-forward")
        // Practise 4 days in a row, then take one off, then practise again.
        for _ in 0..<4 {
            store.recordRep(commandID: "motion.word-forward", outcome: .correct)
            clock.advance(days: 1)
        }
        clock.advance(days: 1)
        store.recordRep(commandID: "motion.word-forward", outcome: .correct)

        let database = try CommandDatabase.load()
        let map = MasteryMap.build(database: database, store: store, trendWindowDays: 40)
        #expect(map.trend.windowDays == 40)
        #expect(map.trend.practicedDays == 5, "5 of the last 40 days — a trend, not a verdict")
        #expect(map.currentStreak == store.currentStreak)
        #expect(map.graceDaysAvailable == store.graceDaysAvailable)
        #expect(map.totalXP == store.totalXP)

        store.awardXP(for: .fullGrammar)
        let after = MasteryMap.build(database: database, store: store)
        #expect(after.totalXP == map.totalXP + CommandComplexity.fullGrammar.xpAward)
    }

    @Test("building a map never writes to the store")
    func buildingIsReadOnly() throws {
        let (store, _) = seededStore()
        let before = store.state
        let bytesBefore = try Data(contentsOf: store.fileURL)
        let database = try CommandDatabase.load()
        for _ in 0..<5 {
            _ = MasteryMap.build(database: database, store: store)
        }
        let bytesAfter = try Data(contentsOf: store.fileURL)
        #expect(store.state == before)
        #expect(bytesAfter == bytesBefore)
    }

    @Test("an empty store yields an empty-but-complete map, not a crash")
    func emptyStore() throws {
        let store = ProgressStore(
            directory: temporaryDirectory(), alternateDirectories: [],
            now: { day(0) }, calendar: testCalendar
        )
        let database = try CommandDatabase.load()
        let map = MasteryMap.build(database: database, store: store)

        #expect(map.allSkills.isEmpty)
        #expect(map.practiceNext.isEmpty)
        #expect(map.rustySkills.isEmpty)
        #expect(map.lockedCount == database.commands.count)
        #expect(map.totalXP == 0)
        #expect(map.currentStreak == 0)
        let untouchedTiers = map.tiers.filter(\.isUntouched).count
        #expect(untouchedTiers == map.tiers.count)
    }
}
