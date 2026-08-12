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

/// The U20 summon migration, through a REAL `UserDefaults` suite — the seam
/// that decides what an EXISTING install answers to after the front-door
/// rebind. Anyone who ran a pre-U20 build has Cmd+Shift+V persisted; a plain
/// "default when nothing is stored" would strand them on the old key forever.
@Suite("Summon shortcut: the Cmd+Shift+V migration", .tags(.integration))
struct SummonShortcutMigrationTests {

    private static let key = HotkeyManager.storageKey

    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "vimkin.tests.summon.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test("a fresh install gets Cmd+Shift+Space")
    func freshInstall() throws {
        try withSuite { defaults in
            #expect(
                HotkeyShortcut.resolveSummon(from: defaults, key: Self.key) == .defaultSummon
            )
        }
    }

    @Test("a stored Cmd+Shift+V from an earlier build migrates, and does not stick")
    func legacyDefaultMigrates() throws {
        try withSuite { defaults in
            HotkeyShortcut.save(.legacyDefaultSummon, to: defaults, key: Self.key)

            #expect(
                HotkeyShortcut.resolveSummon(from: defaults, key: Self.key) == .defaultSummon
            )
            // Rewritten to storage, so the recorder shows the truth and the
            // migration happens exactly once.
            #expect(HotkeyShortcut.load(from: defaults, key: Self.key) == .defaultSummon)
            // …and it is stable on the next launch.
            #expect(
                HotkeyShortcut.resolveSummon(from: defaults, key: Self.key) == .defaultSummon
            )
        }
    }

    @Test("a shortcut the player CHOSE is never migrated away")
    func userChoiceSurvives() throws {
        try withSuite { defaults in
            let chosen = HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_J),
                modifiers: UInt32(controlKey | optionKey)
            )
            HotkeyShortcut.save(chosen, to: defaults, key: Self.key)

            #expect(HotkeyShortcut.resolveSummon(from: defaults, key: Self.key) == chosen)
            #expect(HotkeyShortcut.load(from: defaults, key: Self.key) == chosen)
        }
    }

    @Test("the storage key is the contract string the recorder and manager share")
    func storageKeyContract() {
        #expect(HotkeyManager.storageKey == "vimkin.summonShortcut")
    }
}
