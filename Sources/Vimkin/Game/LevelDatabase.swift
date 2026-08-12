// LevelDatabase.swift — loads `Content/levels/world1/*.md` (plan U7).
//
// Mirrors the Corpus/LessonDatabase loading pattern: the bundle is enumerated
// (so adding a level file is enough — no Swift edit), then every file is parsed
// and the world is sorted by `order`. A malformed file throws rather than being
// skipped, so a broken level can never silently vanish from the world map.

import Foundation

public struct LevelDatabase: Sendable {
    /// Levels in play order.
    public let levels: [Level]

    public init(levels: [Level]) {
        self.levels = levels.sorted { $0.order < $1.order }
    }

    /// The World 1 resource directory inside the bundle.
    public static let world1Subdirectory = "Content/levels/world1"

    public static func loadWorld1(from bundle: Bundle = .vimkinResources) throws -> LevelDatabase {
        let urls = bundle.urls(forResourcesWithExtension: "md", subdirectory: world1Subdirectory) ?? []
        guard !urls.isEmpty else {
            throw ContentError.missingResource("\(world1Subdirectory)/*.md")
        }
        let levels = try urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url -> Level in
                let text = try String(contentsOf: url, encoding: .utf8)
                return try LevelParser.parse(text, fileName: url.lastPathComponent)
            }
        return LevelDatabase(levels: levels)
    }

    public func level(id: String) -> Level? {
        levels.first { $0.id == id }
    }

    public func level(order: Int) -> Level? {
        levels.first { $0.order == order }
    }

    /// The level after the given one, if any.
    public func next(after level: Level) -> Level? {
        self.level(order: level.order + 1)
    }
}
