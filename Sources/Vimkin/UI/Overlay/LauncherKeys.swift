// LauncherKeys.swift — the launcher's routing table (U20).
//
// The launcher is Vimkin's FRONT DOOR: `⌘⇧Space` summons it from anywhere,
// and from there one mnemonic key opens any surface in the app — the same
// shape as tmux's `C-a` prefix followed by a single key, and the same letters
// the hub already prints on its cards.
//
// The load-bearing rule lives here rather than in the view, because it is the
// one that decides whether the app is usable at all:
//
//     TYPING ALWAYS SEARCHES. `:` OPENS COMMAND MODE.
//
// An earlier design made bare letters jump while the query was empty, with `/`
// to stand them down. Playing it killed that idea: the query is ALWAYS empty
// when you begin typing, so "delete inside quotes" fired Daily Run on the `d`
// and quit the app on the `q`. Six of the mnemonics are the first letters of
// delete, append, yank, paste, line and goto — a slab of the Vim vocabulary
// the launcher exists to look up.
//
// So the launcher takes Vim's own answer: text is a search, and `:` is how you
// address the program. Lookup — the thing done fifty times a day — costs zero
// extra keys, and jumping to a surface costs one. Keeping the rule pure means
// it is provable without simulating focus, and the view cannot quietly
// disagree with it.

import Foundation

/// One key-to-surface entry on the launcher.
public struct LauncherDestination: Equatable, Sendable, Identifiable {
    /// The single mnemonic key, on an empty query.
    public let key: Character
    /// The hub verb the shell routes on — the SAME string the hub uses, so the
    /// launcher can never open something the hub cannot.
    public let verb: String
    public let title: String
    /// One line of what it is, for the which-key chips.
    public let blurb: String

    public var id: String { verb }

    public init(key: Character, verb: String, title: String, blurb: String) {
        self.key = key
        self.verb = verb
        self.title = title
        self.blurb = blurb
    }
}

/// What one key press means to the launcher.
public enum LauncherRouting: Equatable, Sendable {
    /// Open a surface in the main window and dismiss the launcher.
    case open(verb: String)
    /// Show the launcher's own which-key map.
    case help
    /// Enter command mode — the NEXT key is read as a destination, not typed.
    /// Vim's `:`.
    case startCommand
    /// Dismiss the launcher.
    case dismiss
    /// The launcher does not want this key — it belongs to the search field.
    case type
}

public enum LauncherKeys {

    /// `?` — show the map, on an empty field or in command mode. The reason
    /// nobody has to memorise the rest.
    public static let helpKey: Character = "?"

    /// `:` — address the program, exactly as it does in Vim. The next key is a
    /// destination rather than text.
    public static let commandKey: Character = ":"

    /// Every destination, in hub order.
    ///
    /// Derived from `Hub.entries` so the launcher, the hub's cards and the
    /// hub's key map are ONE list. A destination cannot exist on the launcher
    /// that the hub does not have (or vice versa), and no key can drift.
    public static var destinations: [LauncherDestination] {
        Hub.entries(HubStatus()).map {
            LauncherDestination(key: $0.key, verb: $0.verb, title: $0.title, blurb: $0.blurb)
        }
    }

    /// The verb a key opens, ignoring the query. `nil` for anything that is
    /// not a destination.
    public static func destination(for character: Character) -> LauncherDestination? {
        destinations.first { $0.key == character }
    }

    /// Route one character press.
    ///
    /// - Parameters:
    ///   - character: the typed character.
    ///   - query: what is already in the search field.
    ///   - searchArmed: `/` was pressed on an empty field, so the mnemonics
    ///     have stood down until the field is empty again.
    ///
    /// A non-empty query means `.type` for EVERY character — including `?` and
    /// every destination letter. `Esc` is not routed here: it dismisses at any
    /// time, query or no query, and the view binds it directly.
    public static func route(
        character: Character,
        query: String,
        commandArmed: Bool = false
    ) -> LauncherRouting {
        // Command mode: this key addresses the program, whatever is typed.
        if commandArmed {
            if character == helpKey { return .help }
            if let destination = destination(for: character) { return .open(verb: destination.verb) }
            // An unknown command key falls back to typing rather than eating
            // the press — a wrong guess should never feel like a dead key.
            return .type
        }
        // `:` only opens command mode from an empty field; mid-query it is a
        // literal colon, so a YAML-ish search like `key: value` still types.
        if query.isEmpty, character == commandKey { return .startCommand }
        if query.isEmpty, character == helpKey { return .help }
        return .type
    }
}
