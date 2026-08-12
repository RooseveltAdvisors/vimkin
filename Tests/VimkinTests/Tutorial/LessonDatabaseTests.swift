import Foundation
import Testing
@testable import Vimkin

// Schema + drift guards for the authored curriculum (Content/lessons.json).
// These are the cheap tests; the expensive proof that the content actually
// WORKS lives in LessonCompletabilityTests.

@Suite("Lesson database schema", .tags(.integration))
struct LessonDatabaseSchemaTests {

    private func loadLessons() throws -> LessonDatabase { try LessonDatabase.load() }

    @Test("every lesson decodes with non-empty required fields")
    func lessonsDecode() throws {
        let db = try loadLessons()
        #expect(db.lessons.count >= 12, "expected a real curriculum, got \(db.lessons.count) lessons")
        for lesson in db.lessons {
            #expect(!lesson.id.isEmpty)
            #expect(!lesson.title.isEmpty, "empty title in \(lesson.id)")
            #expect(!lesson.concept.isEmpty, "empty concept in \(lesson.id)")
            #expect(!lesson.document.isEmpty, "empty practice document in \(lesson.id)")
            #expect(!lesson.teaches.isEmpty, "\(lesson.id) teaches nothing")
            #expect(!lesson.steps.isEmpty, "\(lesson.id) has no steps")
            for step in lesson.steps {
                #expect(!step.id.isEmpty, "empty step id in \(lesson.id)")
                #expect(!step.instruction.isEmpty, "empty instruction in \(step.id)")
                #expect(!step.hint.isEmpty, "empty hint in \(step.id)")
                #expect(!step.canonicalKeys.isEmpty, "no canonical keys for \(step.id)")
                #expect(step.reps >= 1, "\(step.id) requires no reps")
            }
        }
    }

    @Test("lesson ids and step ids are unique")
    func idsUnique() throws {
        let db = try loadLessons()
        let lessonIDs = db.lessons.map(\.id)
        #expect(Set(lessonIDs).count == lessonIDs.count, "duplicate lesson id")
        for lesson in db.lessons {
            let stepIDs = lesson.steps.map(\.id)
            #expect(Set(stepIDs).count == stepIDs.count, "duplicate step id in \(lesson.id)")
        }
    }

    @Test("lesson order is contiguous 1...n within every tier")
    func orderContiguousPerTier() throws {
        let db = try loadLessons()
        #expect(db.tiers == [1, 2, 3, 4], "tutorial covers tiers 1-4; got \(db.tiers)")
        for tier in db.tiers {
            let orders = db.lessons(tier: tier).map(\.order)
            #expect(orders == Array(1...orders.count), "tier \(tier) orders are \(orders)")
        }
    }

    @Test("every target command id exists in commands.json and is engine-supported")
    func targetCommandsExistAndAreSupported() throws {
        let lessons = try loadLessons()
        let commands = try CommandDatabase.load()
        for lesson in lessons.lessons {
            for step in lesson.steps {
                guard let command = commands.command(id: step.targetCommandID) else {
                    Issue.record("\(step.id) targets unknown command \(step.targetCommandID)")
                    continue
                }
                #expect(
                    command.engineSupported,
                    "\(step.id) targets \(command.id), which the engine does not support"
                )
            }
        }
    }

    @Test("every taught command id exists, is engine-supported, and is taught once")
    func taughtCommandsExistAndAreUnique() throws {
        let lessons = try loadLessons()
        let commands = try CommandDatabase.load()
        var seen: [String: String] = [:]
        for lesson in lessons.lessons {
            for id in lesson.teaches {
                guard let command = commands.command(id: id) else {
                    Issue.record("\(lesson.id) teaches unknown command \(id)")
                    continue
                }
                #expect(command.engineSupported, "\(lesson.id) teaches unsupported command \(id)")
                if let owner = seen[id] {
                    Issue.record("\(id) is taught by both \(owner) and \(lesson.id)")
                }
                seen[id] = lesson.id
            }
        }
    }

    @Test("a lesson never teaches a command from a later tier than its own")
    func taughtCommandsMatchTier() throws {
        let lessons = try loadLessons()
        let commands = try CommandDatabase.load()
        for lesson in lessons.lessons {
            for id in lesson.teaches {
                guard let command = commands.command(id: id) else { continue }
                #expect(
                    command.tier <= lesson.tier,
                    "\(lesson.id) (tier \(lesson.tier)) teaches tier-\(command.tier) command \(id)"
                )
            }
        }
    }

    @Test("the curriculum covers all four tutorial tiers with real content")
    func tierCoverage() throws {
        let db = try loadLessons()
        for tier in 1...4 {
            #expect(!db.lessons(tier: tier).isEmpty, "tier \(tier) has no lessons")
        }
        let totalSteps = db.lessons.reduce(0) { $0 + $1.steps.count }
        #expect(totalSteps >= 30, "only \(totalSteps) drilled steps in the whole tutorial")
    }

    @Test("predecessor walks the curriculum in (tier, order) sequence")
    func predecessorOrdering() throws {
        let db = try loadLessons()
        #expect(db.predecessor(of: db.lessons[0]) == nil)
        for (index, lesson) in db.lessons.enumerated().dropFirst() {
            #expect(db.predecessor(of: lesson)?.id == db.lessons[index - 1].id)
        }
    }
}
