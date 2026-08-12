import Foundation
import Testing
@testable import Vimkin

@Suite("Dojo: session bookkeeping and summary math", .tags(.integration))
struct DrillSessionTests {

    /// A two-command session: one `dd` drill, then one `$` drill.
    private func twoDrillSession(
        store: ProgressStore,
        now: @escaping () -> Date = { day(0) }
    ) throws -> (session: DrillSession, deleteLine: Drill, lineEnd: Drill) {
        let content = try dojoContent()
        let generator = DrillGenerator(
            database: content.database, documents: content.documents, store: store
        )
        let deleteLine = try #require(
            generator.makeFocusedSession(commandID: "action.delete-line", length: 1, seed: 1).first
        )
        let lineEnd = try #require(
            generator.makeFocusedSession(commandID: "motion.line-end", length: 1, seed: 2).first
        )
        let session = DrillSession(drills: [deleteLine, lineEnd], store: store, now: now)
        return (session, deleteLine, lineEnd)
    }

    // MARK: - Summary math

    @Test("known correct/incorrect sequence produces the right accuracy, deltas and weakest skill")
    func summaryMath() throws {
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, deleteLine, lineEnd) = try twoDrillSession(store: store)

        // Drill 1: solved first try.
        #expect(submitAttempt(deleteLine.solutionKeys, on: deleteLine, in: session) == .correct)
        #expect(session.currentDrill?.id == lineEnd.id)

        // Drill 2: one wrong attempt, then solved.
        let wrong = try #require(submitAttempt("x", on: lineEnd, in: session))
        #expect(!wrong.isCorrect)
        #expect(session.currentDrill?.id == lineEnd.id, "a wrong attempt must not advance the drill")
        #expect(submitAttempt(lineEnd.solutionKeys, on: lineEnd, in: session) == .correct)
        #expect(session.isFinished)

        let summary = session.summary()
        #expect(summary.drillsPlanned == 2)
        #expect(summary.drillsCompleted == 2)
        #expect(summary.drillsSkipped == 0)
        #expect(summary.totalAttempts == 3)
        #expect(summary.correctAttempts == 2)
        #expect(summary.incorrectAttempts == 1)
        #expect(abs(summary.accuracy - 2.0 / 3.0) < 0.0001)
        #expect(summary.accuracyPercent == 67)

        #expect(summary.skills.count == 2)
        let dd = try #require(summary.skills.first { $0.commandID == "action.delete-line" })
        let end = try #require(summary.skills.first { $0.commandID == "motion.line-end" })

        #expect(dd.attempts == 1)
        #expect(dd.correct == 1)
        #expect(dd.incorrect == 0)
        #expect(dd.accuracy == 1)
        #expect(dd.masteryBefore == 0)
        #expect(abs(dd.masteryAfter - 30) < 0.0001)     // one correct rep: EWMA 0 → 30
        #expect(abs(dd.masteryDelta - 30) < 0.0001)

        #expect(end.attempts == 2)
        #expect(end.correct == 1)
        #expect(end.incorrect == 1)
        #expect(abs(end.accuracy - 0.5) < 0.0001)
        // incorrect from 0 leaves 0, then one correct lifts to 30.
        #expect(abs(end.masteryAfter - 30) < 0.0001)

        // Weakest = the one that actually went wrong.
        #expect(summary.weakestSkill?.commandID == "motion.line-end")
        #expect(summary.practiceNext.first?.commandID == "motion.line-end")
        #expect(summary.improved.map(\.commandID).sorted() == ["action.delete-line", "motion.line-end"])
    }

    @Test("a clean set names no weakest skill (nothing to scold)")
    func cleanSetHasNoWeakestSkill() throws {
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, deleteLine, lineEnd) = try twoDrillSession(store: store)
        submitAttempt(deleteLine.solutionKeys, on: deleteLine, in: session)
        submitAttempt(lineEnd.solutionKeys, on: lineEnd, in: session)

        let summary = session.summary()
        #expect(summary.accuracyPercent == 100)
        #expect(summary.weakestSkill == nil)
        #expect(summary.incorrectAttempts == 0)
    }

    @Test("an empty session summarizes to zeros instead of dividing by zero")
    func emptySession() {
        let store = makeDojoStore(unlocking: [])
        let session = DrillSession(drills: [], store: store, now: { day(0) })
        let summary = session.summary()
        #expect(session.isFinished)
        #expect(summary.accuracy == 0)
        #expect(summary.accuracyPercent == 0)
        #expect(summary.skills.isEmpty)
        #expect(summary.weakestSkill == nil)
    }

    // MARK: - Accuracy-first invariants (plan KTD 5)

    @Test("a slow correct answer is still CORRECT — recorded as slowCorrect, never failed")
    func slownessNeverFails() throws {
        let clock = TestClock(now: day(0))
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, deleteLine, _) = try twoDrillSession(store: store, now: { clock.now })

        clock.now = clock.now.addingTimeInterval(600)   // ten unhurried minutes
        let judgement = try #require(submitAttempt(deleteLine.solutionKeys, on: deleteLine, in: session))

        #expect(judgement == .correct, "slowness must never turn a right answer into a wrong one")
        #expect(session.attempts.first?.outcome == .slowCorrect)
        #expect(session.summary().unhurriedAttempts == 1)
        #expect(session.summary().incorrectAttempts == 0)
        // Mastery still moved UP: a slow correct rep builds skill.
        #expect(store.masteryScore(commandID: "action.delete-line") > 0)
    }

    @Test("a fast correct answer records .correct")
    func promptAnswerRecordsCorrect() throws {
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, deleteLine, _) = try twoDrillSession(store: store)
        submitAttempt(deleteLine.solutionKeys, on: deleteLine, in: session)
        #expect(session.attempts.first?.outcome == .correct)
        #expect(session.summary().unhurriedAttempts == 0)
    }

    // MARK: - Skipping

    @Test("skipping records NOTHING in the mastery store — a skip is not a wrong rep")
    func skippingIsNotAMistake() throws {
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, _, lineEnd) = try twoDrillSession(store: store)

        session.skipCurrentDrill()
        #expect(session.currentDrill?.id == lineEnd.id)
        #expect(session.attempts.isEmpty)
        #expect(store.masteryScore(commandID: "action.delete-line") == 0)
        #expect(store.masteryState(commandID: "action.delete-line") == .unlearned)

        let summary = session.summary()
        #expect(summary.drillsSkipped == 1)
        #expect(summary.drillsCompleted == 0)
    }

    // MARK: - Progress dots

    @Test("progress dots track clean / struggled / skipped / current / upcoming")
    func progressDots() throws {
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, deleteLine, lineEnd) = try twoDrillSession(store: store)

        #expect(session.dotStates == [.current, .upcoming])
        submitAttempt(deleteLine.solutionKeys, on: deleteLine, in: session)
        #expect(session.dotStates == [.clean, .current])

        submitAttempt("x", on: lineEnd, in: session)
        submitAttempt(lineEnd.solutionKeys, on: lineEnd, in: session)
        #expect(session.dotStates == [.clean, .struggled])
    }

    @Test("per-command accuracy inside the session is exact")
    func perCommandAccuracy() throws {
        let store = makeDojoStore(unlocking: ["action.delete-line", "motion.line-end"])
        let (session, deleteLine, lineEnd) = try twoDrillSession(store: store)
        submitAttempt(deleteLine.solutionKeys, on: deleteLine, in: session)
        submitAttempt("x", on: lineEnd, in: session)
        submitAttempt(lineEnd.solutionKeys, on: lineEnd, in: session)

        #expect(session.accuracy(forCommandID: "action.delete-line") == 1)
        #expect(session.accuracy(forCommandID: "motion.line-end") == 0.5)
        #expect(session.accuracy(forCommandID: "motion.word-forward") == 0)
    }
}
