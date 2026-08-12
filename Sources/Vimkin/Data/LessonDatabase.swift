import Foundation

/// Loads and queries `Content/lessons.json` — the tutorial curriculum (plan U5).
///
/// Deliberately a separate loader from `CommandDatabase`: lessons reference
/// commands by id, so the two files stay independently editable and a schema
/// test can prove the reference is intact (no drift between curriculum and
/// command database).
public struct LessonDatabase: Sendable {
    /// Lessons in curriculum order (tier, then order).
    public let lessons: [Lesson]

    public init(lessons: [Lesson]) {
        self.lessons = lessons.sorted {
            $0.tier != $1.tier ? $0.tier < $1.tier : $0.order < $1.order
        }
    }

    /// Decodes `Content/lessons.json` from the given bundle.
    public static func load(from bundle: Bundle = .vimkinResources) throws -> LessonDatabase {
        guard let url = bundle.url(forResource: "lessons", withExtension: "json", subdirectory: "Content") else {
            throw ContentError.missingResource("Content/lessons.json")
        }
        let data = try Data(contentsOf: url)
        return LessonDatabase(lessons: try JSONDecoder().decode([Lesson].self, from: data))
    }

    public func lesson(id: String) -> Lesson? {
        lessons.first { $0.id == id }
    }

    /// Lessons of one curriculum tier, in order.
    public func lessons(tier: Int) -> [Lesson] {
        lessons.filter { $0.tier == tier }
    }

    /// Tiers present, ascending.
    public var tiers: [Int] {
        Array(Set(lessons.map(\.tier))).sorted()
    }

    /// The lesson immediately before `lesson` in curriculum order, if any.
    public func predecessor(of lesson: Lesson) -> Lesson? {
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }), index > 0 else { return nil }
        return lessons[index - 1]
    }
}
