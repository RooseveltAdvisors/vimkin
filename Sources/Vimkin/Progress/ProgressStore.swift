import Foundation

/// The local persistence spine (plan U9 / KTD 6): per-command mastery, lesson
/// unlocks, XP, and ethical streaks, persisted as one JSON file under
/// Application Support with defensive sandbox/non-sandbox path resolution.
///
/// Observable-friendly: all state lives in one value-type `ProgressState`
/// exposed as `private(set)`, so a SwiftUI layer can wrap the store in
/// `@Observable` (or publish state changes) without this module importing UI.
/// Pure Swift + Foundation; deterministic time via the injected `now` closure.
///
/// Not thread-safe by design — own it from one actor/queue (the app uses it
/// from the main actor).
public final class ProgressStore {
    /// The full in-memory state (persisted verbatim).
    public private(set) var state: ProgressState

    /// File the store persists to (canonical location).
    public let fileURL: URL

    /// Non-nil when the most recent autosave failed (surfaced, never silent).
    public private(set) var lastSaveError: Error?

    private let now: () -> Date
    private let calendar: Calendar
    private let fileManager: FileManager

    public static let fileName = "progress.json"

    // MARK: - Init + defensive path resolution

    /// Opens (or creates) a progress store.
    ///
    /// - Parameters:
    ///   - directory: canonical directory for the store file. Created on
    ///     first save if missing. Defaults to Application Support/Vimkin.
    ///   - alternateDirectories: other locations a store may exist at (the
    ///     sandbox-vs-plain twin of `directory`, per the U1 note). On load,
    ///     if the canonical file is missing but an alternate has one, it is
    ///     read and migrated (written) to the canonical location. The
    ///     alternate copy is left in place (never destroys data); canonical
    ///     wins on all subsequent loads.
    ///   - now: injected clock for deterministic tests.
    ///   - calendar: calendar defining "a day" (streaks, decay).
    public init(
        directory: URL? = nil,
        alternateDirectories: [URL]? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        let resolved = Self.defaultDirectories(fileManager: fileManager)
        let canonicalDir = directory ?? resolved.canonical
        let alternates = alternateDirectories ?? resolved.alternates

        self.fileURL = canonicalDir.appendingPathComponent(Self.fileName)
        self.now = now
        self.calendar = calendar
        self.fileManager = fileManager

        if let loaded = Self.read(from: fileURL, fileManager: fileManager) {
            self.state = loaded
        } else if let migrated = alternates
            .map({ $0.appendingPathComponent(Self.fileName) })
            .compactMap({ Self.read(from: $0, fileManager: fileManager) })
            .first {
            // Store exists only at the other location — adopt it and persist
            // to the canonical location.
            self.state = migrated
            persist()
        } else {
            self.state = .empty
        }
    }

    /// Candidate store directories, defensive per the plan's U1 note: dev
    /// builds are sandboxed (Application Support resolves inside
    /// `~/Library/Containers/...`), unsigned CI builds are not (it resolves to
    /// plain `~/Library/Application Support`). Whichever flavor is running,
    /// the twin location is probed as an alternate so an existing store is
    /// never abandoned.
    public static func defaultDirectories(
        fileManager: FileManager = .default
    ) -> (canonical: URL, alternates: [URL]) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        let canonical = appSupport.appendingPathComponent("Vimkin", isDirectory: true)

