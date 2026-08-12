// LessonCoordinator.swift — the glue between LessonRunner (pure) and the
// SwiftUI lesson surface: owns the editor session for the current attempt,
// judges every keystroke, and publishes the feedback the view renders.
//
// How keystrokes are intercepted: `EditorView` exposes a pluggable `KeyFilter`
// that runs BEFORE the key reaches the session. The coordinator uses that hook
// to drive the session itself — capturing engine state either side of the feed
// so the runner sees the full (events, before, after) triple, including the
// zero-event cases (still typing vs. a command that fizzled) — and then returns
// `.block` so the key is not delivered a second time. Nothing in EditorView,
// KeyCapture or the Engine is modified.

import Foundation
import Observation

@Observable
final class LessonCoordinator {
    enum Phase: Equatable {
        case concept
        case practice
        case complete
    }

    /// Inline, non-punitive feedback on the last judged attempt.
    enum Feedback: Equatable {
        case correct(String)
        case hint(String)
    }

    let lesson: Lesson

    private(set) var phase: Phase = .concept
    private(set) var session: EditorSession
    private(set) var feedback: Feedback?
    /// Bumped on every reset so the editor rebuilds (and refocuses).
    private(set) var attemptID: Int = 0
    /// Set by the learner when they ask to see the keys — never shown by default.
    var keysRevealed = false

    @ObservationIgnored private let runner: LessonRunner

    init(lesson: Lesson, store: ProgressStore?) {
        self.lesson = lesson
        self.runner = LessonRunner(lesson: lesson, store: store)
        self.session = EditorSession(text: "")
        self.session = makeSession()
    }

    // MARK: - Read-through state for the view

    var step: LessonStep? { runner.currentStep }
    var stepNumber: Int { runner.stepNumber }
    var stepCount: Int { runner.stepCount }
    var repsCompleted: Int { runner.correctReps }
    var repsRequired: Int { runner.repsRequired }
    var isComplete: Bool { runner.isComplete }

    // MARK: - Flow

    func begin() {
        phase = .practice
    }

    /// Key hook handed to `EditorView(filter:)`. See the file comment.
    func handle(key: KeyInput) -> KeyDecision {
        guard phase == .practice, !runner.isComplete else { return .block(reason: "lesson finished") }

        let before = LessonEngineState(engine: session.engine)
        let events = session.feed(key)
        let after = LessonEngineState(engine: session.engine)

        switch runner.record(events: events, before: before, after: after) {
        case .pending:
            break
        case .correct(let done, let required):
            feedback = .correct(done >= required ? "that's it" : "nice — \(required - done) to go")
            resetAttempt()
        case .stepComplete:
            feedback = .correct("step cleared")
            keysRevealed = false
            resetAttempt()
        case .incorrect(let hint):
            feedback = .hint(hint)
            resetAttempt()
        case .lessonComplete:
            feedback = nil
            phase = .complete
        }
        // Always `.block`: the key was already delivered above.
        return .block(reason: "handled by the lesson")
    }

    /// Fresh document + setup keys for the next attempt. Every attempt starts
    /// from a clean page — a right OR wrong attempt may have edited it.
    private func resetAttempt() {
        session = makeSession()
        attemptID += 1
    }

    private func makeSession() -> EditorSession {
        let session = EditorSession(text: runner.currentDocument)
        session.feed(keys: runner.currentSetupKeys)
        return session
    }
}
