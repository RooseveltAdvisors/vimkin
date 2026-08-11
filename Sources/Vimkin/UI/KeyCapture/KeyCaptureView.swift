// KeyCaptureView.swift — the shared keyboard-capture component (U4).
// Wraps any consumer view (the editor now, the SpriteKit game surface in U7),
// grabs focus, translates SwiftUI key presses into the engine's `KeyInput`, and
// runs each key through a pluggable lock-filter before delivery. Blocked keys
// never reach the consumer — they invoke `onBlocked` instead (the game's
// "not yet learned" shimmer hook). Cmd-modified keys are left to the system
// (quit, hide, …) by returning `.ignored`.
//
// The translation + filter pipeline lives in pure static functions
// (`KeyCaptureView.translate` / `KeyCaptureView.process`) so it is unit-testable
// without simulating SwiftUI focus.

import SwiftUI

/// Verdict of the pluggable key filter.
public enum KeyDecision: Equatable, Sendable {
    case allow
    case block(reason: String)
}

/// The pluggable lock-filter consulted per key.
public typealias KeyFilter = (KeyInput) -> KeyDecision

/// What the capture pipeline did with one key press.
public enum KeyCaptureOutcome: Equatable, Sendable {
    /// Key passed the filter and was delivered to the consumer.
    case delivered
    /// Key was intercepted by the filter; `onBlocked` was invoked.
    case blocked(reason: String)
    /// Key is not ours (Cmd shortcut, function key, …) — fell through to the system.
    case ignored
}

public struct KeyCaptureView<Content: View>: View {
    public typealias Filter = KeyFilter

    private let filter: Filter
    private let onKey: (KeyInput) -> Void
    private let onBlocked: ((KeyInput, String) -> Void)?
    private let content: Content

    @FocusState private var focused: Bool

    /// - Parameters:
    ///   - filter: lock-filter consulted per key; defaults to allow-everything.
    ///   - onBlocked: invoked (with the key and the block reason) when the filter blocks.
    ///   - onKey: receives every allowed key.
    public init(
        filter: @escaping Filter = { _ in .allow },
        onBlocked: ((KeyInput, String) -> Void)? = nil,
        onKey: @escaping (KeyInput) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.filter = filter
        self.onBlocked = onBlocked
        self.onKey = onKey
        self.content = content()
    }

    public var body: some View {
        content
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(phases: [.down, .repeat]) { press in
                Self.handle(
                    key: press.key,
                    characters: press.characters,
                    modifiers: press.modifiers,
                    filter: filter,
                    onKey: onKey,
                    onBlocked: onBlocked
                )
            }
            .onTapGesture { focused = true }
            .onAppear { focused = true }
    }

    // MARK: - Pure pipeline (unit-tested directly)

    /// Full pipeline for one press: translate → filter → deliver/block/ignore.
    /// Returns `.handled` for delivered AND blocked keys (a blocked key must not
    /// fall through to the system), `.ignored` for keys that are not ours.
    nonisolated static func handle(
        key: KeyEquivalent,
        characters: String,
        modifiers: EventModifiers,
        filter: Filter,
        onKey: (KeyInput) -> Void,
        onBlocked: ((KeyInput, String) -> Void)?
    ) -> KeyPress.Result {
        switch Self.process(
            key: key, characters: characters, modifiers: modifiers,
            filter: filter, onKey: onKey, onBlocked: onBlocked
        ) {
        case .delivered, .blocked:
            return .handled
        case .ignored:
            return .ignored
        }
    }

    /// Testable core: translate the press, consult the filter, invoke callbacks.
    nonisolated public static func process(
        key: KeyEquivalent,
        characters: String,
        modifiers: EventModifiers,
        filter: Filter,
        onKey: (KeyInput) -> Void,
        onBlocked: ((KeyInput, String) -> Void)? = nil
    ) -> KeyCaptureOutcome {
        guard let input = translate(key: key, characters: characters, modifiers: modifiers) else {
            return .ignored
        }
        switch filter(input) {
        case .allow:
            onKey(input)
            return .delivered
        case .block(let reason):
            onBlocked?(input, reason)
            return .blocked(reason: reason)
        }
    }

    /// Translate a SwiftUI key press into the engine's `KeyInput`.
    /// Returns nil for keys that should fall through to the system:
    /// Cmd-modified shortcuts, function/arrow keys, and control characters.
    nonisolated public static func translate(
        key: KeyEquivalent,
        characters: String,
        modifiers: EventModifiers
    ) -> KeyInput? {
        // Cmd shortcuts (quit, hide, …) always belong to the system.
        if modifiers.contains(.command) { return nil }

        if key == .escape { return .escape }
        if key == .return { return .enter }

        guard let c = characters.first, characters.count == 1 else { return nil }
        guard let scalar = c.unicodeScalars.first else { return nil }
        // Function/arrow keys arrive as U+F700–U+F8FF; control chars below 0x20
        // (Esc/Return already handled above); DEL 0x7F. None are engine input.
        if (0xF700 ... 0xF8FF).contains(scalar.value) { return nil }
        if scalar.value < 0x20 || scalar.value == 0x7F { return nil }
        return .char(c)
    }
}
