// KeyFeedback.swift — making the invisible visible: what did I just press, and
// is the engine still waiting for more of it?
//
// Two pure pieces plus one observable hub:
//
//   KeyGlyph      a key → the label printed on its key-cap
//   ChordTracker  the growing chip row: `d` → `di` → `diw`, then a beat where
//                 the finished chord stays up so you SEE the grammar compose
//   KeyFeedbackHub  what the SwiftUI visualiser observes
//
// The tracker is a value type with no clock and no UI, so the whole "is this
// chord still building?" rule is unit-testable without a running app.

import Foundation
import Observation

/// How a keystroke was judged. Never harsh: `.wrong` is coral and a wobble.
public enum KeyVerdict: Equatable, Sendable {
    case neutral
    case right
    case wrong
}

/// One rendered key-press.
public struct KeyStroke: Equatable, Sendable, Identifiable {
    public let id: Int
    public let label: String
    public var verdict: KeyVerdict

    public init(id: Int, label: String, verdict: KeyVerdict = .neutral) {
        self.id = id
        self.label = label
        self.verdict = verdict
    }
}

/// A "that's it" moment to render at the cursor.
public struct RewardPulse: Equatable, Sendable {
    public let id: Int
    public let tier: JuiceTier
    public let date: Date

    public init(id: Int, tier: JuiceTier, date: Date) {
        self.id = id
        self.tier = tier
        self.date = date
    }
}

/// The label printed on a key-cap.
public enum KeyGlyph {
    public static func label(for key: KeyInput) -> String {
        switch key {
        case .escape: return "Esc"
        case .enter: return "⏎"
        case .char(let c):
            return c == " " ? "␣" : String(c)
        }
    }

    /// Same, for an authored key STRING (`"diw"`, `"\u{1B}"`).
    public static func label(forKeys keys: String) -> String {
        keys
            .replacingOccurrences(of: "\u{1B}", with: "Esc")
            .replacingOccurrences(of: "\n", with: "⏎")
    }
}

/// Builds the growing chord chip row.
///
/// The rule is one line long: a key extends the chord while the engine is still
/// MID-COMMAND, and closes it otherwise. So `d`(mid) `i`(mid) `w`(done) renders
/// as a row that grows `d` → `d i` → `d i w` and then resolves — which is
/// exactly the shape of vim's grammar, drawn.
public struct ChordTracker: Equatable, Sendable {

    /// What the row should look like after a key.
    public enum State: Equatable, Sendable {
        /// The engine wants more keys — keep the row up and keep growing it.
        case building([String])
        /// The command closed (or fizzled) — hold the row for a beat, then drop it.
        case completed([String])

        public var keys: [String] {
            switch self {
            case .building(let keys), .completed(let keys): return keys
            }
        }
    }

    public private(set) var keys: [String] = []
    /// True once a chord closed: the NEXT key starts a fresh row.
    public private(set) var isResolved = false

    public init() {}

    /// Records one key. `midCommand` is the engine's own "still typing" verdict
    /// AFTER the key was fed (see `LessonEngineState.isMidCommand`), with Insert
    /// mode excluded by the caller — literal text typing is not a chord.
    @discardableResult
    public mutating func record(_ label: String, midCommand: Bool) -> State {
        if isResolved {
            keys.removeAll()
            isResolved = false
        }
        keys.append(label)
        if midCommand { return .building(keys) }
        isResolved = true
        return .completed(keys)
    }

    /// The chord as one string — `"diw"`.
    public var display: String { keys.joined() }

    public mutating func reset() {
        keys.removeAll()
        isResolved = false
    }
}

/// What the key-press visualiser observes. One per practice surface.
///
/// Deliberately NOT actor-isolated: it is driven from the same synchronous key
/// path the editor and the lesson coordinator already run on, and isolating it
/// would force that path async for no benefit.
@Observable
public final class KeyFeedbackHub {
    /// The key-cap currently punching in and fading out.
    public private(set) var latest: KeyStroke?
    /// The chord chip row.
    public private(set) var chord: [String] = []
    /// True while the engine still wants more of the current command.
    public private(set) var chordIsBuilding = false
    /// Bumped when something wants the surface to wobble (a wrong key).
    public private(set) var wobble: Int = 0
    /// The most recent "that's it" burst, for the editor to render at the cursor.
    public private(set) var reward: RewardPulse?

    @ObservationIgnored private var tracker = ChordTracker()
    @ObservationIgnored private var nextID = 0

    public init() {}

    // MARK: - Recording

    /// Records a key against a session's state AFTER the key was fed.
    public func observe(_ key: KeyInput, session: EditorSession) {
        observe(key, state: LessonEngineState(engine: session.engine))
    }

    /// Records a key against an explicit engine snapshot.
    public func observe(_ key: KeyInput, state: LessonEngineState) {
        nextID += 1
        latest = KeyStroke(id: nextID, label: KeyGlyph.label(for: key))

        // Insert mode is literal typing, not grammar — never a chord.
        let midCommand = state.isMidCommand && state.mode != .insert
        let outcome = tracker.record(KeyGlyph.label(for: key), midCommand: midCommand)
        chord = outcome.keys
        chordIsBuilding = { if case .building = outcome { return true }; return false }()
    }

    /// Grades the key-cap already on screen (the lesson judges after feeding).
    public func grade(_ verdict: KeyVerdict) {
        latest?.verdict = verdict
        if verdict == .wrong { wobble &+= 1 }
    }

    /// A correct rep — render a burst at the cursor.
    public func celebrate(_ tier: JuiceTier) {
        nextID += 1
        reward = RewardPulse(id: nextID, tier: tier, date: .now)
    }

    /// Drops the chord row (surface teardown, a fresh attempt).
    public func clearChord() {
        tracker.reset()
        chord = []
        chordIsBuilding = false
    }

    public func reset() {
        clearChord()
        latest = nil
        reward = nil
    }
}
