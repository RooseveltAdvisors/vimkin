import Foundation
import Testing
@testable import Vimkin

// The path's lock / complete / mastery derivations, and the R7 invariant that
// XP can never open a lesson.

private func makeStore() -> ProgressStore {
    ProgressStore(directory: temporaryDirectory(), alternateDirectories: [])
}

@Suite("Tutorial path progression", .tags(.integration))
struct TutorialProgressTests {

    @Test("only the first lesson is open on a fresh profile")
    func freshProfileOpensOnlyTheFirstLesson() throws {
        let progress = TutorialProgress(database: try LessonDatabase.load())
        let store = makeStore()
        let lessons = progress.database.lessons

        #expect(progress.isUnlocked(lessons[0], in: store))
        for lesson in lessons.dropFirst() {
            #expect(!progress.isUnlocked(lesson, in: store), "\(lesson.id) should be locked")
        }
        #expect(progress.completedCount(in: store) == 0)
        #expect(progress.nextLesson(in: store)?.id == lessons[0].id)
    }

    @Test("completing a lesson opens exactly the next one")
    func completionOpensTheNextLesson() throws {
        let progress = TutorialProgress(database: try LessonDatabase.load())
        let store = makeStore()
        let lessons = progress.database.lessons

        for id in lessons[0].teaches { store.markLessonCompleted(commandID: id) }

        #expect(progress.isComplete(lessons[0], in: store))
        #expect(progress.isUnlocked(lessons[1], in: store))
        #expect(!progress.isUnlocked(lessons[2], in: store))
        #expect(progress.nextLesson(in: store)?.id == lessons[1].id)
        #expect(progress.completedCount(in: store) == 1)
    }

    @Test("a partly-taught lesson is not complete and does not open the next one")
    func partialCompletionDoesNotUnlock() throws {
        let progress = TutorialProgress(database: try LessonDatabase.load())
        let store = makeStore()
        // A lesson that teaches more than one command.
        let lesson = try #require(progress.database.lessons.first { $0.teaches.count > 1 })
        store.markLessonCompleted(commandID: lesson.teaches[0])
        #expect(!progress.isComplete(lesson, in: store))
    }

    @Test("XP never opens a lesson")
    func xpCannotUnlock() throws {
        let progress = TutorialProgress(database: try LessonDatabase.load())
        let store = makeStore()
        for _ in 0 ..< 500 { store.awardXP(for: .fullGrammar) }
        #expect(store.totalXP > 0)
        #expect(!progress.isUnlocked(progress.database.lessons[1], in: store))
    }

    @Test("path mastery reports the weakest taught command")
    func masteryIsTheWeakestLink() throws {
        let progress = TutorialProgress(database: try LessonDatabase.load())
        let store = makeStore()
        let lesson = try #require(progress.database.lessons.first { $0.teaches.count > 1 })

        #expect(progress.masteryState(lesson, in: store) == .unlearned)
        // Drill only the first command hard; the rest stay unlearned.
        for _ in 0 ..< 20 { store.recordRep(commandID: lesson.teaches[0], outcome: .correct) }
        #expect(store.masteryState(commandID: lesson.teaches[0]) == .mastered)
        #expect(progress.masteryState(lesson, in: store) == .unlearned, "weakest link wins")
    }
}
