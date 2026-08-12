import Foundation
import Testing
@testable import Vimkin

/// The hub and the lessons page must never disagree about how many lessons you
/// have learned. They did: the hub counted `ProgressStore.completedLessons`,
/// which holds one entry per COMMAND a lesson teaches, so a player three
/// lessons in saw "11/16 learned" on the hub and "3 of 16" on the lessons page
/// (found by playtest, 2026-08-12).
///
/// `TutorialProgress.completedCount` is the single counter; this pins that the
/// raw set can never be mistaken for it again.
@Suite("Tutorial: the hub and the path agree on lesson count", .tags(.integration))
struct LessonCountAgreementTests {

    private func freshStore() throws -> ProgressStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vimkin-count-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProgressStore(directory: dir)
    }

    @Test("completing whole lessons counts lessons, not the commands they teach")
    func countsLessonsNotCommands() throws {
        let database = try LessonDatabase.load()
        let progress = TutorialProgress(database: database)
        let store = try freshStore()

        #expect(progress.completedCount(in: store) == 0)

        // Finish the first two lessons exactly as the app does — by unlocking
        // every command each one teaches.
        let finished = database.lessons.prefix(2)
        for lesson in finished {
            for commandID in lesson.teaches {
                store.markLessonCompleted(commandID: commandID)
            }
        }

        #expect(progress.completedCount(in: store) == finished.count)

        // The raw set is the trap: it is larger, because these lessons teach
        // more than one command each. Anything showing a lesson count to a
        // player must go through TutorialProgress.
        #expect(
            store.state.completedLessons.count > finished.count,
            "fixture too weak — pick lessons that teach several commands"
        )
    }

    @Test("a partly-finished lesson does not count")
    func partialLessonDoesNotCount() throws {
        let database = try LessonDatabase.load()
        let progress = TutorialProgress(database: database)
        let store = try freshStore()

        guard let lesson = database.lessons.first(where: { $0.teaches.count > 1 }) else {
            Issue.record("no lesson teaches more than one command")
            return
        }
        store.markLessonCompleted(commandID: lesson.teaches[0])

        #expect(progress.completedCount(in: store) == 0)
    }
}
