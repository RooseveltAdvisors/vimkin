// DojoModel.swift — the dojo's orchestrator: owns the generator, the running
// DrillSession, and the EditorSession the learner types into. Observation-only
// (no SwiftUI import), so it is fully testable headless.
//
// It also owns the "Practice this →" hand-off: the lookup overlay
// (UI/Overlay/OverlayController) posts `practiceCommandNotification` with a
// command id, and the dojo answers with a focused mini-session on that command.

import Foundation
import Observation

@MainActor
@Observable
public final class DojoModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case drilling
        case summary
    }

    // MARK: - Observable state

    public private(set) var phase: Phase = .idle
    public private(set) var session: DrillSession?
    /// The editor the current drill is played in. Replaced per drill (and after
    /// a wrong attempt, so the buffer is always pristine on a retry).
    public private(set) var editor: EditorSession?
    /// Bumped whenever `editor` is replaced, so SwiftUI can re-key the view.
    public private(set) var editorGeneration: Int = 0
    /// The verdict on the most recent attempt (nil before the first attempt on
    /// a drill).
    public private(set) var feedback: DrillJudgement?
    /// Set when the session came from "Practice this →".
    public private(set) var focusCommandID: String?
    public private(set) var summary: SessionSummary?

    public var currentDrill: Drill? { session?.currentDrill }

    // MARK: - Dependencies

    public let generator: DrillGenerator
    private let store: ProgressStore
    /// True when there is bundled content to drill on.
    public let isReady: Bool

    // Written once in init, read once in deinit; NotificationCenter tokens are
    // safe to remove from any thread. @ObservationIgnored keeps it a plain
    // stored property so the isolation annotation actually applies.
    @ObservationIgnored
    nonisolated(unsafe) private var practiceObserver: (any NSObjectProtocol)?

    public init(
        database: CommandDatabase,
        documents: [CorpusDocument],
        store: ProgressStore,
        observesPracticeRequests: Bool = true
    ) {
        self.store = store
        self.generator = DrillGenerator(database: database, documents: documents, store: store)
        self.isReady = !documents.isEmpty && !database.commands.isEmpty

        if observesPracticeRequests {
            practiceObserver = NotificationCenter.default.addObserver(
                forName: OverlayController.practiceCommandNotification,
                object: nil,
                queue: nil
            ) { [weak self] note in
                guard let id = note.object as? String else { return }
                // The overlay is @MainActor, so the common path is a synchronous
                // main-thread post — handled inline so the hand-off is immediate.
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.startFocusedSession(commandID: id) }
                } else {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.startFocusedSession(commandID: id) }
                    }
                }
            }
        }
    }

    deinit {
        if let practiceObserver {
            NotificationCenter.default.removeObserver(practiceObserver)
        }
    }

    /// The app-facing constructor: bundled command database + corpus + the real
    /// progress store. Content failures degrade to an empty, honest dojo rather
    /// than crashing (`isReady == false`).
    public static func bundled(store: ProgressStore = ProgressStore()) -> DojoModel {
        let database = (try? CommandDatabase.load()) ?? CommandDatabase(commands: [])
        let documents = (try? Corpus.loadAll()) ?? []
        return DojoModel(database: database, documents: documents, store: store)
    }

    // MARK: - Session lifecycle

    /// A calm adaptive set over the learner's unlocked skills.
    public func startSession(
        length: Int = DrillGenerator.defaultSessionLength,
        seed: UInt64? = nil
    ) {
        focusCommandID = nil
        begin(drills: generator.makeSession(length: length, seed: seed))
    }

    /// A focused mini-set on one command (the lookup overlay hand-off).
    public func startFocusedSession(
        commandID: String,
        length: Int = DrillGenerator.defaultFocusLength,
        seed: UInt64? = nil
    ) {
        focusCommandID = commandID
        begin(drills: generator.makeFocusedSession(
            commandID: commandID, length: length, seed: seed
        ))
    }

    /// Back to the dojo's front door.
    public func reset() {
        detachEditor()
        session = nil
        summary = nil
        feedback = nil
        focusCommandID = nil
        phase = .idle
    }

    /// Ends the set early and shows the summary for what was practiced.
    public func finishEarly() {
        guard let session else { return }
        detachEditor()
        summary = session.summary()
        phase = .summary
    }

    /// Move past this drill. Records nothing — skipping is not a wrong rep.
    public func skipDrill() {
        session?.skipCurrentDrill()
        feedback = nil
        presentCurrentDrill()
    }

    /// Put the document back the way the drill started (also happens
    /// automatically after a wrong attempt).
    public func restartDrill() {
        feedback = nil
        attachEditor(for: session?.currentDrill)
        session?.beginCurrentDrill()
    }

    // MARK: - Internals

    private func begin(drills: [Drill]) {
        summary = nil
        feedback = nil
        let session = DrillSession(drills: drills, store: store)
        self.session = session
        guard !drills.isEmpty else {
            self.summary = session.summary()
            phase = .summary
            return
        }
        phase = .drilling
        presentCurrentDrill()
    }

    private func presentCurrentDrill() {
        guard let session else { return }
        guard let drill = session.currentDrill else {
            detachEditor()
            summary = session.summary()
            phase = .summary
            return
        }
        attachEditor(for: drill)
        session.beginCurrentDrill()
    }

    private func attachEditor(for drill: Drill?) {
        detachEditor()
        guard let drill else { return }
        let editor = EditorSession(text: drill.documentText, documentName: drill.documentName)
        // Position the cursor BEFORE wiring the judge, so setup keys are never
        // mistaken for an attempt.
        editor.feed(keys: DrillEngineSupport.positioningKeys(to: drill.start))
        editor.onEvents = { [weak self] events in
            MainActor.assumeIsolated { self?.judge(events) }
        }
        self.editor = editor
        editorGeneration += 1
    }

    private func detachEditor() {
        editor?.onEvents = nil
        editor = nil
    }

    /// Judges one completed command from the editor.
    private func judge(_ events: [CommandEvent]) {
        guard let session, let drill = session.currentDrill, let editor else { return }

        let before = DrillState(
            text: drill.documentText, cursor: drill.start, mode: .normal, register: nil
        )
        let attempt = DrillAttempt(
            events: events, before: before, after: DrillState(session: editor)
        )

        guard let judgement = session.submit(attempt) else { return }
        feedback = judgement

        if judgement.isCorrect {
            presentCurrentDrill()
        } else {
            // Calm retry: hand the learner the same drill on a clean document.
            attachEditor(for: drill)
            session.beginCurrentDrill()
        }
    }
}
