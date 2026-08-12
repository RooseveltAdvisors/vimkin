import Foundation
import Testing
@testable import Vimkin

/// The launcher's key→destination table and the precedence rule that makes it
/// usable (U20).
///
/// The rule under test is the one that decides whether the front door works at
/// all: **letters open a surface only while the query is empty.** Get it
/// backwards and typing "adventure" fires six destinations before the third
/// character — so it is asserted from both sides, on every mnemonic.

@Suite("Launcher: the front-door key routing table", .tags(.acceptance))
struct LauncherRoutingTests {

    // MARK: The destinations

    @Test("the six mnemonics are the ones docs/keymap.md prints")
    func mnemonicsMatchTheSpec() {
        let expected: [(Character, String)] = [
            ("a", Hub.Verb.adventure),
            ("d", Hub.Verb.daily),
            ("l", Hub.Verb.lessons),
            ("p", Hub.Verb.practice),
            ("g", Hub.Verb.progress),
            ("y", Hub.Verb.playground),
        ]
        #expect(LauncherKeys.destinations.count == expected.count)
        for (key, verb) in expected {
            let destination = LauncherKeys.destination(for: key)
            #expect(destination?.verb == verb, "`\(key)` should open \(verb)")
        }
    }

    /// The launcher and the hub are ONE list, so a key can never mean two
    /// different things on the two front doors.
    @Test("every launcher key is the hub's key for the same surface")
    func launcherAgreesWithTheHub() {
        let hub = Hub.entries(HubStatus())
        #expect(LauncherKeys.destinations.map(\.key) == hub.map(\.key))
        #expect(LauncherKeys.destinations.map(\.verb) == hub.map(\.verb))
        for destination in LauncherKeys.destinations {
            #expect(
                SurfaceKeys.hub.action(for: .char(destination.key))
                    == .verb(destination.verb),
                "the hub disagrees about `\(destination.key)`"
            )
        }
    }

    @Test("no two destinations share a key, and none of them quits the app")
    func keysAreUniqueAndSafe() {
        let keys = LauncherKeys.destinations.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(!LauncherKeys.destinations.contains { $0.verb == Hub.Verb.quit })
        // `?` is the map, so it may never also be a destination.
        #expect(LauncherKeys.destination(for: LauncherKeys.helpKey) == nil)
    }

    // MARK: Precedence — the load-bearing rule

    @Test("on an EMPTY query, a bare letter types — it does not jump")
    func emptyQueryTypes() {
        for destination in LauncherKeys.destinations {
            #expect(
                LauncherKeys.route(character: destination.key, query: "") == .type,
                "`\(destination.key)` jumped instead of typing"
            )
        }
        // `?` is the one bare key that acts, because no search begins with it.
        #expect(LauncherKeys.route(character: "?", query: "") == .help)
    }

    @Test("the MOMENT a query exists, the same letters type instead")
    func typingWins() {
        for destination in LauncherKeys.destinations {
            #expect(
                LauncherKeys.route(character: destination.key, query: "d") == .type,
                "`\(destination.key)` jumped while a query was running"
            )
        }
        // Including `?` — a search for "why?" must not open the map.
        #expect(LauncherKeys.route(character: "?", query: "why") == .type)
    }

    /// The bug this design replaced: bare letters used to jump on an empty
    /// field, so the launcher's own canonical query fired Daily Run on its `d`
    /// and quit the app on the trailing `q`. Typing must never address the
    /// program.
    @Test("typing \"delete inside quotes\" types every character, jumping nowhere")
    func typingNeverJumps() {
        var query = ""
        var jumped = false

        for character in "delete inside quotes" {
            switch LauncherKeys.route(character: character, query: query) {
            case .type: query.append(character)
            case .startCommand, .open, .help, .dismiss: jumped = true
            }
        }

        #expect(!jumped, "typing a search addressed the program")
        #expect(query == "delete inside quotes")
    }

    /// Every mnemonic is the first letter of a word the launcher exists to look
    /// up — delete, append, yank, paste, line, goto. Each must be typeable.
    @Test("every mnemonic letter can begin a search")
    func mnemonicsCanBeginASearch() {
        for destination in LauncherKeys.destinations {
            #expect(
                LauncherKeys.route(character: destination.key, query: "") == .type,
                "`\(destination.key)` was eaten instead of typed"
            )
        }
    }

    // MARK: `:` — Vim's own way to address the program

    @Test(": on an empty field opens command mode")
    func colonOpensCommandMode() {
        #expect(LauncherKeys.route(character: ":", query: "") == .startCommand)
        // Mid-query a colon is a literal colon, so `key: value` still types.
        #expect(LauncherKeys.route(character: ":", query: "key") == .type)
    }

    @Test("in command mode, one letter opens its surface")
    func commandModeOpensSurfaces() {
        for destination in LauncherKeys.destinations {
            #expect(
                LauncherKeys.route(character: destination.key, query: "", commandArmed: true)
                    == .open(verb: destination.verb),
                "`:\(destination.key)` did not open \(destination.verb)"
            )
        }
        #expect(LauncherKeys.route(character: "?", query: "", commandArmed: true) == .help)
    }

    /// A wrong guess after `:` must not feel like a dead key.
    @Test("an unclaimed command key falls back to typing")
    func unknownCommandKeyTypes() {
        #expect(LauncherKeys.route(character: "z", query: "", commandArmed: true) == .type)
    }

    @Test("a key that is not a mnemonic always types, query or no query")
    func unboundKeysType() {
        for character in "zxcvbnm" {
            #expect(LauncherKeys.route(character: character, query: "") == .type)
            #expect(LauncherKeys.route(character: character, query: "go") == .type)
        }
    }

    // MARK: The map the launcher shows

    @Test("the launcher's ? map names every destination, grouped")
    func mapAdvertisesEveryDestination() {
        let map = SurfaceKeys.launcher
        let groups = map.groupedChips
        #expect(groups.count > 1, "the map is a flat dump, not a which-key map")
        #expect(groups.allSatisfy { !$0.name.isEmpty })

        let go = groups.first { $0.name == SurfaceKeys.Group.go }
        let advertised = Set(go?.chips.map(\.keys) ?? [])
        for destination in LauncherKeys.destinations {
            #expect(
                advertised.contains(":" + String(destination.key)),
                "the map never mentions `\(destination.key)`"
            )
        }
        // …and the three keys that are not destinations.
        let all = map.chips.map(\.keys)
        #expect(all.contains("?"))
        #expect(all.contains("Esc"))
        #expect(all.contains(String(LauncherKeys.commandKey)))
    }
}

