import Foundation
import Testing
@testable import Vimkin

// Pure mastery math + store-level decay behavior with an injected clock.

@Suite("Mastery model", .tags(.integration))
struct MasteryModelTests {
    /// Fixed reference date: 2026-01-01 00:00 in the test calendar.
    static func makeStore(startingAt start: Date = day(0), clock: TestClock? = nil) -> (ProgressStore, TestClock) {
        let clock = clock ?? TestClock(now: start)
        let dir = temporaryDirectory()
        let store = ProgressStore(
            directory: dir,
            alternateDirectories: [],
            now: { clock.now },
            calendar: testCalendar
        )
        return (store, clock)
    }

    @Test("repeated correct reps drive a skill to mastered")
    func practiceToMastered() {
        let (store, _) = Self.makeStore()
        let id = "motion.word-forward"
        #expect(store.masteryState(commandID: id) == .unlearned)

        for _ in 0..<8 { store.recordRep(commandID: id, outcome: .correct) }

        #expect(store.masteryScore(commandID: id) >= MasteryModel.masteredThreshold)
        #expect(store.masteryState(commandID: id) == .mastered)
    }

    @Test("decay drops a mastered skill toward rusty but never below the learned floor")
    func decayNeverBelowLearnedFloor() {
        let (store, clock) = Self.makeStore()
        let id = "operator.delete"
        for _ in 0..<10 { store.recordRep(commandID: id, outcome: .correct) }
        let masteredScore = store.masteryScore(commandID: id)
        #expect(masteredScore >= MasteryModel.masteredThreshold)

        // Unused for 30 days → decays below mastered, becomes rusty.
        clock.advance(days: 30)
        let after30 = store.masteryScore(commandID: id)
        #expect(after30 < masteredScore)
        #expect(after30 >= MasteryModel.learnedFloor)
        #expect(store.masteryState(commandID: id) == .rusty)

        // Even after a year, never below the learned floor.
        clock.advance(days: 365)
        #expect(store.masteryScore(commandID: id) == MasteryModel.learnedFloor)
        #expect(store.masteryState(commandID: id) == .rusty)
    }

    @Test("short breaks do not decay at all")
    func decayFreeDays() {
        let (store, clock) = Self.makeStore()
        let id = "motion.left"
        for _ in 0..<6 { store.recordRep(commandID: id, outcome: .correct) }
        let score = store.masteryScore(commandID: id)

        clock.advance(days: MasteryModel.decayFreeDays)
        #expect(store.masteryScore(commandID: id) == score)
    }

    @Test("a never-mastered skill decays without the learned floor and stays 'learning'")
    func learningSkillDecay() {
        let (store, clock) = Self.makeStore()
        let id = "motion.down"
        store.recordRep(commandID: id, outcome: .slowCorrect)
        #expect(store.masteryState(commandID: id) == .learning)

        clock.advance(days: 60)
        #expect(store.masteryScore(commandID: id) == 0)
        // Practiced before, never mastered → learning (not unlearned, not rusty).
        #expect(store.masteryState(commandID: id) == .learning)
    }

    @Test("wrong reps lower the rolling score more than slow-correct reps")
    func accuracyWeighting() {
        let (storeA, _) = Self.makeStore()
        let (storeB, _) = Self.makeStore()
        let id = "motion.up"
        for _ in 0..<10 {
            storeA.recordRep(commandID: id, outcome: .correct)
            storeB.recordRep(commandID: id, outcome: .correct)
        }
        let before = storeA.masteryScore(commandID: id)
        #expect(before == storeB.masteryScore(commandID: id))

        storeA.recordRep(commandID: id, outcome: .slowCorrect)
        storeB.recordRep(commandID: id, outcome: .incorrect)

        let slowDrop = before - storeA.masteryScore(commandID: id)
        let wrongDrop = before - storeB.masteryScore(commandID: id)
        #expect(wrongDrop > slowDrop)
        #expect(slowDrop >= 0)
    }
}
