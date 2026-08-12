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
//     LETTERS JUMP ONLY WHILE THE QUERY IS EMPTY.
//
// The moment there is a search query, every letter belongs to the search
// field — otherwise typing "adventure" would fire six different destinations
// before the third character. Keeping the rule pure means it is provable
// without simulating focus, and the view cannot quietly disagree with it.

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
    /// Arm the search field so the NEXT letters type even though the query is
    /// still empty — Vim's `/`.
    case startSearch
    /// Dismiss the launcher.
    case dismiss
    /// The launcher does not want this key — it belongs to the search field.
    case type
}

public enum LauncherKeys {

    /// `?` — show the map. The one non-destination key that acts on an empty
    /// query, and the reason nobody has to memorise the rest.
    public static let helpKey: Character = "?"

    /// `/` — start a search, exactly as it does in Vim.
    ///
    /// Six of the twenty-six letters are mnemonics, and they include the
    /// first letter of `delete`, `append`, `yank`, `paste`, `line` and
    /// `goto` — so without this, a whole slab of the Vim vocabulary could
    /// never begin a query. `/` arms the field: the mnemonics stand down and
    /// everything types, which is what a Vim user's hand does anyway.
    public static let searchKey: Character = "/"

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
        searchArmed: Bool = false
    ) -> LauncherRouting {
        guard query.isEmpty, !searchArmed else { return .type }
        if character == searchKey { return .startSearch }
        if character == helpKey { return .help }
        if let destination = destination(for: character) { return .open(verb: destination.verb) }
        return .type
    }
}
