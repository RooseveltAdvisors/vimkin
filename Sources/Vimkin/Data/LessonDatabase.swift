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

    /// Optional outcome previews, by lesson id (see `OutcomePreviewSpec`).
    ///
    /// Deliberately a SIDE TABLE rather than a field on `Lesson`: the preview is
    /// a property of how a lesson is *presented*, not of what it teaches, and
    /// keeping it out of the curriculum model means the tutorial runner, the
    /// completability proof and the progress store are all untouched by it.
    /// Lessons that do not opt in simply have no entry.
    public let previews: [String: OutcomePreviewSpec]

    public init(lessons: [Lesson], previews: [String: OutcomePreviewSpec] = [:]) {
        self.lessons = lessons.sorted {
            $0.tier != $1.tier ? $0.tier < $1.tier : $0.order < $1.order
        }
        self.previews = previews
    }

    /// Carries just the two fields the side table needs. Every other key in the
    /// lesson object is ignored here — `Lesson` owns those.
    private struct PreviewRow: Decodable {
        let id: String
        let outcomePreview: OutcomePreviewSpec?
    }

    /// Decodes `Content/lessons.json` from the given bundle.
    public static func load(from bundle: Bundle = .vimkinResources) throws -> LessonDatabase {
        guard let url = bundle.url(forResource: "lessons", withExtension: "json", subdirectory: "Content") else {
            throw ContentError.missingResource("Content/lessons.json")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let lessons = try decoder.decode([Lesson].self, from: data)
        let rows = try decoder.decode([PreviewRow].self, from: data)
        var previews: [String: OutcomePreviewSpec] = [:]
        for row in rows { previews[row.id] = row.outcomePreview }
        return LessonDatabase(lessons: lessons, previews: previews)
    }

    /// The outcome preview a lesson opted into, if any.
    public func preview(lessonID: String) -> OutcomePreviewSpec? {
        previews[lessonID]
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
