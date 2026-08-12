import Foundation
import Testing
@testable import Vimkin

// The progression machinery, exercised with a synthetic lesson so the tests
// pin behaviour rather than authored content.

// MARK: - Fixtures

private func step(
    id: String = "step",
    target: String = "operator.delete",
    reps: Int? = nil,
    hint: String = "try `dw`"
) -> LessonStep {
    LessonStep(
        id: id,
        instruction: "Delete the word `draft`",
        targetCommandID: target,
        canonicalKeys: "dw",
        document: nil,
        setupKeys: nil,
        success: SuccessCriteria(verb: "delete", bufferOmits: ["draft"]),
        hint: hint,
        requiredReps: reps
    )
}

private func lesson(steps: [LessonStep], teaches: [String] = ["operator.delete"]) -> Lesson {
    Lesson(
        id: "fixture",
        tier: 3,
        order: 1,
        title: "Fixture",
        concept: "`d` is a verb.",
        document: "This draft sentence.",
        teaches: teaches,
        steps: steps
    )
}

private let deleteEvent = CommandEvent(
    verb: .delete, target: .motion(.wordForward), count: 1, category: .operatorMotion
)
private let moveEvent = CommandEvent(
    verb: .move, target: .motion(.wordForward), count: 1, category: .singleMotion
)

private func state(_ text: String, midCommand: Bool = false) -> LessonEngineState {
    LessonEngineState(
        text: text,
        cursor: Position(line: 0, col: 0),
        mode: .normal,
        isMidCommand: midCommand
    )
}

private let dirty = state("This draft sentence.")
private let clean = state("This sentence.")

/// One correct attempt (`dw`): the `d` is pending, the `w` completes it.
@discardableResult
private func correctAttempt(_ runner: LessonRunner) -> LessonOutcome {
    runner.record(events: [], before: dirty, after: state("This draft sentence.", midCommand: true))
    return runner.record(events: [deleteEvent], before: dirty, after: clean)
}

/// One wrong attempt: a bare `w` motion, which emits an event but not the target one.
@discardableResult
private func wrongAttempt(_ runner: LessonRunner) -> LessonOutcome {
    runner.record(events: [moveEvent], before: dirty, after: dirty)
}

private func makeStore() -> ProgressStore {
    ProgressStore(directory: temporaryDirectory(), alternateDirectories: [])
}

// MARK: - Tests

@Suite("Lesson runner: rep counting", .tags(.unit))
struct LessonRunnerRepTests {

    @Test("a correct attempt advances the rep counter")
    func correctAdvancesReps() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3)]))
        #expect(runner.correctReps == 0)

        #expect(correctAttempt(runner) == .correct(repsCompleted: 1, repsRequired: 3))
        #expect(runner.correctReps == 1)
        #expect(correctAttempt(runner) == .correct(repsCompleted: 2, repsRequired: 3))
        #expect(runner.correctReps == 2)
    }

    @Test("a wrong key shows the hint and never moves the rep counter backwards")
    func wrongKeyHintsWithoutRegressing() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3, hint: "try `dw`")]))
        correctAttempt(runner)
        #expect(runner.correctReps == 1)

        #expect(wrongAttempt(runner) == .incorrect(hint: "try `dw`"))
        #expect(runner.correctReps == 1, "a miss must not undo banked reps")
        #expect(runner.stepIndex == 0, "a miss must not advance the step")
    }

    @Test("wrong attempts on a fresh step never push the counter below zero")
    func wrongKeyCannotGoNegative() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3)]))
        for _ in 0 ..< 5 { wrongAttempt(runner) }
        #expect(runner.correctReps == 0)
        #expect(runner.incorrectReps == 5)
        #expect(runner.stepIndex == 0)
        #expect(!runner.isComplete)
    }

    @Test("keys mid-command are pending: not a rep, not a miss")
    func midCommandKeysArePending() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3)]))
        // `d` typed: operator pending, no events.
        let outcome = runner.record(
            events: [], before: dirty, after: state("This draft sentence.", midCommand: true)
        )
        #expect(outcome == .pending)
        #expect(runner.attempts == 0)
    }

    @Test("a stray key that changes nothing is ignored, not punished")
    func strayKeyIgnored() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3)]))
        let outcome = runner.record(events: [], before: dirty, after: dirty)
        #expect(outcome == .pending)
        #expect(runner.attempts == 0)
    }

    @Test("a command that fizzles to nothing counts as a miss")
    func fizzledCommandIsAMiss() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3, hint: "try `dw`")]))
        // `f` then a character with no match: was mid-command, now idle, no events.
        let outcome = runner.record(
            events: [],
            before: state("This draft sentence.", midCommand: true),
            after: dirty
        )
        #expect(outcome == .incorrect(hint: "try `dw`"))
        #expect(runner.incorrectReps == 1)
    }
}

@Suite("Lesson runner: accuracy gate", .tags(.integration))
struct LessonRunnerAccuracyTests {

