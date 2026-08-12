// OutcomePreview.swift — "show me where each key would land, BEFORE I press one".
//
// The pedagogical problem this solves: a lesson like "Five doors into Insert"
// teaches `i a I A o O` — six keys that all enter Insert mode and all leave the
// cursor somewhere DIFFERENT. A one-line instruction plus a static document
// makes that difference invisible: you press a key, a counter ticks, and you
// never see what the key actually DID.
//
// So the practice surface shows a GHOST cursor for every door, labelled with its
// key, before the learner presses anything. One screen, the whole lesson.
//
// The landing spot is not hand-derived — it is SIMULATED on a copy of the live
// engine (`VimEngine` is a value type, so a copy is free and side-effect-proof).
// That means a ghost can never drift from what the key really does, and the
// mechanism generalises to any keys a lesson wants to preview: motions
// (`h j k l`), anchors (`0 ^ $`), anything. Lessons opt in through
// `Content/lessons.json`; nothing here is specific to one lesson.

import Foundation

/// One previewed key, as authored in `lessons.json`.
public struct OutcomeDoor: Codable, Equatable, Sendable {
    /// The keys to preview, e.g. `"a"` or `"gg"`.
    public let keys: String
    /// Plain-language description of what it does, used both under the ghost and
    /// in the "you pressed `a` — that inserts AFTER the cursor" correction.
    public let note: String

    public init(keys: String, note: String) {
        self.keys = keys
        self.note = note
    }
}

/// A lesson's opt-in outcome preview.
public struct OutcomePreviewSpec: Codable, Equatable, Sendable {
    /// Optional one-liner shown above the ghosts.
    public let caption: String?
    public let doors: [OutcomeDoor]

    public init(caption: String? = nil, doors: [OutcomeDoor]) {
        self.caption = caption
        self.doors = doors
    }

    /// The note authored for `keys`, if this spec previews them.
    public func note(forKeys keys: String) -> String? {
        doors.first { $0.keys == keys }?.note
    }
}

/// Where a ghost cursor sits in the document grid.
public enum GhostAnchor: Equatable, Sendable {
    /// Inside an existing cell.
    case cell(Position)
    /// A brand-new line opens immediately ABOVE buffer line `line` — the ghost
    /// is drawn as a sliver on that boundary, because the line does not exist
    /// yet. (`o` on line 2 → `.newLine(above: 3)`; `O` on line 2 → `above: 2`.)
    case newLine(above: Int)
}

/// One resolved ghost: a door, plus where pressing it would actually land.
public struct OutcomeGhost: Equatable, Sendable, Identifiable {
    public let keys: String
    public let note: String
    public let anchor: GhostAnchor
    /// The mode the door leaves you in — the ghost is tinted with that mode's
    /// colour, so "these five all turn you green (Insert)" reads at a glance.
    public let mode: Mode

    public var id: String { keys }

    public init(keys: String, note: String, anchor: GhostAnchor, mode: Mode) {
        self.keys = keys
        self.note = note
        self.anchor = anchor
        self.mode = mode
    }

    /// The buffer line the ghost is drawn on, either way.
    public var line: Int {
        switch anchor {
        case .cell(let position): return position.line
        case .newLine(let above): return above
        }
    }
}

/// Resolves authored doors against a live engine by simulation.
public enum OutcomePreview {

    /// Where `door.keys` would land, computed by feeding a COPY of the engine.
    ///
    /// Pure: the caller's engine is never touched (value semantics), no clock,
    /// no randomness — the same engine and door always give the same ghost.
    public static func ghost(for door: OutcomeDoor, engine: VimEngine) -> OutcomeGhost {
        var probe = engine
        probe.feed(keys: door.keys)

        let anchor: GhostAnchor = probe.buffer.lineCount > engine.buffer.lineCount
            ? .newLine(above: probe.cursor.line)
            : .cell(probe.cursor)

        return OutcomeGhost(keys: door.keys, note: door.note, anchor: anchor, mode: probe.mode)
    }

    /// Every ghost for a spec. Empty for a lesson that did not opt in.
    public static func ghosts(for spec: OutcomePreviewSpec?, engine: VimEngine) -> [OutcomeGhost] {
        guard let spec else { return [] }
        return spec.doors.map { ghost(for: $0, engine: engine) }
    }

    /// The inline correction for a wrong key, naming the DIFFERENCE rather than
    /// scolding: "you pressed `a` — that inserts after the cursor; try `i`".
    ///
    /// Returns nil when the pressed keys are not previewed by this lesson, so
    /// the step's own authored hint stays the fallback.
    public static func correction(
        pressed: String,
        expected: String,
        spec: OutcomePreviewSpec?
    ) -> String? {
        guard let spec, pressed != expected, let note = spec.note(forKeys: pressed) else { return nil }
        return "you pressed `\(pressed)` — that \(note); try `\(expected)`"
    }
}
