// KeyboardSurface.swift — the SwiftUI wiring for the keyboard shell (U15).
//
// The whole app hangs off one idea: a surface declares its `KeyMap` and its
// current `InputMode`, and this file makes the keyboard work. Two entry points,
// because there are two ways a surface can be receiving keys:
//
//   1. `.keyboardSurface(...)` — the container modifier. It focuses itself,
//      reads plain keys, dispatches actions, draws the hint bar, and owns the
//      `?` help overlay. Used by every surface; it is the ONLY key source on
//      surfaces that have no editor mounted (title, world map, lesson path,
//      progress, every summary card).
//
//   2. `model.engineFilter(...)` — the filter seam of `KeyCaptureView`. On a
//      surface where an editor is mounted, the editor already owns focus and
//      returns `.handled` for every key, so the container above it never sees
//      them. Passing the chrome's router in as the editor's key FILTER puts it
//      in front of the engine without a second focus target — navigation keys
//      are answered and blocked before the engine can see them, and in engine
//      mode every key falls straight through to the engine's own filter.
//
// Both paths share one `KeyboardSurfaceModel`, so the `gg` chord and the
// `Esc Esc` leave-chord behave identically wherever the keys came in.

import SwiftUI

// MARK: - Model

/// Per-surface keyboard state: the mode arbiter plus the help overlay's flag.
///
/// A plain `@Observable` class (not actor-isolated) so it can be captured by
/// the `KeyFilter` closures `KeyCaptureView` invokes.
@Observable
public final class KeyboardSurfaceModel {
    /// The reason string used when the chrome swallows a key. Surfaces that
    /// render `onBlocked` feedback (the game's "not yet learned" toast) must
    /// ignore it — a menu key is not a locked command.
    public static let blockReason = "vimkin.chrome"

    public var showHelp = false

    @ObservationIgnored private var router = KeyRouterState()

    public init() {}

    /// True when a block came from the chrome rather than a real lock filter.
    public static func isChromeBlock(_ reason: String) -> Bool { reason == blockReason }

    public func reset() { router.reset() }

    /// Route one key and run its action. Returns the routing so the caller can
    /// decide what to tell SwiftUI (or the engine).
    @discardableResult
    public func route(
        _ key: KeyInput,
        mode: InputMode,
        map: KeyMap,
        onAction: (NavAction) -> Void
    ) -> KeyRouting {
        let routing = router.route(key, mode: mode, map: map)
        if case .navigate(let action) = routing {
            if action == .help {
                showHelp = true
            } else {
                onAction(action)
            }
        }
        return routing
    }

    /// A `KeyFilter` for `KeyCaptureView` / `EditorView` that keeps the chrome
    /// in front of the engine. See the file header for why this exists.
    ///
    /// - Parameters:
    ///   - mode: read fresh on every key — a surface changes phase mid-session.
    ///   - map: likewise.
    ///   - base: the surface's own filter (a level's lock gate, a lesson's
    ///     judge). Consulted only for keys the chrome does not take.
    public func engineFilter(
        mode: @escaping () -> InputMode,
        map: @escaping () -> KeyMap,
        base: @escaping KeyFilter = { _ in .allow },
        onAction: @escaping (NavAction) -> Void
    ) -> KeyFilter {
        { [self] key in
            // The help overlay is modal: it eats everything until it closes.
            if showHelp {
                closeHelp(on: key)
                return .block(reason: Self.blockReason)
            }
            switch route(key, mode: mode(), map: map(), onAction: onAction) {
            case .engine:
                return base(key)
            case .navigate, .pending, .ignored:
                return .block(reason: Self.blockReason)
            }
        }
    }

    /// `Esc`, `q` and `?` all dismiss the help card; anything else is swallowed
    /// so a stray key cannot leak past it.
    fileprivate func closeHelp(on key: KeyInput) {
        if key == .escape || key == .char("q") || key == .char("?") {
            showHelp = false
            reset()
        }
    }
}

// MARK: - Container modifier