    @Test("3 clean correct reps complete the step")
    func cleanRunCompletes() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3), step(id: "second")]))
        correctAttempt(runner)
        correctAttempt(runner)
        #expect(correctAttempt(runner) == .stepComplete(nextStepIndex: 1))
        #expect(runner.stepIndex == 1)
        #expect(runner.correctReps == 0, "counters reset for the new step")
    }

    @Test("3 correct + 5 wrong is below the accuracy threshold and does NOT complete")
    func accuracyGateBlocksAdvancement() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3), step(id: "second")]))
        for _ in 0 ..< 5 { wrongAttempt(runner) }
        correctAttempt(runner)
        correctAttempt(runner)
        let third = correctAttempt(runner)

        #expect(runner.correctReps == 3, "the reps are banked")
        #expect(third == .correct(repsCompleted: 3, repsRequired: 3), "but the step is not cleared")
        #expect(runner.stepIndex == 0)
        #expect(runner.accuracy < runner.accuracyThreshold)
        #expect(!runner.isComplete)
    }

    @Test("the gate is recoverable: more correct reps lift accuracy over the line")
    func accuracyGateIsRecoverable() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 3), step(id: "second")]))
        for _ in 0 ..< 5 { wrongAttempt(runner) }
        var outcome: LessonOutcome = .pending
        for _ in 0 ..< 12 {
            outcome = correctAttempt(runner)
            if case .stepComplete = outcome { break }
        }
        #expect(outcome == .stepComplete(nextStepIndex: 1), "practice must be able to clear the gate")
    }

    @Test("accuracy starts perfect so a clean learner is never gated")
    func accuracyStartsPerfect() {
        let runner = LessonRunner(lesson: lesson(steps: [step()]))
        #expect(runner.accuracy == 1)
        #expect(runner.attempts == 0)
    }

    @Test("no timer input exists: correct reps are recorded as .correct, never .slowCorrect")
    func repsAreNeverSpeedGraded() {
        let store = makeStore()
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 1)]), store: store)
        correctAttempt(runner)
        // A single .correct rep leaves a mastery record with exactly one rep and
        // a score consistent with the correct (not slow-correct) outcome.
        let record = store.state.mastery["operator.delete"]
        #expect(record?.repCount == 1)
        #expect(record?.score == MasteryModel.updatedScore(from: 0, outcome: .correct))
    }
}

@Suite("Lesson runner: progress store writes", .tags(.integration))
struct LessonRunnerProgressTests {

    @Test("completing a lesson unlocks exactly the commands it teaches")
    func lessonCompletionUnlocksTaughtCommands() {
        let store = makeStore()
        let taught = ["operator.delete", "action.delete-line"]
        let runner = LessonRunner(
            lesson: lesson(steps: [step(reps: 2)], teaches: taught),
            store: store
        )
        #expect(store.unlockedCommands.isEmpty)

        correctAttempt(runner)
        #expect(store.unlockedCommands.isEmpty, "nothing unlocks mid-lesson")
        #expect(correctAttempt(runner) == .lessonComplete)

        #expect(store.unlockedCommands == Set(taught))
        #expect(store.isUnlocked(commandID: "operator.delete"))
        #expect(!store.isUnlocked(commandID: "operator.change"))
        #expect(runner.isComplete)
    }

    @Test("a lesson gated by accuracy unlocks nothing")
    func blockedLessonUnlocksNothing() {
        let store = makeStore()
        let runner = LessonRunner(
            lesson: lesson(steps: [step(reps: 3)], teaches: ["operator.delete"]),
            store: store
        )
        for _ in 0 ..< 5 { wrongAttempt(runner) }
        for _ in 0 ..< 3 { correctAttempt(runner) }
        #expect(store.unlockedCommands.isEmpty, "the accuracy gate must hold the unlock back")
    }

    @Test("every judged attempt is recorded as a rep against the target command")
    func attemptsRecordReps() {
        let store = makeStore()
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 5)]), store: store)
        correctAttempt(runner)
        wrongAttempt(runner)
        wrongAttempt(runner)
        #expect(store.state.mastery["operator.delete"]?.repCount == 3)
    }

    @Test("recording after completion is inert")
    func recordingAfterCompletionIsInert() {
        let store = makeStore()
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 1)]), store: store)
        #expect(correctAttempt(runner) == .lessonComplete)
        #expect(correctAttempt(runner) == .pending)
        #expect(store.state.mastery["operator.delete"]?.repCount == 1)
    }

    @Test("the runner works with no store at all")
    func storeIsOptional() {
        let runner = LessonRunner(lesson: lesson(steps: [step(reps: 1)]))
        #expect(correctAttempt(runner) == .lessonComplete)
    }
}

@Suite("Lesson runner: attempt setup", .tags(.unit))
struct LessonRunnerSetupTests {

    @Test("makeEngine opens the step document and applies the setup keys")
    func makeEngineAppliesSetup() {
        let drill = LessonStep(
            id: "s", instruction: "i", targetCommandID: "motion.down", canonicalKeys: "j",
            document: "alpha\nbeta\ngamma", setupKeys: "jj",
            success: SuccessCriteria(), hint: "h", requiredReps: nil
        )
        let runner = LessonRunner(lesson: lesson(steps: [drill]))
        let engine = runner.makeEngine()
        #expect(engine.buffer.text == "alpha\nbeta\ngamma")
        #expect(engine.cursor == Position(line: 2, col: 0))
    }

    @Test("keyInputs maps escape and return")
    func keyInputMapping() {
        #expect(LessonRunner.keyInputs("d\u{1B}\n") == [.char("d"), .escape, .enter])
    }
}
