import Foundation
import Testing
@testable import Vimkin

// Integration for the layer the SwiftUI lesson screen actually runs on: the
// coordinator drives an EditorSession through EditorView's key filter, judges
// every keystroke, and resets the page between attempts. Rendering is manual QA
// by design (plan U4/U5), but this proves the wiring underneath it.

private func makeStore() -> ProgressStore {
    ProgressStore(directory: temporaryDirectory(), alternateDirectories: [])
}

private func firstLesson() throws -> Lesson {
    try #require(try LessonDatabase.load().lessons.first)
}

@Suite("Lesson coordinator drives the editor session")
struct LessonCoordinatorTests {

    @Test("keys reach the session through the filter hook and are always blocked from re-delivery")
    func filterDrivesTheSessionOnce() throws {
        let lesson = try firstLesson()
        let coordinator = LessonCoordinator(lesson: lesson, store: makeStore())
        coordinator.begin()

        let session = coordinator.session
        #expect(session.mode == .normal)
        let decision = coordinator.handle(key: .char("i"))

        #expect(decision != .allow, "the coordinator already fed the key; it must not be delivered twice")
        // The correct rep resets the page, so inspect the session we captured.
        #expect(session.mode == .insert, "the key must have reached the engine")
    }

    @Test("the practice page resets after every judged attempt, right or wrong")
    func pageResetsBetweenAttempts() throws {
        let db = try LessonDatabase.load()
        let lesson = try #require(db.lesson(id: "t3-delete-verb"))
        let coordinator = LessonCoordinator(lesson: lesson, store: makeStore())
        coordinator.begin()

        let original = coordinator.session.buffer.text
        let idBefore = coordinator.attemptID
        for key in LessonRunner.keyInputs("dw") { _ = coordinator.handle(key: key) }

        #expect(coordinator.attemptID == idBefore + 1, "one attempt, one reset")
        #expect(coordinator.session.buffer.text == original, "the page comes back clean")
        #expect(coordinator.repsCompleted == 1)
    }

    @Test("a wrong key produces the step's hint, not a punishment")
    func wrongKeyShowsHint() throws {
        let db = try LessonDatabase.load()
        let lesson = try #require(db.lesson(id: "t4-inner-word"))
        let coordinator = LessonCoordinator(lesson: lesson, store: makeStore())
        coordinator.begin()
        let step = try #require(coordinator.step)

        for key in LessonRunner.keyInputs("dw") { _ = coordinator.handle(key: key) }

        #expect(coordinator.feedback == .hint(step.hint))
        #expect(coordinator.repsCompleted == 0)
        #expect(coordinator.phase == .practice)
    }

    @Test("driving a whole lesson through the coordinator reaches the learned state")
    func fullLessonThroughTheUILayer() throws {
        let db = try LessonDatabase.load()
        let store = makeStore()
        // A tier-1 and a tier-4 lesson: the shortest and the hardest wiring.
        for id in ["t1-modes", "t4-grammar-click"] {
            let lesson = try #require(db.lesson(id: id))
            let coordinator = LessonCoordinator(lesson: lesson, store: store)
            #expect(coordinator.phase == .concept)
            coordinator.begin()
            #expect(coordinator.phase == .practice)

            let cap = lesson.steps.reduce(0) { $0 + $1.reps } + 5
            for _ in 0 ..< cap {
                guard let step = coordinator.step, coordinator.phase == .practice else { break }
                for key in LessonRunner.keyInputs(step.canonicalKeys) {
                    _ = coordinator.handle(key: key)
                }
            }
            #expect(coordinator.phase == .complete, "\(id) did not reach the learned state")
            #expect(coordinator.isComplete)
        }
        // Both lessons' unlocks landed in the shared store.
        for id in ["t1-modes", "t4-grammar-click"] {
            let lesson = try #require(db.lesson(id: id))
            for command in lesson.teaches {
                #expect(store.isUnlocked(commandID: command), "\(command) not unlocked")
            }
        }
    }

    @Test("keys stay hidden until asked for, and re-hide on the next step")
    func keysRevealIsPerStep() throws {
        let db = try LessonDatabase.load()
        let lesson = try #require(db.lesson(id: "t3-delete-char"))
        let coordinator = LessonCoordinator(lesson: lesson, store: makeStore())
        coordinator.begin()
        #expect(!coordinator.keysRevealed)

        coordinator.keysRevealed = true
        let step = try #require(coordinator.step)
        for _ in 0 ..< step.reps {
            for key in LessonRunner.keyInputs(step.canonicalKeys) { _ = coordinator.handle(key: key) }
        }
        #expect(coordinator.stepNumber == 2)
        #expect(!coordinator.keysRevealed, "a new step starts with the keys hidden again")
    }

    @Test("keys after the lesson finishes are inert")
    func keysAfterCompletionAreInert() throws {
        let db = try LessonDatabase.load()
        let lesson = try #require(db.lesson(id: "t1-modes"))
        let coordinator = LessonCoordinator(lesson: lesson, store: makeStore())
        coordinator.begin()
        let cap = lesson.steps.reduce(0) { $0 + $1.reps } + 5
        for _ in 0 ..< cap {
            guard let step = coordinator.step, coordinator.phase == .practice else { break }
            for key in LessonRunner.keyInputs(step.canonicalKeys) { _ = coordinator.handle(key: key) }
        }
        #expect(coordinator.phase == .complete)
        let idBefore = coordinator.attemptID
        _ = coordinator.handle(key: .char("d"))
        #expect(coordinator.attemptID == idBefore)
    }
}