public extension View {
    /// Make this view a keyboard surface. See the file header.
    ///
    /// - Parameters:
    ///   - model: shared with any `engineFilter` this surface installs.
    ///   - map: the surface's bindings (also what `?` lists).
    ///   - mode: `.engine` exactly while a practice view is capturing.
    ///   - isActive: false while something else owns the keyboard (a sheet is
    ///     up). Focus is reclaimed automatically when it flips back to true.
    ///   - hasInnerCapture: TRUE while this surface has a `KeyCaptureView` /
    ///     `EditorView` mounted whose `engineFilter` is routing plain keys.
    ///
    ///     **Exactly one router may see each physical key.** If both this
    ///     container and an inner filter route the same press, a single `Esc`
    ///     arms the leave-chord in one and fires it in the other, and the
    ///     player is thrown out of a level on one keystroke (observed on the
    ///     real app, 2026-08-11). So when an inner capture exists, this
    ///     container stops being focusable and handles ⌘-verbs only — those
    ///     bubble up because `KeyCaptureView` ignores them.
    ///   - showsHintBar: the persistent discoverability strip.
    func keyboardSurface(
        _ model: KeyboardSurfaceModel,
        map: KeyMap,
        mode: InputMode = .navigation,
        isActive: Bool = true,
        hasInnerCapture: Bool = false,
        showsHintBar: Bool = true,
        onAction: @escaping (NavAction) -> Void
    ) -> some View {
        modifier(
            KeyboardSurfaceModifier(
                model: model, map: map, mode: mode, isActive: isActive,
                hasInnerCapture: hasInnerCapture,
                showsHintBar: showsHintBar, onAction: onAction
            )
        )
    }
}

struct KeyboardSurfaceModifier: ViewModifier {
    let model: KeyboardSurfaceModel
    let map: KeyMap
    let mode: InputMode
    let isActive: Bool
    /// See `keyboardSurface(_:map:mode:isActive:hasInnerCapture:…)`.
    let hasInnerCapture: Bool
    let showsHintBar: Bool
    let onAction: (NavAction) -> Void

    @FocusState private var focused: Bool

    /// Changes whenever the surface, its phase, or its activity changes — the
    /// trigger for re-claiming the keyboard.
    private var focusToken: String {
        "\(map.title)|\(mode == .engine ? "e" : "n")|\(isActive)|\(hasInnerCapture)"
    }

    /// True when this container is the one reading plain keys.
    private var ownsPlainKeys: Bool { !hasInnerCapture }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // Never compete with an inner capture for focus — see the note on
            // `hasInnerCapture`. With one mounted this container is a pure
            // ancestor handler for the ⌘-verbs the inner view lets through.
            .focusable(ownsPlainKeys)
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(phases: [.down, .repeat], action: handle)
            // Claiming focus is the whole ballgame for a keyboard-only app, and
            // `onAppear` alone is not enough: on a route change SwiftUI tears
            // the old focusable down and the new one is not yet in the
            // responder chain when `onAppear` fires, so the keyboard lands
            // nowhere and the surface is dead. Re-asserting one runloop later —
            // keyed on the surface identity, so it re-runs on every phase and
            // route change — is what actually makes the claim stick.
            .onAppear { if ownsPlainKeys { focused = true } }
            .task(id: focusToken) {
                model.reset()
                guard ownsPlainKeys, isActive else { return }
                focused = true
                try? await Task.sleep(for: .milliseconds(60))
                focused = true
            }
            // Mouse users are still welcome; this just restores the keyboard.
            .onTapGesture { if ownsPlainKeys { focused = true } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if showsHintBar { KeyHintBar(map: map) }
                }
            }
            .overlay {
                Group {
                    if model.showHelp && isActive {
                        KeyHelpOverlay(map: map) { model.showHelp = false }
                    }
                }
            }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard isActive else { return .ignored }
        // ⌘-verbs work everywhere, including mid-drill: a ⌘ combo never reaches
        // the engine, so this is the safe channel for chrome while practising.
        if press.modifiers.contains(.command) {
            guard let character = press.characters.first,
                  let action = map.commandAction(for: character)
            else {
                return .ignored  // belongs to the menu bar
            }
            if action == .help {
                model.showHelp.toggle()
            } else {
                model.showHelp = false
                onAction(action)
            }
            return .handled
        }

        // Plain keys belong to the inner capture when there is one. Routing
        // them here as well would double-count every press.
        guard ownsPlainKeys else { return .ignored }

        // The translation pipeline is shared with the engine's own capture view,
        // burst expansion included, so a fast `gg` is never half-eaten.
        let keys = KeyCaptureView<EmptyView>.translateAll(
            key: press.key, characters: press.characters, modifiers: press.modifiers
        )
        guard !keys.isEmpty else { return .ignored }

        var handledAny = false
        for key in keys {
            if model.showHelp {
                model.closeHelp(on: key)
                handledAny = true
                continue
            }
            switch model.route(key, mode: mode, map: map, onAction: onAction) {
            case .navigate, .pending:
                handledAny = true
            case .engine, .ignored:
                // In engine mode a key that reaches this container was already
                // declined by the editor below; let it fall through.
                continue
            }
        }
        return handledAny ? .handled : .ignored
    }
}

