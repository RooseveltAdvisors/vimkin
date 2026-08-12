// ArcadeLeaderboard.swift — the self-leaderboard: today's score against your
// own past runs. No server, no other people, no rank.
//
// Its OWN JSON document beside `progress.json`, for the same structural reason
// `GameProgressStore` is separate: `ProgressStore` owns mastery and the unlock
// truth (`UnlockModel` reads `completedLessons` and nothing else), so a scored
// pressure surface must not be able to write into it — not even by accident,
// not even a field it "only reads". Two files, one directory, no shared writer.
//
// Path resolution reuses `ProgressStore.defaultDirectories`, so both stores
// travel together across the sandboxed / unsandboxed build flavors.

import Foundation

/// The persisted arcade state — one JSON document, keyed by calendar day.
public struct ArcadeLeaderboardState: Codable, Equatable, Sendable {
    public internal(set) var schemaVersion: Int
    /// One recorded run per day key ("yyyy-MM-dd").
    public internal(set) var runs: [String: ArcadeRunResult]

    public static let currentSchemaVersion = 1
    public static let empty = ArcadeLeaderboardState(
        schemaVersion: currentSchemaVersion, runs: [:]
    )
}

public final class ArcadeLeaderboardStore {
    public private(set) var state: ArcadeLeaderboardState
    public let fileURL: URL
    /// Non-nil when the most recent save failed (surfaced, never silent).
    public private(set) var lastSaveError: Error?

    private let fileManager: FileManager
    private let calendar: Calendar

    public static let fileName = "arcade.json"

    /// - Parameter directory: defaults to the same directory `ProgressStore`
    ///   resolves to.
    public init(
        directory: URL? = nil,
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        let canonical = directory
            ?? ProgressStore.defaultDirectories(fileManager: fileManager).canonical
        self.fileURL = canonical.appendingPathComponent(Self.fileName)
        self.calendar = calendar
        self.fileManager = fileManager
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ArcadeLeaderboardState.self, from: data) {
            self.state = decoded
        } else {
            // Defensive: a corrupt store yields a fresh board, never a crash.
            self.state = .empty
        }
    }

    // MARK: - Queries

    public func result(day: String) -> ArcadeRunResult? { state.runs[day] }

    /// True when the day's scored run is already in the books.
    public func hasPlayed(day: String) -> Bool { state.runs[day] != nil }

    public var runCount: Int { state.runs.count }

    /// Every recorded run, most recent day first.
    public var runs: [ArcadeRunResult] {
        state.runs.values.sorted { $0.day > $1.day }
    }

    public func recentRuns(limit: Int = 7) -> [ArcadeRunResult] {
        Array(runs.prefix(max(0, limit)))
    }

    /// The best run ever recorded (highest score; earliest day breaks a tie, so
    /// the record belongs to whoever set it first). Nil with no runs.
    public var bestRun: ArcadeRunResult? {
        state.runs.values.max { lhs, rhs in
            lhs.score != rhs.score ? lhs.score < rhs.score : lhs.day > rhs.day
        }
    }

    public var bestScore: Int? { bestRun?.score }

    /// Mean score across every recorded run. Nil with no runs (never 0 — an
    /// empty board has no average, and showing "0" would read as a bad one).
    public var averageScore: Double? {
        guard !state.runs.isEmpty else { return nil }
        let total = state.runs.values.reduce(0) { $0 + $1.score }
        return Double(total) / Double(state.runs.count)
    }

    /// Consecutive days played, ending at `day`.
    ///
    /// If today has not been played yet the count ends YESTERDAY — a streak
    /// should not read as broken at 00:01 just because the day is young. It
    /// breaks only once a whole day has gone by unplayed.
    public func dailyStreak(endingOn day: String) -> Int {
        var cursor = day
        if !hasPlayed(day: cursor) {
            guard let yesterday = ArcadeDay.day(cursor, offsetBy: -1, calendar: calendar) else {
                return 0
            }
            cursor = yesterday
        }
        var streak = 0
        while hasPlayed(day: cursor) {
            streak += 1
            guard let previous = ArcadeDay.day(cursor, offsetBy: -1, calendar: calendar) else {
                break
            }
            cursor = previous
        }
        return streak
    }

    /// Whether `score` would beat every run already on the board.
    public func isPersonalBest(score: Int) -> Bool {
        guard let best = bestScore else { return true }
        return score > best
    }

    // MARK: - Recording

    /// Records a run — ONE per day. A day already in the books is left exactly
    /// as it was and `false` is returned; replaying a finished day can neither
    /// re-score it nor corrupt the board. (The UI gates on `hasPlayed` too; this
    /// is the structural backstop underneath it.)
    @discardableResult
    public func record(_ result: ArcadeRunResult) -> Bool {
        guard state.runs[result.day] == nil else { return false }
        state.runs[result.day] = result
        persist()
        return true
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
