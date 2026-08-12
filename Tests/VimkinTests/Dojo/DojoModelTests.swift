import Foundation
import Testing
@testable import Vimkin

@Suite("Dojo: model orchestration and the \"Practice this →\" hand-off", .tags(.acceptance))
@MainActor
struct DojoModelTests {

    private func makeModel(
        unlocking commandIDs: [String],
        observesPracticeRequests: Bool = false
    ) throws -> (model: DojoModel, store: ProgressStore) {
        let content = try dojoContent()
        let store = makeDojoStore(unlocking: commandIDs)
        let model = DojoModel(
            database: content.database,
            documents: content.documents,
            store: store,
            observesPracticeRequests: observesPracticeRequests
        )
        return (model, store)
    }

    // MARK: - Practice-notification wiring

    @Test("posting practiceCommandNotification opens a session focused on that command")
    func practiceNotificationStartsFocusedSession() throws {
        let (model, _) = try makeModel(unlocking: [], observesPracticeRequests: true)
        #expect(model.phase == .idle)

        NotificationCenter.default.post(
            name: OverlayController.practiceCommandNotification,
            object: "grammar.delete-inside-quotes"
        )

        #expect(model.phase == .drilling)
        #expect(model.focusCommandID == "grammar.delete-inside-quotes")
        let session = try #require(model.session)
        #expect(!session.drills.isEmpty)
        #expect(session.drills.allSatisfy { $0.commandID == "grammar.delete-inside-quotes" })
        #expect(model.currentDrill?.commandID == "grammar.delete-inside-quotes")
        // The overlay hand-off is explicit user intent: it works even though the
        // command's lesson has not been completed yet.
        #expect(model.editor != nil)
        #expect(model.editor?.cursor == model.currentDrill?.start)
    }

    @Test("a notification with no command id is ignored")
    func notificationWithoutIDIsIgnored() throws {
        let (model, _) = try makeModel(unlocking: [], observesPracticeRequests: true)
        NotificationCenter.default.post(
            name: OverlayController.practiceCommandNotification, object: nil
        )
        #expect(model.phase == .idle)
    }

    // MARK: - Playing a drill through the model

    @Test("typing the right keys advances the drill; a wrong command resets the document")
    func playingThroughTheModel() throws {
        let (model, _) = try makeModel(unlocking: ["grammar.delete-inner-word"])
        model.startFocusedSession(commandID: "grammar.delete-inner-word", length: 3, seed: 6)

        let first = try #require(model.currentDrill)
        let editor = try #require(model.editor)

        // A wrong-but-related command: judged as a near miss, document restored.
        editor.feed(keys: "dw")
        guard case .nearMiss(let miss) = try #require(model.feedback) else {
            Issue.record("expected a near miss, got \(String(describing: model.feedback))")
            return
        }
        #expect(miss.performedKeys == "dw")
        #expect(model.currentDrill?.id == first.id, "a wrong attempt must not skip the drill")
        let restored = try #require(model.editor)
        #expect(restored.buffer.text == first.documentText, "the document must be pristine on retry")
        #expect(restored.cursor == first.start)

        // Now solve it.
        restored.feed(keys: first.solutionKeys)
        #expect(model.feedback == .correct)
        #expect(model.currentDrill?.id != first.id)
        #expect(model.phase == .drilling)
    }

    @Test("finishing every drill lands on the summary phase")
    func sessionCompletionShowsSummary() throws {
        let (model, _) = try makeModel(unlocking: ["action.delete-line"])
        model.startFocusedSession(commandID: "action.delete-line", length: 2, seed: 9)

        for _ in 0..<2 {
            let drill = try #require(model.currentDrill)
            try #require(model.editor).feed(keys: drill.solutionKeys)
        }

        #expect(model.phase == .summary)
        let summary = try #require(model.summary)
        #expect(summary.drillsPlanned == 2)
        #expect(summary.drillsCompleted == 2)
        #expect(summary.accuracyPercent == 100)
        #expect(model.editor == nil)
    }

    @Test("setup keystrokes that place the cursor are never judged as attempts")
    func setupKeysAreNotAttempts() throws {
        let (model, _) = try makeModel(unlocking: ["motion.word-forward"])
        model.startFocusedSession(commandID: "motion.word-forward", length: 2, seed: 3)
        #expect(model.feedback == nil)
        #expect(model.session?.attempts.isEmpty == true)
    }

    @Test("a session with no unlocked commands goes straight to an honest empty summary")
    func emptySessionIsHonest() throws {
        let (model, _) = try makeModel(unlocking: [])
        model.startSession(length: 10, seed: 1)
        #expect(model.phase == .summary)
        #expect(model.summary?.drillsPlanned == 0)
        #expect(model.editor == nil)
    }

    @Test("skip moves on without recording a wrong rep")
    func skipDoesNotPunish() throws {
        let (model, store) = try makeModel(unlocking: ["action.delete-line"])
        model.startFocusedSession(commandID: "action.delete-line", length: 2, seed: 4)
        let first = try #require(model.currentDrill)

        model.skipDrill()
        #expect(model.currentDrill?.id != first.id)
        #expect(store.masteryState(commandID: "action.delete-line") == .unlearned)
    }

    @Test("restartDrill puts the document back without judging anything")
    func restartDrillIsFree() throws {
        let (model, _) = try makeModel(unlocking: ["action.delete-line"])
        model.startFocusedSession(commandID: "action.delete-line", length: 2, seed: 4)
        let drill = try #require(model.currentDrill)

        try #require(model.editor).feed(keys: "x")   // messes up the document
        model.restartDrill()

        #expect(model.feedback == nil)
        #expect(model.currentDrill?.id == drill.id)
        #expect(model.editor?.buffer.text == drill.documentText)
    }

    @Test("reset returns the dojo to its front door")
    func resetGoesIdle() throws {
        let (model, _) = try makeModel(unlocking: ["action.delete-line"])
        model.startFocusedSession(commandID: "action.delete-line", length: 2, seed: 4)
        model.reset()
        #expect(model.phase == .idle)
        #expect(model.session == nil)
        #expect(model.editor == nil)
        #expect(model.focusCommandID == nil)
    }
}
