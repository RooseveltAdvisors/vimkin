// FirstRunStore.swift — "has this player seen this mode's one-screen guide?"
//
// Deliberately its own tiny store rather than a field on `ProgressStore`:
// `ProgressStore.completedLessons` is the STRUCTURAL source of command unlocks
// (`UnlockModel` reads it and nothing else), so writing UI bookkeeping into it
// would forge unlocks for commands that do not exist. This file sits beside
// `progress.json` and `game-progress.json` in the same directory and carries
// nothing but "you have already read this."
//
// Same defensive-path pattern as `GameProgress.swift`: the directory is
// resolved through `ProgressStore.defaultDirectories`, so the sandboxed and
// unsandboxed build flavors both land on the same file, and a read or write
// failure is recorded rather than crashing — a guide shown twice is a much
// smaller sin than a launch that dies on a corrupt JSON file.

import Foundation

/// The surfaces that carry a first-time "how this works" screen.
///
/// The Playground has none on purpose: its host view lives in `VimkinApp.swift`.
public enum GuideMode: String, CaseIterable, Codable, Sendable {
    case adventure
    case lessons
    case practice
    case dailyRun
}

/// The persisted first-run state — one small JSON document.
public struct FirstRunState: Codable, Equatable, Sendable {
    public internal(set) var schemaVersion: Int
    /// Raw values of the `GuideMode`s already shown. Stored as strings so an
    /// older build meeting a newer file ignores modes it does not know.
    public internal(set) var seenGuides: Set<String>

    public static let currentSchemaVersion = 1
    public static let empty = FirstRunState(schemaVersion: currentSchemaVersion, seenGuides: [])
}

/// Local, account-free persistence for "I have already read that."
public final class FirstRunStore {
    public private(set) var state: FirstRunState
    public let fileURL: URL
    /// Non-nil when the most recent save failed (surfaced, never silent).
    public private(set) var lastSaveError: Error?

    private let fileManager: FileManager

    public static let fileName = "first-run.json"

    /// - Parameter directory: defaults to the directory `ProgressStore`
    ///   resolves to, so all three stores travel together.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        let canonical = directory
            ?? ProgressStore.defaultDirectories(fileManager: fileManager).canonical
        self.fileURL = canonical.appendingPathComponent(Self.fileName)
        self.fileManager = fileManager
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(FirstRunState.self, from: data) {
            self.state = decoded
        } else {
            self.state = .empty
        }
    }

    // MARK: - Queries

    /// True once the mode's guide has been shown and dismissed.
    public func hasSeen(_ mode: GuideMode) -> Bool {
        state.seenGuides.contains(mode.rawValue)
    }

    /// The inverse, spelled the way call sites read best.
    public func shouldShowGuide(for mode: GuideMode) -> Bool { !hasSeen(mode) }

    // MARK: - Recording

    /// Marks a guide read. Idempotent: a second call writes nothing new.
    public func markSeen(_ mode: GuideMode) {
        guard !hasSeen(mode) else { return }
        state.seenGuides.insert(mode.rawValue)
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
