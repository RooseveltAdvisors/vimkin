// LessonRunner.swift — the tutorial's pure, testable progression engine (plan U5).
//
// Feeds are judged one at a time: the host hands the runner every
// (events, before, after) triple produced by a keystroke, and the runner decides
// whether the learner is still typing, got it right, or missed.
//
// Two pedagogy rules are enforced structurally here (plan KTD 4 + 5):
//
//   ACCURACY FIRST — a step clears only when the learner has N correct reps AND
//   the step's accuracy is at or above the threshold. Wrong reps never subtract
//   from the rep counter (nothing ever goes backwards); they lower accuracy,
//   which is recovered by practising more, not by being punished.
//
//   NO TIMERS — nothing in this file measures elapsed time. Speed is not
//   scored anywhere in the tutorial, so every correct rep is recorded as
//   `.correct`, never `.slowCorrect`.
//
// No SwiftUI, no Foundation-heavy machinery: a host (the SwiftUI LessonView, or
// a test) owns the engine and just relays keystroke results.

/// What one judged keystroke did to the lesson.
public enum LessonOutcome: Equatable, Sendable {
    /// Nothing to judge yet — the command is still being typed (or the key had
    /// no effect at all). Never counted as a rep.
    case pending
    /// A correct rep that did not yet clear the step.
    case correct(repsCompleted: Int, repsRequired: Int)
    /// A wrong (or fizzled) attempt. The hint is shown gently, inline.
    case incorrect(hint: String)
    /// The step is cleared; `nextStepIndex` is now current.
    case stepComplete(nextStepIndex: Int)
    /// The final step cleared — the lesson's commands are now unlocked.
    case lessonComplete
}

public final class LessonRunner {
    /// Correct reps a step needs when it does not specify its own.
    public static let defaultRequiredReps = 3
    /// Minimum step accuracy (correct / attempts) required to advance.
    public static let defaultAccuracyThreshold = 0.6

    public let lesson: Lesson
    public let accuracyThreshold: Double

    /// Index of the step being drilled (== `lesson.steps.count` once complete).
    public private(set) var stepIndex: Int = 0
    /// Correct reps banked for the current step.
    public private(set) var correctReps: Int = 0
    /// Wrong attempts on the current step.
    public private(set) var incorrectReps: Int = 0
    /// True once the last step cleared and the unlocks were written.
    public private(set) var isComplete: Bool = false

    private let store: ProgressStore?

    /// - Parameters:
    ///   - lesson: the lesson to run.
    ///   - store: progress store to write reps and (on completion) unlocks to.
    ///     Optional so the runner can be exercised with no persistence at all.
    ///   - accuracyThreshold: step accuracy gate, 0...1.
    public init(
        lesson: Lesson,
        store: ProgressStore? = nil,
        accuracyThreshold: Double = LessonRunner.defaultAccuracyThreshold
    ) {
        self.lesson = lesson
        self.store = store
        self.accuracyThreshold = accuracyThreshold
    }

    // MARK: - Current state (read by the UI)

    public var currentStep: LessonStep? {
        stepIndex < lesson.steps.count ? lesson.steps[stepIndex] : nil
    }

    /// 1-based step number for display ("step 2 of 4").
    public var stepNumber: Int { min(stepIndex + 1, lesson.steps.count) }
    public var stepCount: Int { lesson.steps.count }

    /// Reps required by the current step (0 once the lesson is complete).
    public var repsRequired: Int { currentStep?.reps ?? 0 }

    /// Attempts judged on the current step.
    public var attempts: Int { correctReps + incorrectReps }

    /// Step accuracy so far. A step with no attempts yet counts as perfect, so
    /// the gate never blocks a learner who has not missed anything.
    public var accuracy: Double {
        attempts == 0 ? 1 : Double(correctReps) / Double(attempts)
    }

    /// The practice document for the current step.
    public var currentDocument: String {
        currentStep?.documentText(in: lesson) ?? lesson.document
    }

    /// Keys fed to position the learner before an attempt (never judged).
    public var currentSetupKeys: String { currentStep?.setupKeys ?? "" }

    /// A fresh engine for the next attempt: the step's document, with the
    /// step's setup keys already applied. Every attempt starts here — a wrong
    /// (or right) attempt may have mutated the document, so it is always reset.
    public func makeEngine() -> VimEngine {
        var engine = VimEngine(text: currentDocument)
        engine.feed(keys: currentSetupKeys)
        return engine
    }

    // MARK: - Judging

    /// Judge one keystroke's result.
    ///
    /// - Parameters:
    ///   - events: `CommandEvent`s the keystroke emitted (empty is meaningful —
    ///     a no-op command and a half-typed one both emit nothing).
    ///   - before: engine state before the keystroke.
    ///   - after: engine state after it.
    @discardableResult
    public func record(
        events: [CommandEvent],
        before: LessonEngineState,
        after: LessonEngineState
    ) -> LessonOutcome {
        guard !isComplete, let step = currentStep else { return .pending }

        if events.isEmpty {
            // Still typing (operator pending, awaiting a find char, count in
            // progress, `:` prompt open) — say nothing.
            if after.isMidCommand { return .pending }
            // A command WAS in flight and produced nothing: it fizzled
            // (`fz` with no z, `d` then an invalid motion). That is a miss.
            if before.isMidCommand { return miss(step) }
            // A stray key that did nothing at all: ignore it rather than
            // punish it (accuracy-first, never punitive).
            return .pending
        }

        return step.success.matches(events: events, before: before, after: after)
            ? hit(step)
            : miss(step)
    }

    private func hit(_ step: LessonStep) -> LessonOutcome {
        correctReps += 1
        store?.recordRep(commandID: step.targetCommandID, outcome: .correct)
        guard correctReps >= step.reps, accuracy >= accuracyThreshold else {
            return .correct(repsCompleted: correctReps, repsRequired: step.reps)
        }
        return advance()
    }

    private func miss(_ step: LessonStep) -> LessonOutcome {
        incorrectReps += 1
        store?.recordRep(commandID: step.targetCommandID, outcome: .incorrect)
        return .incorrect(hint: step.hint)
    }

    private func advance() -> LessonOutcome {
        stepIndex += 1
        correctReps = 0
        incorrectReps = 0
        guard stepIndex >= lesson.steps.count else {
            return .stepComplete(nextStepIndex: stepIndex)
        }
        isComplete = true
        for commandID in lesson.teaches {
            store?.markLessonCompleted(commandID: commandID)
        }
        return .lessonComplete
    }

    // MARK: - Key helpers

    /// Split an authored key string into engine inputs.
    /// `"\u{1B}"` is Esc and `"\n"`/`"\r"` are Enter, matching `VimEngine.feed(keys:)`.
    public static func keyInputs(_ keys: String) -> [KeyInput] {
        keys.map { c in
            switch c {
            case "\u{1B}": return .escape
            case "\n", "\r": return .enter
            default: return .char(c)
            }
        }
    }
}
