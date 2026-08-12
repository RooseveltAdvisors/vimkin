// HubModel.swift — the home screen's content, as data (U18).
//
// The hub is the first thing anyone sees, and Jon's verdict on its predecessor
// was "a bunch of small buttons on a blank canvas… everything is very
// fragmented." The fix is not bigger buttons: it is GROUPING BY INTENT, so six
// scattered modes read as four decisions — do I want to PLAY, TRAIN, check on
// MYSELF, or just mess about in a SANDBOX — and giving every entry a LIVE
// STATUS so the screen reports the state of your practice instead of being a
// launcher.
//
// Everything here is pure. `HubStatus` is a plain value a test builds inline,
// so the status wording, the grouping, and the "every jump key is unique"
// invariant are all provable without standing up a view or touching disk.
// `HubView` renders exactly what this file returns and adds nothing.

import Foundation

/// One destination on the hub.
public struct HubEntry: Identifiable, Sendable, Equatable {
    /// The key that jumps straight here from the hub.
    public let key: Character
    /// The verb the shell routes on — the same string the `KeyMap` carries, so
    /// the binding table and this list can never drift apart.
    public let verb: String
    public let title: String
    /// One line of "what this is", for someone who has never opened it.
    public let blurb: String
    /// One line of "where you stand", read from real progress.
    public let status: String

    public var id: String { verb }

    public init(key: Character, verb: String, title: String, blurb: String, status: String) {
        self.key = key
        self.verb = verb
        self.title = title
        self.blurb = blurb
        self.status = status
    }
}

/// A band of the hub — the intent grouping that stops the modes feeling loose.
public struct HubGroup: Identifiable, Sendable, Equatable {
    public let name: String
    public let entries: [HubEntry]

    public var id: String { name }

    public init(name: String, entries: [HubEntry]) {
        self.name = name
        self.entries = entries
    }
}

/// The live numbers the hub reports.
///
/// Deliberately a dumb value type: the stores are read once, in the view, and
/// handed over as plain integers. That keeps the wording rules (pluralisation,
/// the "not played today" case, the untouched-vault case) unit-testable.
public struct HubStatus: Sendable, Equatable {
    public var levelsCleared: Int
    public var levelCount: Int
    /// Today's daily-run score, or nil when today's run has not been played.
    public var todaysScore: Int?
    public var lessonsLearned: Int
    public var lessonCount: Int
    public var skillsUnlocked: Int
    public var practicedDays: Int
    public var windowDays: Int
    public var documentCount: Int

    public init(
        levelsCleared: Int = 0,
        levelCount: Int = 0,
        todaysScore: Int? = nil,
        lessonsLearned: Int = 0,
        lessonCount: Int = 0,
        skillsUnlocked: Int = 0,
        practicedDays: Int = 0,
        windowDays: Int = 40,
        documentCount: Int = 0
    ) {
        self.levelsCleared = levelsCleared
        self.levelCount = levelCount
        self.todaysScore = todaysScore
        self.lessonsLearned = lessonsLearned
        self.lessonCount = lessonCount
        self.skillsUnlocked = skillsUnlocked
        self.practicedDays = practicedDays
        self.windowDays = windowDays
        self.documentCount = documentCount
    }
}

public enum Hub {

    // MARK: - Verbs

    /// The routing verbs, named once so the key map, the view and the shell's
    /// switch all spell them the same way.
    public enum Verb {
        public static let adventure = "adventure"
        public static let daily = "daily"
        public static let lessons = "lessons"
        public static let practice = "practice"
        public static let progress = "progress"
        public static let playground = "playground"
        /// Not a destination — the hub's own `q`.
        public static let quit = "quit"
    }

    // MARK: - Groups

    /// The hub, grouped by intent, with every status line filled in.
    ///
    /// NOTE on Typing: the design calls for a `t` Typing entry in TRAIN *if the
    /// surface exists*. It does not exist on this branch, so it is omitted
    /// rather than stubbed — a card that opens nothing is worse than no card.
    public static func groups(_ status: HubStatus) -> [HubGroup] {
        [
            HubGroup(
                name: "PLAY",
                entries: [
                    HubEntry(
                        key: "a", verb: Verb.adventure, title: "Adventure",
                        blurb: "rescue the Vimkins, one page at a time",
                        status: adventureStatus(status)
                    ),
                    HubEntry(
                        key: "d", verb: Verb.daily, title: "Daily Run",
                        blurb: "today's gauntlet — three minutes, speed counts",
                        status: dailyStatus(status)
                    ),
                ]
            ),
            HubGroup(
                name: "TRAIN",
                entries: [
                    HubEntry(
                        key: "l", verb: Verb.lessons, title: "Lessons",
                        blurb: "the guided path, one idea at a time",
                        status: lessonStatus(status)
                    ),
                    HubEntry(
                        key: "p", verb: Verb.practice, title: "Practice",
                        blurb: "a calm set of drills — no timer, nothing to lose",
                        status: practiceStatus(status)
                    ),
                ]
            ),
            HubGroup(
                name: "YOU",
                entries: [
                    HubEntry(
                        key: "g", verb: Verb.progress, title: "Progress",
                        blurb: "what you know, and what is going rusty",
                        status: progressStatus(status)
                    )
                ]
            ),
            HubGroup(
                name: "SANDBOX",
                entries: [
                    HubEntry(
                        key: "y", verb: Verb.playground, title: "Playground",
                        blurb: "a real document and no rules",
                        status: playgroundStatus(status)
                    )
                ]
            ),
        ]
    }

    /// Every entry in `j`/`k` order — the groups flattened, top to bottom.
    /// This IS the navigation order, so the cursor and the drawn layout cannot
    /// disagree about which card is third.
    public static func entries(_ status: HubStatus) -> [HubEntry] {
        groups(status).flatMap(\.entries)
    }

    /// The jump keys, for the binding table and the uniqueness test.
    public static var jumpKeys: [Character] {
        entries(HubStatus()).map(\.key)
    }

    // MARK: - Status wording

    private static func adventureStatus(_ s: HubStatus) -> String {
        guard s.levelCount > 0 else { return "World 1 · the Notebook" }
        return "World 1 · \(s.levelsCleared)/\(s.levelCount) levels"
    }

    private static func dailyStatus(_ s: HubStatus) -> String {
        guard let score = s.todaysScore else { return "not played today" }
        return "today: \(score)"
    }

    private static func lessonStatus(_ s: HubStatus) -> String {
        guard s.lessonCount > 0 else { return "the path is waiting" }
        return "\(s.lessonsLearned)/\(s.lessonCount) learned"
    }

    /// Kept SHORT on purpose: the status sits on the same row as the blurb and
    /// wins the space fight (it is `fixedSize`), so a long empty-state string
    /// truncates the blurb next to it. Observed in the 900pt snapshot.
    private static func practiceStatus(_ s: HubStatus) -> String {
        guard s.skillsUnlocked > 0 else { return "nothing unlocked yet" }
        return "\(s.skillsUnlocked) skill\(s.skillsUnlocked == 1 ? "" : "s") unlocked"
    }

    private static func progressStatus(_ s: HubStatus) -> String {
        guard s.practicedDays > 0 else { return "no practice logged yet" }
        return "\(s.practicedDays) of the last \(s.windowDays) days"
    }

    /// The blurb already says "a real document and no rules", so the status
    /// carries the one thing the blurb cannot: how many there are.
    private static func playgroundStatus(_ s: HubStatus) -> String {
        guard s.documentCount > 0 else { return "scratch space" }
        return "\(s.documentCount) documents"
    }
}
