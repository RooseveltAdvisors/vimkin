// KeyboardNavigation.swift — the pure core of Vimkin's keyboard shell (U15).
//
// Vimkin teaches modal editing, so its own chrome is modal. Two modes:
//
//   NAVIGATION — no practice surface is capturing. Plain keys drive the menus:
//                `j`/`k` (and `h`/`l` on grids) move a visible selection,
//                `gg`/`G` jump to the ends, `⏎` opens, `Esc`/`q` go back one
//                level, `?` shows every binding for the surface you are on.
//
//   ENGINE     — a practice surface (game / lesson practice / dojo drill /
//                arcade run / playground) is capturing. EVERY key belongs to
//                the VimEngine: `j` moves the cursor, never the menu. The only
//                key the chrome takes here is a SECOND consecutive `Esc`, which
//                is a provable no-op for the engine (the first Esc already
//                returned it to normal mode with nothing pending), so nothing
//                meaningful is ever swallowed.
//
// Everything in this file is pure and free of SwiftUI, so the binding tables,
// the mode arbitration, and the selection arithmetic are unit-testable without
// simulating focus. `KeyboardSurface.swift` is the (thin) SwiftUI wiring.

import Foundation

// MARK: - Actions

/// What a key means to the chrome. Surface-specific verbs travel as `.verb`
/// so this enum never grows a case per screen.
public enum NavAction: Equatable, Sendable {
    case moveDown
    case moveUp
    case moveLeft
    case moveRight
    /// `gg` — jump to the first item.
    case first
    /// `G` — jump to the last item.
    case last
    /// `⏎` — open / confirm the selection.
    case activate
    /// `Esc` (or `q`) — one level back.
    case back
    /// `?` — the keyboard-help overlay for this surface.
    case help
    /// A surface-specific verb, e.g. `.verb("adventure")`, `.verb("skip")`.
    case verb(String)
}

// MARK: - Modes

/// Which layer owns the keyboard right now. The SURFACE decides — a practice
/// view reports `.engine` exactly while it is capturing.
public enum InputMode: Equatable, Sendable {
    case navigation
    case engine
}

/// What the router decided to do with one key.
public enum KeyRouting: Equatable, Sendable {
    /// The chrome takes it — run this action, do NOT feed the engine.
    case navigate(NavAction)
    /// Hand it to the VimEngine unchanged.
    case engine
    /// Swallowed as the first half of a chord (`g` of `gg`); nothing to do yet.
    case pending
    /// Nobody wants it.
    case ignored
}

// MARK: - Bindings

/// One row of the hint bar / help overlay. Display only — several bindings
/// (`j` and `k`) collapse into a single chip.
public struct KeyChip: Equatable, Sendable, Identifiable {
    /// The default group, for a chip that names no domain of its own.
    public static let defaultGroup = "Keys"

    /// Rendered key-caps, space separated: `"j k"`, `"gg"`, `"⏎"`, `"⌘K"`.
    public let keys: String
    /// What it does, lowercase and short: `"move"`, `"open"`, `"back"`.
    public let label: String
    /// Compact bars only have room for the essentials; the rest is `?`-only.
    public let inBar: Bool
    /// Which which-key band this belongs to — `"Move"`, `"Go"`, `"Leave"`.
    ///
    /// neovim's which-key popup groups by domain rather than listing every
    /// binding in one column, and `?` copies it: the map is scannable because
    /// the eye lands on a band first and a key second.
    public let group: String
    /// A shorter wording for the one-line hint bar, when the map's own
    /// description will not fit. A key-cap label that has been truncated to
    /// `"practise the ma…"` is worse than no label at all.
    public let barLabel: String?

    public init(
        _ keys: String,
        _ label: String,
        inBar: Bool = true,
        group: String = KeyChip.defaultGroup,
        barLabel: String? = nil
    ) {
        self.keys = keys
        self.label = label
        self.inBar = inBar
        self.group = group
        self.barLabel = barLabel
    }

    /// What the hint bar prints — the short wording when there is one.
    public var barText: String { barLabel ?? label }

    public var id: String { keys + "\u{1F}" + label }
}

/// A which-key band: a heading and the chips under it.
public struct KeyChipGroup: Equatable, Sendable, Identifiable {
    public let name: String
    public let chips: [KeyChip]

    public var id: String { name }

    public init(name: String, chips: [KeyChip]) {
        self.name = name
        self.chips = chips
    }
}

/// Every key a surface answers to, plus the chips that advertise them.
///
/// A key map is data, not behaviour: `KeyRouterState` interprets it. That split
/// is what lets a test assert "on the world map, `l` means move right" without
/// standing up a view.
public struct KeyMap: Equatable, Sendable {
    /// Shown as the heading of the help overlay.
    public let title: String
    public let bindings: [KeyInput: NavAction]
    /// ⌘-modified chrome verbs, keyed by the bare character (`"k"` for ⌘K).
    ///
    /// These are the bindings a CAPTURING surface can still offer, because
    /// `KeyCaptureView.translate` drops every ⌘ combo before the engine sees
    /// it — so ⌘K can mean "show me the keys" while plain `k` moves the cursor.
    public let commandBindings: [Character: NavAction]
    public let chips: [KeyChip]
    /// Whether `gg` / `G` mean anything here (only list-ish surfaces).
    /// Also decides whether a bare `g` opens a chord or resolves normally.
    public let hasListJumps: Bool

