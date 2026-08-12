import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Vimkin

@Suite("Hotkey shortcut: codable round-trip + rejection rules", .tags(.acceptance))
struct HotkeyShortcutTests {

    // MARK: Codable round-trip

    @Test("Codable round-trip preserves keyCode and modifiers")
    func codableRoundTrip() throws {
        let original = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyShortcut.self, from: data)
        #expect(decoded == original)
    }

    // MARK: Modifier-only / no-modifier rejection

    @Test(
        "modifier-only key codes are rejected even with modifier flags held",
        arguments: [
            kVK_Shift, kVK_RightShift, kVK_Control, kVK_RightControl,
            kVK_Option, kVK_RightOption, kVK_Command, kVK_RightCommand,
            kVK_CapsLock, kVK_Function,
        ]
    )
    func modifierOnlyKeyCodesRejected(keyCode: Int) {
        let result = HotkeyShortcut.make(
            keyCode: UInt32(keyCode),
            modifierFlags: [.command, .shift]
        )
        #expect(result == nil)
    }

    @Test("a normal key with zero modifiers is rejected")
    func bareKeyRejected() {
        #expect(HotkeyShortcut.make(keyCode: UInt32(kVK_ANSI_V), modifierFlags: []) == nil)
        // Flags outside the recognized set (e.g. fn) don't count as modifiers.
        #expect(HotkeyShortcut.make(keyCode: UInt32(kVK_ANSI_V), modifierFlags: [.function]) == nil)
    }

    @Test("a normal key with modifiers maps to the right Carbon mask")
    func validShortcutAccepted() throws {
        let shortcut = try #require(
            HotkeyShortcut.make(keyCode: UInt32(kVK_ANSI_V), modifierFlags: [.command, .shift])
        )
        #expect(shortcut.keyCode == UInt32(kVK_ANSI_V))
        #expect(shortcut.modifiers == UInt32(cmdKey | shiftKey))
        #expect(shortcut.displayString == "Shift+Cmd+V")
    }

    // MARK: Default

    @Test("default summon shortcut is Cmd+Shift+V")
    func defaultShortcut() {
        #expect(HotkeyShortcut.defaultSummon.keyCode == UInt32(kVK_ANSI_V))
        #expect(HotkeyShortcut.defaultSummon.modifiers == UInt32(cmdKey | shiftKey))
        #expect(HotkeyShortcut.defaultSummon.displayString == "Shift+Cmd+V")
    }
}
