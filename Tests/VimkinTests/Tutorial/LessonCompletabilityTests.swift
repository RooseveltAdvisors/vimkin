import Foundation
import Testing
@testable import Vimkin

// The load-bearing test for the AUTHORED content (plan U5 / reality-gate):
// every lesson is replayed end to end through a REAL VimEngine on its REAL
// practice document, driving the real LessonRunner. A lesson only passes if its
// canonical key sequences actually satisfy its own success criteria — so a
// mis-authored setup, a wrong cursor column, or an engine behaviour change
// fails here instead of in front of a learner.

/// Replays one attempt exactly as the app does: fresh document + setup keys,
/// then the step's canonical keys fed one at a time until the runner rules.
private func replayAttempt(_ runner: LessonRunner) -> LessonOutcome {
    guard let step = runner.currentStep else { return .pending }
    var engine = runner.makeEngine()
    var outcome: LessonOutcome = .pending
    for key in LessonRunner.keyInputs(step.canonicalKeys) {
        let before = LessonEngineState(engine: engine)
        let events = engine.feed(key)
        let after = LessonEngineState(engine: engine)
        outcome = runner.record(events: events, before: before, after: after)
        if outcome != .pending { break }
    }
    return outcome
}

private func makeStore() -> ProgressStore {
    ProgressStore(directory: temporaryDirectory(), alternateDirectories: [])
}

@Suite("Authored lessons are completable on a real engine")
struct LessonCompletabilityTests {

    @Test("every lesson reaches .lessonComplete by replaying its canonical keys")
    func everyLessonIsCompletable() throws {
        let db = try LessonDatabase.load()
        for lesson in db.lessons {
            let store = makeStore()
            let runner = LessonRunner(lesson: lesson, store: store)

            // Generous cap: every step needs at most `reps` attempts, so an
            // overrun means a step never resolves (an authoring bug).
            let cap = lesson.steps.reduce(0) { $0 + $1.reps } + 5
            var completed = false

            for _ in 0 ..< cap {
                let stepID = runner.currentStep?.id ?? "-"
                let outcome = replayAttempt(runner)
                switch outcome {
                case .correct, .stepComplete:
                    continue
                case .lessonComplete:
                    completed = true
                case .incorrect(let hint):
                    Issue.record(
                        """
                        \(lesson.id) / \(stepID): canonical keys did not satisfy the step.
                        hint shown: \(hint)
                        """
                    )
                case .pending:
                    Issue.record(
                        "\(lesson.id) / \(stepID): canonical keys produced no judged attempt"
                    )
                }
                if completed { break }
                if case .incorrect = outcome { break }
                if case .pending = outcome { break }
            }

            #expect(completed, "\(lesson.id) never completed")
            #expect(
                store.unlockedCommands == Set(lesson.teaches),
                "\(lesson.id) unlocked \(store.unlockedCommands.sorted()) instead of \(lesson.teaches.sorted())"
            )
        }
    }

    @Test("a completed run records only correct reps — no canonical key ever misses")
    func canonicalRunIsClean() throws {
        let db = try LessonDatabase.load()
        for lesson in db.lessons {
            let runner = LessonRunner(lesson: lesson)
            let cap = lesson.steps.reduce(0) { $0 + $1.reps } + 5
            for _ in 0 ..< cap {
                if runner.isComplete { break }
                _ = replayAttempt(runner)
            }
            #expect(runner.isComplete, "\(lesson.id) did not complete")
            #expect(runner.incorrectReps == 0, "\(lesson.id) logged a miss on canonical keys")
        }
    }

    @Test("each step's setup keys leave the engine idle, ready to judge")
    func setupKeysLeaveEngineIdle() throws {
        let db = try LessonDatabase.load()
        for lesson in db.lessons {
            for step in lesson.steps {
                var engine = VimEngine(text: step.documentText(in: lesson))
                engine.feed(keys: step.setupKeys ?? "")
                // Insert mode is a legitimate prepared state (the Esc drill);
                // a half-typed operator or find is not.
                #expect(
                    engine.mode != .operatorPending && engine.mode != .commandLine,
                    "\(step.id) setup keys leave the engine mid-command"
                )
            }
        }
    }

    @Test("a wrong-but-plausible key is rejected by the step it is wrong for")
    func plausibleWrongKeysAreRejected() throws {
        let db = try LessonDatabase.load()
        // `dw` is not `diw`: the classic near-miss the dojo cares about, and
        // proof the criteria are discriminating rather than rubber-stamping.
        let lesson = try #require(db.lesson(id: "t4-inner-word"))
        let runner = LessonRunner(lesson: lesson)
        let step = try #require(runner.currentStep)

        var engine = runner.makeEngine()
        var outcome: LessonOutcome = .pending
        for key in LessonRunner.keyInputs("dw") {
            let before = LessonEngineState(engine: engine)
            let events = engine.feed(key)
            let after = LessonEngineState(engine: engine)
            outcome = runner.record(events: events, before: before, after: after)
            if outcome != .pending { break }
        }
        #expect(outcome == .incorrect(hint: step.hint))
        #expect(runner.correctReps == 0)
    }

    @Test("every lesson's canonical keys are accepted by the engine's key surface")
    func canonicalKeysAreEngineInputs() throws {
        let db = try LessonDatabase.load()
        for lesson in db.lessons {
            for step in lesson.steps {
                let inputs = LessonRunner.keyInputs(step.canonicalKeys)
                #expect(!inputs.isEmpty, "\(step.id) has no canonical keys")
            }
        }
    }
}
