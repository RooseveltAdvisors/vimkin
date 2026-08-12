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
//
// U19 adds the *visible* half of that judgement, without changing any of the
// judging: every key is mirrored into a `KeyFeedbackHub` (the key-cap and the
// growing chord row), a correct rep raises a graded reward, and the session
// that was just judged is kept alive in `finishedSession` so the surface can
// hold the OUTCOME on screen for a beat before the page resets under it.

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
    /// Ghost-cursor outcome preview, when the lesson opted into one.
    let preview: OutcomePreviewSpec?
    /// Key-cap + chord-row state for the practice surface.
    let keys = KeyFeedbackHub()

    private(set) var phase: Phase = .concept
    private(set) var session: EditorSession
    private(set) var feedback: Feedback?
    /// Bumped on every reset so the editor rebuilds (and refocuses).
    private(set) var attemptID: Int = 0
    /// The session from the attempt just judged. The surface keeps showing it
    /// for a beat so the learner SEES what their key did before the page resets.
    private(set) var finishedSession: EditorSession?
    /// Raw keys typed in the current attempt — what the correction names back.
    private(set) var attemptKeys: String = ""
    /// Set by the learner when they ask to see the keys — never shown by default.
    var keysRevealed = false

    /// Graded celebration for a correct rep / cleared step / finished lesson.
    /// The surface routes this into its `JuiceConductor`.
    @ObservationIgnored var onReward: ((JuiceEvent) -> Void)?

    @ObservationIgnored private let runner: LessonRunner

    init(lesson: Lesson, store: ProgressStore?, preview: OutcomePreviewSpec? = nil) {
        self.lesson = lesson
        self.preview = preview
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

    /// True when the step the learner is on asks for `Esc` itself.
    ///
    /// This exists because `Esc` is the one key that is ALSO chrome: the
    /// keyboard shell's leave-chord is `Esc Esc`. A step that drills `Esc`
    /// therefore scores the first press and is thrown out of the lesson by the
    /// second — and Lesson 1's second step asks for three. `LessonView` reads
    /// this to route `Esc` to the judge instead of the chord on those steps.
    var stepDrillsEscape: Bool {
        guard phase == .practice, let step else { return false }
        return step.canonicalKeys == "\u{1b}"
    }

    /// The ghosts to draw right now: only before the learner has committed to a
    /// key this attempt, and only if the lesson opted in.
    var ghosts: [OutcomeGhost] {
        guard phase == .practice, attemptKeys.isEmpty else { return [] }
        return OutcomePreview.ghosts(for: preview, engine: session.engine)
    }

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

        attemptKeys += Self.rawKey(key)
        keys.observe(key, state: after)

        switch runner.record(events: events, before: before, after: after) {
        case .pending:
            break
        case .correct(let done, let required):
            feedback = .correct(done >= required ? "that's it" : "nice — \(required - done) to go")
            reward(PracticeReward.correct(events: events))
            resetAttempt()
        case .stepComplete:
            feedback = .correct("step cleared")
            keysRevealed = false
            reward(PracticeReward.stepCleared)
            resetAttempt()
        case .incorrect(let hint):
            feedback = .hint(correction(fallback: hint))
            keys.grade(.wrong)
            resetAttempt()
        case .lessonComplete:
            feedback = nil
            phase = .complete
            keys.grade(.right)
        }
        // Always `.block`: the key was already delivered above.
        return .block(reason: "handled by the lesson")
    }

    /// Names the DIFFERENCE when the learner picked a neighbouring door
    /// ("you pressed `a` — that types AFTER the cursor; try `i`"), and falls
    /// back to the step's own authored hint otherwise.
    private func correction(fallback: String) -> String {
        guard let expected = step?.canonicalKeys else { return fallback }
        return OutcomePreview.correction(pressed: attemptKeys, expected: expected, spec: preview)
            ?? fallback
    }

    private func reward(_ juice: JuiceEvent) {
        keys.grade(.right)
        keys.celebrate(juice.tier)
        onReward?(juice)
    }

    /// Fresh document + setup keys for the next attempt. Every attempt starts
    /// from a clean page — a right OR wrong attempt may have edited it.
    private func resetAttempt() {
        finishedSession = session
        session = makeSession()
        attemptKeys = ""
        attemptID += 1
    }

    private func makeSession() -> EditorSession {
        let session = EditorSession(text: runner.currentDocument)
        session.feed(keys: runner.currentSetupKeys)
        return session
    }

    /// The raw key string, in the same encoding `canonicalKeys` uses.
    private static func rawKey(_ key: KeyInput) -> String {
        switch key {
        case .char(let c): return String(c)
        case .escape: return "\u{1B}"
        case .enter: return "\n"
        }
    }
}
