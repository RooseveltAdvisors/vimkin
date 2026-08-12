import Carbon.HIToolbox
import Foundation
import Testing
@testable import Vimkin

/// The summon shortcut's round-trip through a REAL `UserDefaults` suite — the
/// seam that decides whether a player's rebind survives a relaunch. (The
/// shortcut's own validation rules are pinned by `HotkeyShortcutTests` —
/// acceptance tier.)
@Suite("Hotkey shortcut: UserDefaults persistence", .tags(.integration))
struct HotkeyPersistenceTests {

    @Test("save/load through UserDefaults round-trips; nil save removes the key")
    func userDefaultsPersistence() throws {
        let suiteName = "vimkin.tests.hotkey.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "vimkin.summonShortcut"

        #expect(HotkeyShortcut.load(from: defaults, key: key) == nil)

        let shortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey)
        )
        HotkeyShortcut.save(shortcut, to: defaults, key: key)
        #expect(HotkeyShortcut.load(from: defaults, key: key) == shortcut)

        // Stored as JSON data (the vimhint pattern), not a plist blob.
        #expect(defaults.data(forKey: key) != nil)

        HotkeyShortcut.save(nil, to: defaults, key: key)
        #expect(HotkeyShortcut.load(from: defaults, key: key) == nil)
        #expect(defaults.data(forKey: key) == nil)
    }
}
