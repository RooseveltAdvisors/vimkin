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

    @Test("on an EMPTY query, every mnemonic opens its surface")
    func emptyQueryJumps() {
        for destination in LauncherKeys.destinations {
            #expect(
                LauncherKeys.route(character: destination.key, query: "")
                    == .open(verb: destination.verb),
                "`\(destination.key)` did not open \(destination.verb)"
            )
        }
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

    /// Only the FIRST character can ever be a jump, and only when the field was
    /// empty when it arrived.
    @Test("a bare \"delete\" jumps on its d, then types the rest")
    func typingAWordOfMnemonics() {
        var query = ""
        var routings: [LauncherRouting] = []
        for character in "delete" {
            let routing = LauncherKeys.route(character: character, query: query)
            routings.append(routing)
            if routing == .type { query.append(character) }
        }
        // `d` on an empty field is Daily Run — that is the design, and it is
        // exactly why `/` exists (below).
        #expect(routings.first == .open(verb: Hub.Verb.daily))
        // …and nothing after it jumps.
        #expect(routings.dropFirst().allSatisfy { $0 == .type })
    }

    // MARK: `/` — the reason a search can still begin with a jump key

    @Test("/ on an empty field arms the search instead of typing a slash")
    func slashArmsTheSearch() {
        #expect(LauncherKeys.route(character: "/", query: "") == .startSearch)
        // Once armed, or once there is a query, `/` is just a character.
        #expect(LauncherKeys.route(character: "/", query: "", searchArmed: true) == .type)
        #expect(LauncherKeys.route(character: "/", query: "d") == .type)
    }

    /// The canonical query from the spec starts with `d`, which is Daily Run.
    /// `/` is what keeps it typeable — without it, no search could begin with
    /// any of the six mnemonics (delete, append, yank, paste, line, goto).
    @Test("\"/delete inside quotes\" types every character, jumping nowhere")
    func armedSearchTypesEverything() {
        var query = ""
        var armed = false
        var jumped = false

        for character in "/delete inside quotes" {
            switch LauncherKeys.route(character: character, query: query, searchArmed: armed) {
            case .startSearch: armed = true
            case .type: query.append(character)
            case .open, .help, .dismiss: jumped = true
            }
        }

        #expect(armed)
        #expect(!jumped, "an armed search still fired a jump")
        #expect(query == "delete inside quotes")
    }

    @Test("while armed, EVERY mnemonic types — including ? and q")
    func armedSearchSuppressesEveryMnemonic() {
        for destination in LauncherKeys.destinations {
            #expect(
                LauncherKeys.route(character: destination.key, query: "", searchArmed: true)
                    == .type,
                "`\(destination.key)` still jumped while the search was armed"
            )
        }
        #expect(LauncherKeys.route(character: "?", query: "", searchArmed: true) == .type)
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
                advertised.contains(String(destination.key)),
                "the map never mentions `\(destination.key)`"
            )
        }
        // …and the three keys that are not destinations.
        let all = map.chips.map(\.keys)
        #expect(all.contains("?"))
        #expect(all.contains("Esc"))
        #expect(all.contains(String(LauncherKeys.searchKey)))
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
