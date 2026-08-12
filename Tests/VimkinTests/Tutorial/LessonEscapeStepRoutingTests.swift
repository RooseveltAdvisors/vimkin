import Foundation
import Testing
@testable import Vimkin

// The first lesson in the app could not be finished by doing what it said.
//
// `Normal is home` step 2 reads "You are in Insert mode. Press `Esc` to come
// home to Normal", and asks for three of them. But `Esc` is also the chrome's
// leave-chord (`Esc Esc`): the first press scored a rep and the second threw
// the learner back to the lesson list with nothing recorded. Reproduced by hand
// on agt-2 before the fix — press `i i i`, then `Esc` (✓ "2 to go"), then `Esc`
// (ejected, "0 of 16 lessons").
//
// `LessonView` now routes `Esc` straight to the judge on a step that drills it,
// which it decides with `stepDrillsEscape`.

private func makeStore() -> ProgressStore {
    ProgressStore(directory: temporaryDirectory(), alternateDirectories: [])
}

@Suite("Steps that drill Esc keep it away from the leave chord", .tags(.acceptance))
struct LessonEscapeStepRoutingTests {

    private func modesLesson() throws -> Lesson {
        try #require(try LessonDatabase.load().lesson(id: "t1-modes"))
    }

    @Test("the concept card is not an Esc step — the chord still leaves from there")
    func conceptPhaseNeverClaimsEscape() throws {
        let coordinator = LessonCoordinator(lesson: try modesLesson(), store: makeStore())
        #expect(!coordinator.stepDrillsEscape)
    }

    @Test("a step that asks for a letter leaves Esc to the chrome")
    func letterStepDoesNotClaimEscape() throws {
        let coordinator = LessonCoordinator(lesson: try modesLesson(), store: makeStore())
        coordinator.begin()
        #expect(coordinator.step?.canonicalKeys == "i")
        #expect(!coordinator.stepDrillsEscape)
    }

    @Test("the step that asks for Esc claims it")
    func escapeStepClaimsEscape() throws {
        let coordinator = LessonCoordinator(lesson: try modesLesson(), store: makeStore())
        coordinator.begin()
        // Clear step 1 (three reps of `i`).
        while coordinator.step?.canonicalKeys == "i" && !coordinator.isComplete {
            _ = coordinator.handle(key: .char("i"))
        }
        #expect(coordinator.step?.canonicalKeys == "\u{1b}")
        #expect(coordinator.stepDrillsEscape, "the Esc step must take Esc away from the chord")
    }

    /// `LessonView`'s key filter, replicated exactly, so the ROUTING is what is
    /// under test and not just the coordinator underneath it.
    ///
    /// `guarded: false` is the pre-U21 shape — every key, `Esc` included, goes
    /// through the chrome router first.
    @MainActor
    private func lessonFilter(
        _ coordinator: LessonCoordinator,
        _ keyboard: KeyboardSurfaceModel,
        guarded: Bool,
        onAction: @escaping (NavAction) -> Void
    ) -> KeyFilter {
        { key in
            if guarded, key == .escape, coordinator.stepDrillsEscape {
                return coordinator.handle(key: key)
            }
            return keyboard.engineFilter(
                mode: { .engine },
                map: { SurfaceKeys.lessonPractice },
                base: coordinator.handle(key:),
                onAction: onAction
            )(key)
        }
    }

    @MainActor
    private func atTheEscapeStep() throws -> LessonCoordinator {
        let coordinator = LessonCoordinator(lesson: try modesLesson(), store: makeStore())
        coordinator.begin()
        while coordinator.step?.canonicalKeys == "i" && !coordinator.isComplete {
            _ = coordinator.handle(key: .char("i"))
        }
        return coordinator
    }

    @Test("the pre-fix routing ejected the learner on their second Esc")
    @MainActor
    func unguardedRoutingLeavesTheLessonOnTheSecondEscape() throws {
        let coordinator = try atTheEscapeStep()
        var actions: [NavAction] = []
        let filter = lessonFilter(
            coordinator, KeyboardSurfaceModel(), guarded: false, onAction: { actions.append($0) }
        )

        _ = filter(.escape)
        _ = filter(.escape)

        #expect(actions.contains(.back), "this is the bug: two Escs left the lesson")
        #expect(!coordinator.isComplete)
    }

    @Test("three consecutive Esc presses finish the lesson instead of ejecting")
    @MainActor
    func guardedRoutingCompletesTheLesson() throws {
        let coordinator = try atTheEscapeStep()
        var actions: [NavAction] = []
        let filter = lessonFilter(
            coordinator, KeyboardSurfaceModel(), guarded: true, onAction: { actions.append($0) }
        )

        // The exact sequence a learner types when they follow the instruction:
        // Esc, Esc, Esc, with nothing in between.
        var guardRail = 0
        while !coordinator.isComplete && guardRail < 10 {
            _ = filter(.escape)
            guardRail += 1
        }

        #expect(coordinator.isComplete, "back-to-back Esc presses must finish the lesson")
        #expect(!actions.contains(.back), "no press may have leaked to the leave chord")
    }

    @Test("once the lesson is over, Esc goes back to meaning 'leave'")
    func completedLessonReleasesEscape() throws {
        let coordinator = LessonCoordinator(lesson: try modesLesson(), store: makeStore())
        coordinator.begin()
        while coordinator.step?.canonicalKeys == "i" && !coordinator.isComplete {
            _ = coordinator.handle(key: .char("i"))
        }
        var guardRail = 0
        while !coordinator.isComplete && guardRail < 10 {
            _ = coordinator.handle(key: .escape)
            guardRail += 1
        }
        #expect(coordinator.isComplete)
        #expect(!coordinator.stepDrillsEscape, "the 'learned' card is chrome, not a drill")
    }
}