    public init(
        title: String,
        bindings: [KeyInput: NavAction],
        commandBindings: [Character: NavAction] = [:],
        chips: [KeyChip],
        hasListJumps: Bool = false
    ) {
        self.title = title
        self.bindings = bindings
        self.commandBindings = commandBindings.merging(["/": .help]) { existing, _ in existing }
        self.chips = chips
        self.hasListJumps = hasListJumps
    }

    public func action(for key: KeyInput) -> NavAction? { bindings[key] }

    /// Resolve a ⌘-modified press. Case-insensitive: ⌘⇧K is still ⌘K.
    public func commandAction(for character: Character) -> NavAction? {
        commandBindings[Character(character.lowercased())]
    }

    public var barChips: [KeyChip] { chips.filter(\.inBar) }

    /// Every chip, banded by `group`, in first-appearance order — what `?`
    /// draws. Order comes from the chip list itself, so a surface controls its
    /// own reading order without a second table to keep in step.
    public var groupedChips: [KeyChipGroup] {
        var order: [String] = []
        var buckets: [String: [KeyChip]] = [:]
        for chip in chips {
            if buckets[chip.group] == nil { order.append(chip.group) }
            buckets[chip.group, default: []].append(chip)
        }
        return order.map { KeyChipGroup(name: $0, chips: buckets[$0] ?? []) }
    }
}

// MARK: - The router

/// The mode arbiter. One instance per surface; it carries the only two pieces
/// of state a Vim-ish chrome needs — a pending `g`, and whether the last key
/// was an `Esc`.
public struct KeyRouterState: Equatable, Sendable {
    /// True between the two `g`s of `gg`.
    public private(set) var pendingG = false
    /// True when the immediately-preceding key was `Esc` in engine mode.
    public private(set) var escapePrimed = false

    public init() {}

    /// Route one key.
    ///
    /// The invariant this function exists to guarantee: **in `.engine` mode the
    /// only navigation action it can ever emit is `.back`, and only on a second
    /// consecutive `Esc`.** No menu binding can leak into a practice surface.
    public mutating func route(_ key: KeyInput, mode: InputMode, map: KeyMap) -> KeyRouting {
        switch mode {
        case .engine:
            // A menu chord can never be half-open while the engine has the keys.
            pendingG = false
            guard key == .escape else {
                escapePrimed = false
                return .engine
            }
            if escapePrimed {
                escapePrimed = false
                return .navigate(.back)
            }
            escapePrimed = true
            return .engine

        case .navigation:
            escapePrimed = false
            if pendingG {
                pendingG = false
                if key == .char("g") { return .navigate(.first) }
                // `g` followed by anything else: cancel the chord and let the
                // key stand on its own, the way Vim drops an unknown `g`-prefix.
            }
            if map.hasListJumps, key == .char("g") {
                pendingG = true
                return .pending
            }
            if let action = map.action(for: key) { return .navigate(action) }
            return .ignored
        }
    }

    /// Drop any half-typed chord — call when the surface or phase changes.
    public mutating func reset() {
        pendingG = false
        escapePrimed = false
    }
}

// MARK: - Selection

/// The selected index of a keyboard-navigable list or grid.
///
/// Vim semantics: movement CLAMPS, it never wraps — `k` on the first row stays
/// on the first row. `columns == 1` makes it a plain list, where `h`/`l` step
/// one item just like `k`/`j`.
public struct ListCursor: Equatable, Sendable {
    public private(set) var index: Int
    public private(set) var count: Int
    public let columns: Int

    public init(count: Int, columns: Int = 1, index: Int = 0) {
        self.count = max(0, count)
        self.columns = max(1, columns)
        self.index = Self.clamp(index, count: self.count)
    }

    /// Re-point at a list whose length changed (a filter, a reload), keeping the
    /// selection in range.
    public mutating func setCount(_ newCount: Int) {
        count = max(0, newCount)
        index = Self.clamp(index, count: count)
    }

    public mutating func select(_ newIndex: Int) {
        index = Self.clamp(newIndex, count: count)
    }

    /// Apply a movement action. Returns false for actions that are not
    /// movements, so the caller can go on to handle `.activate` / `.back` / … .
    public mutating func apply(_ action: NavAction) -> Bool {
        switch action {
        case .moveDown: move(by: columns)
        case .moveUp: move(by: -columns)
        case .moveRight: move(by: 1)
        case .moveLeft: move(by: -1)
        case .first: index = 0
        case .last: index = max(0, count - 1)
        default: return false
        }
        index = Self.clamp(index, count: count)
        return true
    }

    private mutating func move(by delta: Int) {
        guard count > 0 else { return }
        index = Self.clamp(index + delta, count: count)
    }

    private static func clamp(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(value, 0), count - 1)
    }
}
