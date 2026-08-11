import Foundation
import Testing
@testable import Vimkin

@Suite("Progress store: XP, unlocks, persistence")
struct ProgressStoreTests {
    func makeStore(directory: URL, alternates: [URL] = [], clock: TestClock) -> ProgressStore {
        ProgressStore(
            directory: directory,
            alternateDirectories: alternates,
            now: { clock.now },
            calendar: testCalendar
        )
    }

    // MARK: - XP

    @Test("XP awards are tiered by command complexity")
    func tieredXP() {
        let store = makeStore(directory: temporaryDirectory(), clock: TestClock(now: day(0)))
        let single = store.awardXP(for: .singleMotion)
        let opMotion = store.awardXP(for: .operatorMotion)
        let grammar = store.awardXP(for: .fullGrammar)

        #expect(single < opMotion)
        #expect(opMotion < grammar)
        #expect(store.totalXP == single + opMotion + grammar)
    }

    // MARK: - XP-never-gates invariant

    @Test("unlock API takes no XP input (compile-level signature pin)")
    func unlockSignatureHasNoXP() {
        // Compiles only while the unlock computation is a pure function of
        // completed lessons — adding an XP parameter breaks this line.
        let unlock: (Set<String>) -> Set<String> = UnlockModel.unlockedCommands(completedLessons:)
        #expect(unlock(["motion.left"]) == ["motion.left"])
    }

    @Test("XP=0 and XP=1e6 produce identical unlocks")
    func xpNeverGatesBehaviorally() {
        let clock = TestClock(now: day(0))
        let poor = makeStore(directory: temporaryDirectory(), clock: clock)
        let rich = makeStore(directory: temporaryDirectory(), clock: clock)

        for store in [poor, rich] {
            store.markLessonCompleted(commandID: "motion.word-forward")
            store.markLessonCompleted(commandID: "operator.delete")
        }
        for _ in 0..<20_000 { rich.awardXP(for: .fullGrammar) }
        #expect(rich.totalXP >= 1_000_000)

        #expect(poor.unlockedCommands == rich.unlockedCommands)
        #expect(rich.isUnlocked(commandID: "operator.delete"))
        #expect(!rich.isUnlocked(commandID: "text-object.inner-word"))
    }

    // MARK: - Persistence

    @Test("round-trip: save, then a new instance loads identical state")
    func roundTrip() throws {
        let dir = temporaryDirectory()
        let clock = TestClock(now: day(0))
        let store = makeStore(directory: dir, clock: clock)

        store.recordRep(commandID: "motion.word-forward", outcome: .correct)
        store.recordRep(commandID: "motion.word-forward", outcome: .incorrect)
        store.recordRep(commandID: "operator.delete", outcome: .slowCorrect)
        store.markLessonCompleted(commandID: "motion.word-forward")
        store.awardXP(for: .operatorMotion)
        try store.save()

        let reloaded = makeStore(directory: dir, clock: clock)
        #expect(reloaded.state == store.state)
    }

    @Test("migration: a store existing only at the alternate location is adopted and written to canonical")
    func migration() throws {
        let locationA = temporaryDirectory() // legacy/other flavor
        let locationB = temporaryDirectory() // canonical for the new instance
        let clock = TestClock(now: day(0))

        let original = makeStore(directory: locationA, clock: clock)
        original.recordRep(commandID: "motion.line-start", outcome: .correct)
        original.markLessonCompleted(commandID: "motion.line-start")
        original.awardXP(for: .singleMotion)
        try original.save()

        let migrated = makeStore(directory: locationB, alternates: [locationA], clock: clock)
        #expect(migrated.state == original.state)

        // The canonical location now has the file...
        let canonicalFile = locationB.appendingPathComponent(ProgressStore.fileName)
        #expect(FileManager.default.fileExists(atPath: canonicalFile.path))
        // ...and a fresh instance NOT given the alternate still sees the data.
        let after = makeStore(directory: locationB, clock: clock)
        #expect(after.state == original.state)
    }

    @Test("canonical store wins over the alternate when both exist")
    func canonicalWins() throws {
        let locationA = temporaryDirectory()
        let locationB = temporaryDirectory()
        let clock = TestClock(now: day(0))

        let alternate = makeStore(directory: locationA, clock: clock)
        alternate.awardXP(for: .singleMotion)
        try alternate.save()

        let canonical = makeStore(directory: locationB, clock: clock)
        canonical.awardXP(for: .fullGrammar)
        canonical.awardXP(for: .fullGrammar)
        try canonical.save()
        let canonicalXP = canonical.totalXP

        let store = makeStore(directory: locationB, alternates: [locationA], clock: clock)
        #expect(store.totalXP == canonicalXP)
    }

    @Test("a corrupt store file yields a fresh state, never a crash")
    func corruptStore() throws {
        let dir = temporaryDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json{{".utf8).write(to: dir.appendingPathComponent(ProgressStore.fileName))

        let store = makeStore(directory: dir, clock: TestClock(now: day(0)))
        #expect(store.state == .empty)
    }

    @Test("default path resolution probes the sandbox/plain twin of the canonical location")
    func defaultDirectories() {
        let (canonical, alternates) = ProgressStore.defaultDirectories()
        #expect(canonical.lastPathComponent == "Vimkin")
        if canonical.path.contains("/Library/Containers/") {
            // Sandboxed flavor → must probe the plain real-home location.
            #expect(alternates.contains { !$0.path.contains("/Library/Containers/") })
        } else {
            // Unsandboxed flavor → probes the container twin when a bundle id exists.
            #expect(alternates.allSatisfy { $0.path.contains("/Library/Containers/") })
        }
        #expect(alternates.allSatisfy { $0.lastPathComponent == "Vimkin" })
    }

    // MARK: - 30-day simulation

    @Test("30-day simulation: varying accuracy produces sane, bounded trajectories")
    func thirtyDaySimulation() {
        let clock = TestClock(now: day(0))
        let store = makeStore(directory: temporaryDirectory(), clock: clock)
        let commands = ["motion.word-forward", "operator.delete", "text-object.inner-word"]
        var trajectories: [String: [Double]] = [:]

        for dayIndex in 0..<30 {
            for (index, id) in commands.enumerated() {
                // Deterministic varying accuracy: each command has its own
                // rhythm of correct / slow / wrong reps.
                for rep in 0..<5 {
                    let roll = (dayIndex &+ index &* 7 &+ rep &* 3) % 10
                    let outcome: RepOutcome = roll < 6 ? .correct : (roll < 8 ? .slowCorrect : .incorrect)
                    store.recordRep(commandID: id, outcome: outcome)
                }
                trajectories[id, default: []].append(store.masteryScore(commandID: id))
            }
            clock.advance(days: 1)
        }
        clock.advance(days: -1) // back to the last practiced day

        for (id, scores) in trajectories {
            #expect(scores.count == 30)
            for score in scores {
                #expect(score.isFinite, "non-finite score for \(id)")
                #expect(score >= 0 && score <= 100, "out-of-range score for \(id)")
            }
            // Mostly-correct daily practice trends upward overall and ends learned+.
            #expect(scores.last! > scores.first!)
            #expect(scores.last! >= MasteryModel.learnedFloor)
            #expect(store.masteryState(commandID: id) != .unlearned)
        }

        // Streak and trend stayed sane over 30 practiced days.
        #expect(store.currentStreak == 30)
        #expect(store.graceDaysAvailable == StreakModel.graceCap)
        #expect(store.practiceTrend(windowDays: 40).practicedDays == 30)
    }
}