/// The channel the launcher reaches the main window over. It is the same
/// NotificationCenter precedent as the "Practice this →" hand-off, so the two
/// contracts are pinned side by side.
@Suite("Launcher: the open-a-surface notification", .tags(.acceptance))
struct LauncherOpenSurfaceTests {

    /// Cross-thread capture box for the notification observer closure.
    private final class ReceivedBox: @unchecked Sendable {
        var verbs: [String] = []
    }

    @Test("the notification name is the shell-facing contract string")
    func notificationNameContract() {
        #expect(OverlayController.openSurfaceNotification.rawValue == "vimkin.openSurface")
        // …and is NOT the practice channel: two hand-offs, two names.
        #expect(
            OverlayController.openSurfaceNotification
                != OverlayController.practiceCommandNotification
        )
    }

    @Test("requesting a surface posts its hub verb")
    @MainActor
    func requestPostsTheVerb() {
        let controller = OverlayController(database: CommandDatabase(commands: []))
        let received = ReceivedBox()

        let token = NotificationCenter.default.addObserver(
            forName: OverlayController.openSurfaceNotification,
            object: nil,
            queue: nil
        ) { note in
            if let verb = note.object as? String { received.verbs.append(verb) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        for destination in LauncherKeys.destinations {
            controller.requestSurface(verb: destination.verb)
        }

        #expect(received.verbs == LauncherKeys.destinations.map(\.verb))
    }
}
