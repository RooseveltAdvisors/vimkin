// ModeGuide.swift — the one-screen "how this works" text for each mode.
//
// Why this file exists: playtesting the app cold, the single most common
// reaction was "I don't know what game I'm playing here." Every surface told
// you the GOAL ("rescue the Vimkins", "start typing just after the cursor")
// and none of them told you the MEANS. A guide here must answer three
// questions, in this order, every time:
//
//   1. what am I doing        — the mode's job, in one plain sentence
//   2. what do I press        — the actual keys, named
//   3. how do I know it worked — the signal to look for
//
// The three are modelled as named beats rather than free prose so the shape
// cannot rot: a test asserts every mode has all three, non-empty.
//
// Voice: warm, plain, unhurried, never condescending. Matches the lines the
// app already got right ("the page resets after every try — nothing here can
// break", "No timer. No streak to lose.").
//
// Backticks are intentional and are the ONLY markup used: every consumer
// renders these through `LessonText`, which turns `like this` into a cyan
// key-cap-coloured code span. No other markdown is supported, so none is used.

import Foundation

/// One "how this works" screen.
public struct ModeGuide: Equatable, Sendable {
    /// One of the three questions, and its answer.
    public struct Beat: Equatable, Sendable, Identifiable {
        public let label: String
        public let text: String
        public var id: String { label }

        public init(label: String, text: String) {
            self.label = label
            self.text = text
        }
    }

    public let mode: GuideMode
    public let title: String
    /// One sentence of "what this place IS" before the beats.
    public let blurb: String
    /// Exactly three: doing / pressing / knowing.
    public let beats: [Beat]

    public init(mode: GuideMode, title: String, blurb: String, beats: [Beat]) {
        self.mode = mode
        self.title = title
        self.blurb = blurb
        self.beats = beats
    }

    /// The labels every guide carries, in order. Kept as constants so the
    /// three questions read identically on every screen.
    public static let doingLabel = "what you're doing"
    public static let pressingLabel = "what you press"
    public static let knowingLabel = "how you know it worked"

    // MARK: - The content

    public static func guide(for mode: GuideMode) -> ModeGuide {
        switch mode {
        case .adventure: return adventure
        case .lessons: return lessons
        case .practice: return practice
        case .dailyRun: return dailyRun
        }
    }

    public static let all: [ModeGuide] = GuideMode.allCases.map(guide(for:))

    static let adventure = ModeGuide(
        mode: .adventure,
        title: "Adventure — how this works",
        blurb: """
            Vimkins are small creatures who live inside the words of a notebook. \
            The Entropy Worm knocked them out of their sentences. You are the \
            cursor — the blinking block — and you put them back.
            """,
        beats: [
            Beat(
                label: doingLabel,
                text: """
                    Each level is one page with a few Vimkins stuck in it. \
                    Move the cursor onto a Vimkin and it is free. Free every \
                    one and the page is done.
                    """
            ),
            Beat(
                label: pressingLabel,
                text: """
                    Only the keys on the toolkit bar along the bottom work \
                    inside a level — that bar is the level's whole vocabulary. \
                    Any other key just tells you which lesson teaches it. \
                    `Esc` `Esc` leaves.
                    """
            ),
            Beat(
                label: knowingLabel,
                text: """
                    The Vimkin pops free and the vimkins counter at the top \
                    goes up. The keys counter is how many you have pressed; \
                    par beside it is a target, never a limit — take as many \
                    keys as you like, beating par is only a flourish.
                    """
            ),
        ]
    )

    static let lessons = ModeGuide(
        mode: .lessons,
        title: "Lessons — how this works",
        blurb: """
            One idea per lesson: read a short card, then practise that one \
            command on a real page until it sticks.
            """,
        beats: [
            Beat(
                label: doingLabel,
                text: """
                    A lesson is a few steps, and each step asks for the same \
                    command a few times over. The dots at the top right fill in \
                    as you get them.
                    """
            ),
            Beat(
                label: pressingLabel,
                text: """
                    The instruction always names the key to press. If it has not \
                    stuck yet, press `⌘K` — show me the keys — as often as \
                    you like; nothing is scored here. `⌘L` goes back to the \
                    lesson list.
                    """
            ),
            Beat(
                label: knowingLabel,
                text: """
                    A green ✓ and one more filled dot means that try counted. The \
                    page resets after every try — nothing here can break, and no \
                    counter ever goes backwards.
                    """
            ),
        ]
    )

    static let practice = ModeGuide(
        mode: .practice,
        title: "Practice — how this works",
        blurb: """
            A calm set of drills over real documents, leaning toward whatever \
            has gone rusty. No timer. No streak to lose.
            """,
        beats: [
            Beat(
                label: doingLabel,
                text: """
                    Each drill describes one command in plain English and \
                    asks you to do it in the document below. Twelve of them make \
                    a set.
                    """
            ),
            Beat(
                label: pressingLabel,
                text: """
                    The drill names the job, not the keys — remembering the keys \
                    is the exercise. When you would rather be shown, press `⌘K` \
                    and it will tell you. `⌘R` resets the page, `⌘J` skips, \
                    `⌘E` ends the set.
                    """
            ),
            Beat(
                label: knowingLabel,
                text: """
                    Right, and the next drill loads. Nearly right, and Vimkin \
                    names the key you reached for as well as the one it wanted. \
                    Nothing you press can hurt the document.
                    """
            ),
        ]
    )

    static let dailyRun = ModeGuide(
        mode: .dailyRun,
        title: "Daily Run — how this works",
        blurb: """
            The same fifteen drills for everyone today, against a three-minute \
            clock. This is the one place in Vimkin where speed counts.
            """,
        beats: [
            Beat(
                label: doingLabel,
                text: """
                    Clear as many of the fifteen as you can before the clock runs \
                    out. The drills read exactly like Practice — only the clock \
                    is new.
                    """
            ),
            Beat(
                label: pressingLabel,
                text: """
                    Answer and move on; there is no reveal here. `⌘J` skips a \
                    drill you do not want to spend the clock on, `⌘E` ends the \
                    run early, `Esc` `Esc` leaves.
                    """
            ),
            Beat(
                label: knowingLabel,
                text: """
                    Every clear pops its points on the right. The flame counts \
                    clean clears in a row — a longer streak is worth more per \
                    drill, up to double, and one fumble starts it over. Running \
                    out of time is not a failure; it is the end of the run.
                    """
            ),
        ]
    )
}
