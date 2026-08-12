import SwiftUI
import Testing
@testable import Vimkin

/// Tests the pure translate/filter pipeline of KeyCaptureView — no SwiftUI
/// focus simulation (per plan: rendering/focus verified visually).
@Suite("KeyCapture: translation + lock-filter pipeline", .tags(.acceptance))
struct KeyCaptureTests {
    typealias Capture = KeyCaptureView<EmptyView>

    // MARK: - Translation

    @Test func plainCharacterTranslates() {
        #expect(Capture.translate(key: "x", characters: "x", modifiers: []) == .char("x"))
        #expect(Capture.translate(key: "$", characters: "$", modifiers: [.shift]) == .char("$"))
        #expect(Capture.translate(key: "W", characters: "W", modifiers: [.shift]) == .char("W"))
    }

    @Test func escapeAndReturnTranslate() {
        #expect(Capture.translate(key: .escape, characters: "\u{1B}", modifiers: []) == .escape)
        #expect(Capture.translate(key: .return, characters: "\r", modifiers: []) == .enter)
    }

    @Test func commandModifiedKeysAreNotOurs() {
        #expect(Capture.translate(key: "q", characters: "q", modifiers: [.command]) == nil)
        #expect(Capture.translate(key: "w", characters: "w", modifiers: [.command, .shift]) == nil)
        // Even Cmd-Escape belongs to the system.
        #expect(Capture.translate(key: .escape, characters: "\u{1B}", modifiers: [.command]) == nil)
    }

    @Test func functionAndControlCharactersAreNotOurs() {
        // Arrow keys arrive in the U+F700 function-key plane.
        #expect(Capture.translate(key: .upArrow, characters: "\u{F700}", modifiers: []) == nil)
        // DEL / control chars are not engine input.
        #expect(Capture.translate(key: .delete, characters: "\u{7F}", modifiers: []) == nil)
        #expect(Capture.translate(key: "a", characters: "\u{01}", modifiers: [.control]) == nil)
        #expect(Capture.translate(key: "x", characters: "", modifiers: []) == nil)
    }

    // MARK: - Filter pipeline

    @Test func allowedKeyIsDelivered() {
        var delivered: [KeyInput] = []
        let outcome = Capture.process(
            key: "w", characters: "w", modifiers: [],
            filter: { _ in .allow },
            onKey: { delivered.append($0) }
        )
        #expect(outcome == .delivered)
        #expect(delivered == [.char("w")])
    }

    @Test func blockedKeyNeverReachesConsumerAndFiresOnBlocked() {
        var delivered: [KeyInput] = []
        var blocked: [(KeyInput, String)] = []
        let outcome = Capture.process(
            key: "d", characters: "d", modifiers: [],
            filter: { key in
                key == .char("d") ? .block(reason: "not yet learned") : .allow
            },
            onKey: { delivered.append($0) },
            onBlocked: { blocked.append(($0, $1)) }
        )
        #expect(outcome == .blocked(reason: "not yet learned"))
        #expect(delivered.isEmpty)
        #expect(blocked.count == 1)
        #expect(blocked[0].0 == .char("d"))
        #expect(blocked[0].1 == "not yet learned")
    }

    @Test func commandModifiedKeyIsIgnoredWithoutConsultingFilter() {
        var filterCalls = 0
        var delivered: [KeyInput] = []
        let outcome = Capture.process(
            key: "q", characters: "q", modifiers: [.command],
            filter: { _ in filterCalls += 1; return .block(reason: "nope") },
            onKey: { delivered.append($0) }
        )
        #expect(outcome == .ignored)
        #expect(filterCalls == 0)
        #expect(delivered.isEmpty)
    }

    @Test func blockedFilterDrivesEndToEndSessionIntegration() {
        // A blocked key never mutates the engine; an allowed one does.
        let session = EditorSession(text: "hello")
        let filter: KeyFilter = { $0 == .char("x") ? .block(reason: "locked") : .allow }

        let first = Capture.process(
            key: "x", characters: "x", modifiers: [],
            filter: filter, onKey: { session.feed($0) }
        )
        #expect(first == .blocked(reason: "locked"))
        #expect(session.buffer.text == "hello")

        let second = Capture.process(
            key: "l", characters: "l", modifiers: [],
            filter: filter, onKey: { session.feed($0) }
        )
        #expect(second == .delivered)
        #expect(session.cursor == Position(line: 0, col: 1))
    }

    /// macOS coalesces a fast burst of keystrokes into ONE key-press event whose
    /// `characters` carries every character typed. Dropping those is fatal for a
    /// Vim game — typing fast is the entire point — so a burst must expand into
    /// one engine input per character, in order.
    @Test func aCoalescedBurstDeliversEveryKeyInOrder() {
        var delivered: [KeyInput] = []
        let outcome = Capture.process(
            key: "j", characters: "jjl", modifiers: [],
            filter: { _ in .allow }, onKey: { delivered.append($0) }
        )
        #expect(outcome == .delivered)
        #expect(delivered == [.char("j"), .char("j"), .char("l")])
    }

    @Test func aCoalescedBurstMovesTheCursorOncePerKey() {
        let session = EditorSession(text: "hello world")
        _ = Capture.process(
            key: "l", characters: "lll", modifiers: [],
            filter: { _ in .allow }, onKey: { session.feed($0) }
        )
        #expect(session.cursor == Position(line: 0, col: 3))
    }

    @Test func theFilterStillGatesEveryKeyInABurst() {
        var delivered: [KeyInput] = []
        var blocked: [KeyInput] = []
        let outcome = Capture.process(
            key: "d", characters: "dxd", modifiers: [],
            filter: { $0 == .char("x") ? .block(reason: "locked") : .allow },
            onKey: { delivered.append($0) },
            onBlocked: { key, _ in blocked.append(key) }
        )
        // A burst containing a locked key still delivers the legal ones and
        // reports the block rather than swallowing the whole burst.
        #expect(delivered == [.char("d"), .char("d")])
        #expect(blocked == [.char("x")])
        #expect(outcome == .delivered)
    }

    @Test func aBurstOfSystemKeysIsStillIgnored() {
        var delivered: [KeyInput] = []
        // Arrow/function keys (U+F700 block) never belong to the engine, even
        // when several arrive together.
        let outcome = Capture.process(
            key: "a", characters: "\u{F700}\u{F701}", modifiers: [],
            filter: { _ in .allow }, onKey: { delivered.append($0) }
        )
        #expect(outcome == .ignored)
        #expect(delivered.isEmpty)
    }
}