        var alternates: [URL] = []
        let path = canonical.path
        if path.contains("/Library/Containers/") {
            // Sandboxed: also probe the plain (real-home) location.
            if let realHome = realUserHomeDirectory() {
                alternates.append(
                    realHome.appendingPathComponent(
                        "Library/Application Support/Vimkin", isDirectory: true)
                )
            }
        } else if let bundleID = Bundle.main.bundleIdentifier {
            // Unsandboxed: also probe the sandbox container location.
            alternates.append(
                URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
                    "Library/Containers/\(bundleID)/Data/Library/Application Support/Vimkin",
                    isDirectory: true)
            )
        }
        return (canonical, alternates)
    }

    /// The user's real home directory from the passwd database — unaffected by
    /// sandbox rewriting of `NSHomeDirectory()`.
    private static func realUserHomeDirectory() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }

    // MARK: - Mastery

    /// Records one practice repetition of a command: applies pending decay,
    /// folds the outcome into the rolling score, and counts today as a
    /// practiced day (streak + trend).
    public func recordRep(commandID: String, outcome: RepOutcome) {
        let today = dayString(now())
        var record = state.mastery[commandID] ?? MasteryRecord(
            score: 0, lastPracticedDay: today, everMastered: false, repCount: 0
        )

        // Bake accumulated decay into the stored score before updating.
        let idleDays = daysBetween(record.lastPracticedDay, today)
        record.score = MasteryModel.decayedScore(
            from: record.score,
            daysSincePractice: idleDays,
            everMastered: record.everMastered
        )

        record.score = MasteryModel.updatedScore(from: record.score, outcome: outcome)
        record.repCount += 1
        record.lastPracticedDay = today
        if record.score >= MasteryModel.masteredThreshold {
            record.everMastered = true
        }
        state.mastery[commandID] = record

        recordPracticeDay(today)
        persist()
    }

    /// The effective (decay-applied) mastery score for a command right now, 0-100.
    public func masteryScore(commandID: String) -> Double {
        guard let record = state.mastery[commandID] else { return 0 }
        return MasteryModel.decayedScore(
            from: record.score,
            daysSincePractice: daysBetween(record.lastPracticedDay, dayString(now())),
            everMastered: record.everMastered
        )
    }

    /// Learning state (unlearned / learning / mastered / rusty) as of now.
    public func masteryState(commandID: String) -> MasteryState {
        guard let record = state.mastery[commandID] else { return .unlearned }
        return MasteryModel.state(
            effectiveScore: masteryScore(commandID: commandID),
            everMastered: record.everMastered,
            repCount: record.repCount
        )
    }

    // MARK: - Lesson unlocks (XP-free by construction)

    /// Marks a lesson complete (written by the tutorial). Unlocks the command.
    public func markLessonCompleted(commandID: String) {
        state.completedLessons.insert(commandID)
        persist()
    }

    /// All unlocked command ids. Computed by `UnlockModel` from completed
    /// lessons only — the unlock API has no XP input, structurally.
    public var unlockedCommands: Set<String> {
        UnlockModel.unlockedCommands(completedLessons: state.completedLessons)
    }

    public func isUnlocked(commandID: String) -> Bool {
        unlockedCommands.contains(commandID)
    }

    // MARK: - XP (celebratory only)

    /// Awards tiered XP for a successfully executed command and returns the
    /// amount awarded. XP is additive and never gates anything.
    @discardableResult
    public func awardXP(for complexity: CommandComplexity) -> Int {
        let amount = complexity.xpAward
        state.totalXP += amount
        persist()
        return amount
    }

    public var totalXP: Int { state.totalXP }

    // MARK: - Streaks + trend

    /// The current streak, checked against today: if the gap since the last
    /// practice already exceeds the remaining grace bank, the streak is 0.
    /// (Grace is only *consumed* when practice resumes.)
    public var currentStreak: Int {
        guard let last = state.streak.lastPracticeDay else { return 0 }
        let missed = max(0, daysBetween(last, dayString(now())) - 1)
        return missed <= state.streak.graceBank ? state.streak.current : 0
    }

    public var graceDaysAvailable: Int { state.streak.graceBank }

    /// Practice-day trend over the trailing window ending today, for
    /// progress-over-perfection messaging ("32 of the last 40 days").
    public func practiceTrend(windowDays: Int = 40) -> PracticeTrend {
        let today = calendar.startOfDay(for: now())
        var practiced = 0
        for offset in 0..<max(0, windowDays) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if state.practiceDays.contains(dayString(day)) { practiced += 1 }
        }
        return PracticeTrend(practicedDays: practiced, windowDays: windowDays)
    }

    private func recordPracticeDay(_ day: String) {
        state.practiceDays.insert(day)
        let missed: Int
        if let last = state.streak.lastPracticeDay {
            missed = max(0, daysBetween(last, day) - 1)
        } else {
            missed = 0
        }
        state.streak = StreakModel.recordingPractice(state.streak, day: day, missedDays: missed)
    }

    // MARK: - Persistence

    /// Writes the state to `fileURL` atomically, creating the directory if
    /// needed. Mutating APIs autosave; call this to surface write errors.
    public func save() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
        lastSaveError = nil
    }

    private func persist() {
        do {
            try save()
        } catch {
            lastSaveError = error
        }
    }

    private static func read(from url: URL, fileManager: FileManager) -> ProgressState? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        // Defensive: a corrupt store yields nil → fresh state, never a crash.
        return try? JSONDecoder().decode(ProgressState.self, from: data)
    }

    // MARK: - Calendar-day helpers

    private func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    /// Whole calendar days from `fromDay` to `toDay` (0 for the same day).
    private func daysBetween(_ fromDay: String, _ toDay: String) -> Int {
        guard fromDay != toDay,
              let from = date(fromDay: fromDay),
              let to = date(fromDay: toDay)
        else { return 0 }
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
