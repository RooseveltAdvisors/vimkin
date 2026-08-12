// GameProgress.swift — world/level completion persistence (plan U7).
//
// Deliberately its OWN small store rather than a field on ProgressStore:
// `ProgressStore.completedLessons` is the structural source of command unlocks
// (UnlockModel reads it and nothing else), so writing level ids into it would
// quietly forge unlocks for commands that do not exist. This file sits beside
// `progress.json` in the same directory and carries only game results.

import Foundation

/// The best result recorded for one level.
public struct LevelResult: Codable, Equatable, Sendable {
    /// Fewest keystrokes used on a completed run.
    public internal(set) var bestKeystrokes: Int
    /// Vimkins rescued on the best run (equals the level's total once cleared).
    public internal(set) var vimkinsRescued: Int
    /// True once the level has been completed at least once.
    public internal(set) var completed: Bool

    public init(bestKeystrokes: Int, vimkinsRescued: Int, completed: Bool) {
        self.bestKeystrokes = bestKeystrokes
        self.vimkinsRescued = vimkinsRescued
        self.completed = completed
    }
}

/// The persisted game state — one JSON document.
public struct GameProgressState: Codable, Equatable, Sendable {
    public internal(set) var schemaVersion: Int
    /// Keyed by `Level.id`.
    public internal(set) var results: [String: LevelResult]

    public static let currentSchemaVersion = 1
    public static let empty = GameProgressState(schemaVersion: currentSchemaVersion, results: [:])
}

/// Local, account-free persistence for adventure-mode results.
public final class GameProgressStore {
    public private(set) var state: GameProgressState
    public let fileURL: URL
    /// Non-nil when the most recent save failed (surfaced, never silent).
    public private(set) var lastSaveError: Error?

    private let fileManager: FileManager

    public static let fileName = "game-progress.json"

    /// - Parameter directory: defaults to the same directory ProgressStore
    ///   resolves to, so both stores travel together across the sandboxed /
    ///   unsandboxed build flavors.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        let canonical = directory ?? ProgressStore.defaultDirectories(fileManager: fileManager).canonical
        self.fileURL = canonical.appendingPathComponent(Self.fileName)
        self.fileManager = fileManager
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(GameProgressState.self, from: data) {
            self.state = decoded
        } else {
            self.state = .empty
        }
    }

    // MARK: - Queries

    public func result(levelID: String) -> LevelResult? { state.results[levelID] }

    public func isCompleted(levelID: String) -> Bool {
        state.results[levelID]?.completed ?? false
    }

    /// A level is playable when it is the first one or the previous level has
    /// been completed. (The in-level command gate is the LockFilter's job; this
    /// is the world-map gate.)
    public func isUnlocked(level: Level, in database: LevelDatabase) -> Bool {
        guard level.order > 1 else { return true }
        guard let previous = database.level(order: level.order - 1) else { return true }
        return isCompleted(levelID: previous.id)
    }

    /// Highest order the player has cleared (0 when nothing is cleared).
    public func furthestClearedOrder(in database: LevelDatabase) -> Int {
        database.levels.filter { isCompleted(levelID: $0.id) }.map(\.order).max() ?? 0
    }

    // MARK: - Recording

    /// Records the outcome of a run. Keeps the best keystroke count; a
    /// completion is never downgraded by a later worse run.
    public func record(level: Level, keystrokes: Int, rescued: Int, completed: Bool) {
        var result = state.results[level.id]
            ?? LevelResult(bestKeystrokes: keystrokes, vimkinsRescued: rescued, completed: false)
        if completed {
            result.bestKeystrokes = result.completed
                ? min(result.bestKeystrokes, keystrokes)
                : keystrokes
            result.completed = true
        }
        result.vimkinsRescued = max(result.vimkinsRescued, rescued)
        state.results[level.id] = result
        persist()
    }

    public func save() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic])
        lastSaveError = nil
    }

    private func persist() {
        do { try save() } catch { lastSaveError = error }
    }
}