// MARK: - Palette

enum KeyboardTheme {
    static let selection = EditorTheme.cursor          // cursor cyan #7DE8D8
    static let bar = Color(hex: 0x211C38)              // plum dark
    static let paper = EditorTheme.text                // parchment

    /// The selection highlight. Deliberately loud — a keyboard-only app has to
    /// answer "where am I?" at a glance, not with a hairline focus ring.
    static let selectionFill = EditorTheme.cursor.opacity(0.16)
    static let selectionStroke = EditorTheme.cursor.opacity(0.95)
}

public extension View {
    /// The one selection highlight used by every list and grid in the app.
    func navSelected(_ isSelected: Bool, radius: CGFloat = 10) -> some View {
        self
            .background(
                isSelected ? KeyboardTheme.selectionFill : .clear,
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        isSelected ? KeyboardTheme.selectionStroke : .clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? KeyboardTheme.selection.opacity(0.35) : .clear,
                radius: isSelected ? 10 : 0
            )
    }
}

// MARK: - Hint bar

/// The persistent, unobtrusive strip that names the bindings for the surface
/// you are on. Vimkin teaches keyboards; it may not make you guess its own.
struct KeyHintBar: View {
    let map: KeyMap

    var body: some View {
        HStack(spacing: 12) {
            // A key-cap that has wrapped onto two lines is not a key-cap any
            // more, so the strip scrolls sideways rather than reflowing — it
            // has to survive the dojo sheet's narrower window.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(map.barChips) { chip in
                        HStack(spacing: 6) {
                            ForEach(
                                Array(chip.keys.split(separator: " ").enumerated()),
                                id: \.offset
                            ) { _, cap in
                                Keycap(label: String(cap)).fixedSize()
                            }
                            Text(chip.barText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(KeyboardTheme.paper.opacity(0.55))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
            Text("no mouse needed")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(KeyboardTheme.paper.opacity(0.22))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(KeyboardTheme.bar.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KeyboardTheme.paper.opacity(0.10))
                .frame(height: 1)
        }
    }
}

// MARK: - Which-key section

/// One band of the `?` map: a heading, then its keys. Shared by the in-app
/// help overlay and the launcher's own map, so the two can never drift into
/// different-looking answers to the same question.
struct KeyGroupSection: View {
    let group: KeyChipGroup
    var keyColumnWidth: CGFloat = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(group.name.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(KeyboardTheme.selection.opacity(0.75))
                .tracking(1.2)
            ForEach(group.chips) { chip in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(
                            Array(chip.keys.split(separator: " ").enumerated()),
                            id: \.offset
                        ) { _, cap in
                            Keycap(label: String(cap)).fixedSize()
                        }
                    }
                    .frame(width: keyColumnWidth, alignment: .leading)
                    Text(chip.label)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(KeyboardTheme.paper.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

// MARK: - Help overlay

/// `?` (or ⌘/) — every binding for the current surface, plus the two rules that
/// explain the whole shell.
struct KeyHelpOverlay: View {
    let map: KeyMap
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Keys · \(map.title)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(KeyboardTheme.paper)
                    Spacer()
                    HStack(spacing: 6) {
                        Keycap(label: "Esc")
                        Text("close")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(KeyboardTheme.paper.opacity(0.5))
                    }
                }

                // Grouped, which-key style — never a flat dump of every key.
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(map.groupedChips) { group in
                        KeyGroupSection(group: group)
                    }
                }

                Divider().overlay(KeyboardTheme.paper.opacity(0.12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Vimkin is modal, like Vim.")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(KeyboardTheme.selection)
                    Text(
                        "While you are practising, EVERY key belongs to the editor — "
                            + "`j` moves the cursor, not the menu. Press `Esc` twice to leave."
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(KeyboardTheme.paper.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    Text("The mouse is never required. Anywhere.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(KeyboardTheme.paper.opacity(0.4))
                }
            }
            .padding(28)
            .frame(width: 520, alignment: .leading)
            .background(KeyboardTheme.bar.opacity(0.98), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(KeyboardTheme.selection.opacity(0.35), lineWidth: 1)
            )
            .shadow(radius: 30)
        }
        .transition(.opacity)
        // Clicking outside closes it too, but the keyboard path is the real one.
        .onTapGesture(perform: onClose)
    }
}
