// TutorialProgress.swift — read-only derivations over the ProgressStore that the
// tutorial path needs: is this lesson finished, is it unlocked yet, how rusty is
// it. Pure logic (no SwiftUI) so it is testable and the views stay dumb.
//
// Ethical-gamification note (plan R7): unlocking reads COMPLETED LESSONS only,
// never XP and never a streak — the same structural invariant `UnlockModel`
// enforces one layer down. Nothing here can gate a learner behind engagement.

public struct TutorialProgress: Sendable {
    public let database: LessonDatabase

    public init(database: LessonDatabase) {
        self.database = database
    }

    /// A lesson is complete once every command it teaches is unlocked.
    public func isComplete(_ lesson: Lesson, in store: ProgressStore) -> Bool {
        !lesson.teaches.isEmpty && lesson.teaches.allSatisfy(store.isUnlocked(commandID:))
    }

    /// Lessons open in curriculum order: the first is always available, and each
    /// later one opens when its predecessor is complete.
    public func isUnlocked(_ lesson: Lesson, in store: ProgressStore) -> Bool {
        guard let previous = database.predecessor(of: lesson) else { return true }
        return isComplete(previous, in: store)
    }

    /// The lesson to offer next: the first unfinished one.
    public func nextLesson(in store: ProgressStore) -> Lesson? {
        database.lessons.first { !isComplete($0, in: store) }
    }

    /// Weakest mastery state across the lesson's taught commands — what the path
    /// row shows, so a rusty skill is visible without nagging about it.
    public func masteryState(_ lesson: Lesson, in store: ProgressStore) -> MasteryState {
        let states = lesson.teaches.map { store.masteryState(commandID: $0) }
        for candidate in [MasteryState.unlearned, .learning, .rusty, .mastered] where states.contains(candidate) {
            return candidate
        }
        return .unlearned
    }

    public func completedCount(in store: ProgressStore) -> Int {
        database.lessons.count { isComplete($0, in: store) }
    }

    public var lessonCount: Int { database.lessons.count }
}
