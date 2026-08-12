// LevelBriefing.swift — a level's objective, in plain words, derived from the
// level itself.
//
// Why derived and not authored: the level files ALREADY say precisely what
// frees each Vimkin (`rescue: reach`, `rescue: written`) and what else must be
// true (`goals:`). Writing that a second time as prose would let the two drift,
// and the prose is exactly the thing that was missing — every level's `intro`
// is atmosphere ("You are the cursor-spirit. Start walking.") and none of them
// says the mechanic out loud.
//
// The gap this closes, found by playing World 1 cold:
//
//   • no screen ever said that you free a Vimkin by MOVING ONTO it;
//   • the boss changes the rules twice — one Vimkin is freed by TYPING a word
//     back in, and the level has an extra "finish here" goal that is not drawn
//     anywhere — so the HUD reads `4/4 vimkins` while the level refuses to end,
//     with no clue on screen about what is left.
//
// Pure Swift + Foundation, no SwiftUI: this is a text function over a value,
// and it is unit-tested as one.

import Foundation

public enum LevelBriefing {

    /// The one-line "what you are doing here", derived from how this level's
    /// Vimkins are freed. Always non-empty.
    public static func objective(for level: Level) -> String {
        let reachable = level.vimkins.filter { $0.condition.isReach }.count
        let others = level.vimkins.count - reachable

        switch (reachable, others) {
        case (0, 0):
            return "Finish the page."
        case (_, 0):
            return "Move the cursor onto each Vimkin to set it free."
        case (0, _):
            return "Free every Vimkin by mending the page."
        default:
            return "Move the cursor onto each Vimkin to set it free — "
                + "except the one caught in a word, which needs the word mended."
        }
    }

    /// The HUD form: one short line that still fits beside the stats at the
    /// minimum window width. The full sentence, with a level's exceptions, is
    /// on the intro card, and the exceptions themselves are `extraObjectives`.
    public static func shortObjective(for level: Level) -> String {
        level.vimkins.contains(where: { $0.condition.isReach })
            ? "Move the cursor onto a Vimkin to free it."
            : "Free every Vimkin by mending the page."
    }

    /// Everything beyond "reach the Vimkins" that this level requires, each as
    /// one plain sentence. Empty for an ordinary level.
    public static func extraObjectives(for level: Level) -> [String] {
        let mends = level.vimkins
            .filter { !$0.condition.isReach }
            .map { sentence(for: $0.condition, subject: .vimkin) }
        let goals = level.extraGoals.map { sentence(for: $0, subject: .level) }
        return mends + goals
    }

    /// What is still outstanding, once every Vimkin is free but the level has
    /// not ended. `nil` whenever there is nothing useful to say — so a caller
    /// can bind it straight to a banner.
    ///
    /// Deliberately keyed off counts rather than the level's private latch
    /// state: the HUD already knows both numbers, and this stays a pure
    /// function of values.
    public static func remaining(
        for level: Level, rescued: Int, isComplete: Bool
    ) -> String? {
        guard !isComplete, rescued >= level.vimkins.count, !level.vimkins.isEmpty else {
            return nil
        }
        let goals = level.extraGoals.map { sentence(for: $0, subject: .level) }
        guard !goals.isEmpty else { return nil }
        return "Everyone is free — one thing left. " + goals.joined(separator: " ")
    }

    /// What `par` means, said once, where a first-timer meets it.
    public static func parNote(for level: Level) -> String {
        "par \(level.par) keystrokes — a target, not a limit. "
            + "Take as many keys as you like; beating par is only a flourish."
    }

    // MARK: - Condition → English

    private enum Subject {
        case vimkin
        case level
    }

    private static func sentence(for condition: RescueCondition, subject: Subject) -> String {
        switch condition {
        case .cursorReaches(let position):
            let place = "line \(position.line + 1), column \(position.col + 1)"
            switch subject {
            case .vimkin: return "Bring the cursor to \(place)."
            case .level: return "Finish with the cursor on \(place)."
            }
        case .textPresent(let text):
            return "Mend the page so it says \u{201C}\(text)\u{201D} again."
        case .textRemoved(let text):
            return "Take \u{201C}\(text)\u{201D} off the page."
        case .registerContains(let text):
            return "Copy \u{201C}\(text)\u{201D} so it is on the clipboard."
        }
    }
}

extension RescueCondition {
    /// True for the plain "walk onto it" rescue — the one 38 of World 1's 39
    /// Vimkins use, and therefore the one the player is entitled to assume.
    var isReach: Bool {
        if case .cursorReaches = self { return true }
        return false
    }
}
