import SwiftUI
import Testing
@testable import Vimkin

/// Tests for the keyboard shell (U15) — the pure half of it: the per-surface
/// binding tables, the navigation-vs-engine mode arbitration, and the list
/// cursor. No SwiftUI focus is simulated (that is verified by driving the real
/// app with synthetic key events).
///
/// The load-bearing property, asserted from several angles below: **while a
/// practice surface is capturing, no menu binding can reach the chrome.**

// MARK: - Fixtures

/// Every surface, paired with the mode it runs in, so a test can sweep them all.
private let allSurfaces: [(name: String, map: KeyMap, mode: InputMode)] = [
    ("hub", SurfaceKeys.hub, .navigation),
    ("worldMap", SurfaceKeys.worldMap, .navigation),
    ("gameIntro", SurfaceKeys.gameIntro, .navigation),
    ("gamePlaying", SurfaceKeys.gamePlaying, .engine),
    ("gameWin", SurfaceKeys.gameWin, .navigation),
    ("lessonPath", SurfaceKeys.lessonPath, .navigation),
    ("lessonConcept", SurfaceKeys.lessonConcept, .navigation),
    ("lessonPractice", SurfaceKeys.lessonPractice, .engine),
    ("lessonComplete", SurfaceKeys.lessonComplete, .navigation),
    ("dojoIdle", SurfaceKeys.dojoIdle, .navigation),
    ("dojoDrilling", SurfaceKeys.dojoDrilling, .engine),
    ("dojoSummary", SurfaceKeys.dojoSummary, .navigation),
    ("arcadeIdle", SurfaceKeys.arcadeIdle, .navigation),
    ("arcadeRunning", SurfaceKeys.arcadeRunning, .engine),
    ("arcadeResult", SurfaceKeys.arcadeResult, .navigation),
    ("mastery", SurfaceKeys.mastery, .navigation),
    ("playground", SurfaceKeys.playground, .engine),
]

private var navigationSurfaces: [(name: String, map: KeyMap, mode: InputMode)] {
    allSurfaces.filter { $0.mode == .navigation }
}

private var engineSurfaces: [(name: String, map: KeyMap, mode: InputMode)] {
    allSurfaces.filter { $0.mode == .engine }
}

private func route(
    _ keys: [KeyInput],
    mode: InputMode,
    map: KeyMap,
    router: inout KeyRouterState
) -> [KeyRouting] {
    keys.map { router.route($0, mode: mode, map: map) }
}

// MARK: - Binding tables

@Suite("Keyboard: per-surface binding tables", .tags(.acceptance))
struct SurfaceKeyMapTests {

    @Test("the hub jumps straight to each of its six destinations")
    func hubMnemonics() {
        let map = SurfaceKeys.hub
        #expect(map.action(for: .char("a")) == .verb(Hub.Verb.adventure))
        #expect(map.action(for: .char("d")) == .verb(Hub.Verb.daily))
        #expect(map.action(for: .char("l")) == .verb(Hub.Verb.lessons))
        #expect(map.action(for: .char("p")) == .verb(Hub.Verb.practice))
        #expect(map.action(for: .char("g")) == .verb(Hub.Verb.progress))
        #expect(map.action(for: .char("y")) == .verb(Hub.Verb.playground))
    }

    @Test("every hub mnemonic actually opens something in the shell")
    func hubMnemonicsMatchTheCards() {
        let entries = Hub.entries(HubStatus())
        var verbs = Set(entries.map(\.verb))
        verbs.insert(Hub.Verb.quit)  // `q` is a verb with no card
        for (key, action) in SurfaceKeys.hub.bindings {
            guard case .verb(let verb) = action else { continue }
            #expect(verbs.contains(verb), "\(key) maps to unknown verb \(verb)")
        }
        // …and every card on the hub is reachable by exactly one key, which is
        // the key the card itself prints.
        for entry in entries {
            let keys = SurfaceKeys.hub.bindings.filter { $0.value == .verb(entry.verb) }
            #expect(keys.count == 1, "\(entry.verb) has \(keys.count) keys")
            #expect(keys.first?.key == .char(entry.key), "\(entry.verb) advertises the wrong key")
        }
    }

    /// `docs/keymap.md` rule 4: `hjkl` moves EVERYWHERE in navigation. On a
    /// one-column list `ListCursor` steps `h`/`l` by a single item, so the same
    /// four keys work on a grid and a list alike — one motion vocabulary, not
    /// two. (The hub is the exception and stays a mnemonic surface: `l` there
    /// is Lessons, the same letter the launcher uses.)
    @Test("every navigation list moves with h j k l and jumps with gg / G")
    func listMotions() {
        for surface in allSurfaces where surface.map.hasListJumps {
            #expect(surface.map.action(for: .char("h")) == .moveLeft, "\(surface.name)")
            #expect(surface.map.action(for: .char("j")) == .moveDown, "\(surface.name)")
            #expect(surface.map.action(for: .char("k")) == .moveUp, "\(surface.name)")
            #expect(surface.map.action(for: .char("l")) == .moveRight, "\(surface.name)")
            #expect(surface.map.action(for: .char("G")) == .last, "\(surface.name)")
            #expect(surface.map.action(for: .enter) == .activate, "\(surface.name)")
        }
    }

    @Test("the hub is mnemonic, not a list: l is Lessons, not a motion")
    func hubIsNotAList() {
        #expect(SurfaceKeys.hub.action(for: .char("l")) == .verb(Hub.Verb.lessons))
        #expect(SurfaceKeys.hub.action(for: .char("h")) == nil)
        #expect(SurfaceKeys.hub.hasListJumps == false)
    }

    @Test("every navigation surface answers Esc, q and ?")
    func everyNavigationSurfaceCanBeLeft() {
        // The hub is the root — see the carve-out at the end.
        for surface in navigationSurfaces where surface.name != "hub" {
            #expect(surface.map.action(for: .escape) != nil, "\(surface.name) has no Esc")
            #expect(surface.map.action(for: .char("?")) == .help, "\(surface.name) has no ?")
            // `q` and Esc must agree, or "back" means two things on one screen.
            #expect(
                surface.map.action(for: .char("q")) == surface.map.action(for: .escape),
                "\(surface.name): q and Esc disagree"
            )
        }
        // The hub is the root: there is nowhere above it to go back to, so
        // `q` there means QUIT THE APP rather than "one level back".
        #expect(SurfaceKeys.hub.action(for: .escape) == nil)
        #expect(SurfaceKeys.hub.action(for: .char("q")) == .verb(Hub.Verb.quit))
    }

    @Test("every capturing surface can still be left and helped, on ⌘")
    func everyEngineSurfaceHasCommandEscapes() {
        for surface in engineSurfaces {
            #expect(surface.map.commandAction(for: "l") == .back, "\(surface.name)")
            #expect(surface.map.commandAction(for: "/") == .help, "\(surface.name)")
            // …and NOT on plain keys, which belong to the engine.
            #expect(surface.map.bindings.isEmpty, "\(surface.name) binds plain keys")
        }
    }

    @Test("⌘ bindings ignore case, so ⌘⇧K still means ⌘K")
    func commandBindingsAreCaseInsensitive() {
        #expect(SurfaceKeys.lessonPractice.commandAction(for: "K") == .verb("showKeys"))
        #expect(SurfaceKeys.dojoDrilling.commandAction(for: "R") == .verb("reset"))
        #expect(SurfaceKeys.dojoDrilling.commandAction(for: "E") == .verb("finish"))
    }

    @Test("`g` is never a mnemonic on a surface where gg is a chord")
    func gIsReservedOnListSurfaces() {
        for surface in allSurfaces where surface.map.hasListJumps {
            #expect(
                surface.map.action(for: .char("g")) == nil,
                "\(surface.name) binds g, which would shadow gg"
            )
        }
    }

    @Test("every surface advertises itself: a title and at least one bar chip")
    func everySurfaceIsDiscoverable() {
        for surface in allSurfaces {
            #expect(!surface.map.title.isEmpty, "\(surface.name)")
            #expect(!surface.map.barChips.isEmpty, "\(surface.name) has an empty hint bar")
        }
    }

    /// `?` is a which-key popup, not a flat dump: every chip declares a band,
    /// and the bands partition the chips exactly once.
    @Test("every surface's ? map is grouped, and the groups lose nothing")
    func everyMapIsGrouped() {
        for surface in allSurfaces + [("launcher", SurfaceKeys.launcher, InputMode.navigation)] {
            let groups = surface.map.groupedChips
            #expect(!groups.isEmpty, "\(surface.name) has no groups")
            #expect(groups.allSatisfy { !$0.name.isEmpty }, "\(surface.name) has an unnamed group")
            #expect(
                Set(groups.map(\.name)).count == groups.count,
                "\(surface.name) repeats a group heading"
            )
            #expect(
                groups.flatMap(\.chips) == surface.map.chips,
                "\(surface.name): grouping dropped or reordered a chip"
            )
        }
    }

    /// `docs/keymap.md`'s ⌘ table. A chrome verb may not mean two different
    /// things on two screens, or the namespace stops being a namespace.
    @Test("the ⌘ chrome verbs mean the same thing on every capturing surface")
    func commandVerbsAreConsistent() {
        // ⌘R resets the page wherever a page can be reset.
        #expect(SurfaceKeys.gamePlaying.commandAction(for: "r") == .verb("replay"))
        #expect(SurfaceKeys.dojoDrilling.commandAction(for: "r") == .verb("reset"))
        // ⌘J skips, ⌘E ends.
        #expect(SurfaceKeys.dojoDrilling.commandAction(for: "j") == .verb("skip"))
        #expect(SurfaceKeys.arcadeRunning.commandAction(for: "j") == .verb("skip"))
        #expect(SurfaceKeys.dojoDrilling.commandAction(for: "e") == .verb("finish"))
        #expect(SurfaceKeys.arcadeRunning.commandAction(for: "e") == .verb("end"))
        // ⌘K shows the keys — and is claimed by NOTHING else.
        #expect(SurfaceKeys.lessonPractice.commandAction(for: "k") == .verb("showKeys"))
        for surface in engineSurfaces where surface.name != "lessonPractice" {
            #expect(
                surface.map.commandAction(for: "k") == nil,
                "\(surface.name) squats on ⌘K, which means \"show me the keys\""
            )
        }
        // The playground's document walk lives on the bracket pair instead.
        #expect(SurfaceKeys.playground.commandAction(for: "]") == .verb("nextDoc"))
        #expect(SurfaceKeys.playground.commandAction(for: "[") == .verb("prevDoc"))
        #expect(SurfaceKeys.playground.commandAction(for: "j") == nil)
    }
}

// MARK: - Mode arbitration

@Suite("Keyboard: navigation vs engine mode arbitration", .tags(.acceptance))
struct KeyRouterArbitrationTests {

    @Test("in navigation mode a bound key becomes its action")
    func navigationResolves() {
        var router = KeyRouterState()
        #expect(
            router.route(.char("j"), mode: .navigation, map: SurfaceKeys.lessonPath)
                == .navigate(.moveDown)
        )
        #expect(
            router.route(.enter, mode: .navigation, map: SurfaceKeys.lessonPath)
                == .navigate(.activate)
        )
    }

    @Test("in navigation mode an unbound key is ignored, never passed to the engine")
    func navigationSwallowsUnbound() {
        var router = KeyRouterState()
        #expect(
            router.route(.char("z"), mode: .navigation, map: SurfaceKeys.lessonPath) == .ignored
        )
    }

    // THE crux test: while practising, `j` moves the cursor, not the menu.
    @Test("in engine mode EVERY ordinary key goes to the engine")
    func engineOwnsOrdinaryKeys() {
        var router = KeyRouterState()
        for key in ["j", "k", "h", "l", "g", "G", "q", "?", "s", "d", "a", "m", "y", "p", "n", "r"] {
            let routing = router.route(
                .char(Character(key)), mode: .engine, map: SurfaceKeys.gamePlaying
            )
            #expect(routing == .engine, "engine mode leaked on `\(key)`")
        }
        #expect(router.route(.enter, mode: .engine, map: SurfaceKeys.gamePlaying) == .engine)
    }

    /// The generalised form: sweep EVERY key bound on ANY navigation surface
    /// through EVERY capturing surface. Not one may become a navigation action.
    @Test("no navigation binding can leak into any capturing surface")
    func noNavigationBindingLeaksWhileCapturing() {
        let everyNavigationKey = Set(navigationSurfaces.flatMap { $0.map.bindings.keys })
        #expect(everyNavigationKey.count > 10)  // guard against an empty sweep

        for surface in engineSurfaces {
            for key in everyNavigationKey where key != .escape {
                var router = KeyRouterState()
                let routing = router.route(key, mode: .engine, map: surface.map)
                #expect(routing == .engine, "\(surface.name) leaked on \(key)")
            }
        }
    }

    @Test("a single Esc belongs to the engine — it is Vim's own mode key")
    func firstEscapeGoesToTheEngine() {
        var router = KeyRouterState()
        #expect(router.route(.escape, mode: .engine, map: SurfaceKeys.gamePlaying) == .engine)
    }

    @Test("a SECOND consecutive Esc leaves the surface")
    func doubleEscapeLeaves() {
        var router = KeyRouterState()
        let routings = route(
            [.escape, .escape], mode: .engine, map: SurfaceKeys.gamePlaying, router: &router
        )
        #expect(routings == [.engine, .navigate(.back)])
    }

    @Test("any key between the two Escs disarms the chord")
    func escapeChordNeedsToBeConsecutive() {
        var router = KeyRouterState()
        let routings = route(
            [.escape, .char("j"), .escape], mode: .engine,
            map: SurfaceKeys.gamePlaying, router: &router
        )
        #expect(routings == [.engine, .engine, .engine])
        // …and the third Esc has re-armed it, so a fourth leaves.
        #expect(router.route(.escape, mode: .engine, map: SurfaceKeys.gamePlaying)
            == .navigate(.back))
    }

    @Test("three Escs leave exactly once, not twice")
    func escapeChordDoesNotDoubleFire() {
        var router = KeyRouterState()
        let routings = route(
            [.escape, .escape, .escape], mode: .engine,
            map: SurfaceKeys.gamePlaying, router: &router
        )
        #expect(routings == [.engine, .navigate(.back), .engine])
    }

    @Test("the Esc chord does not survive a switch back to navigation mode")
    func modeSwitchDisarmsTheChord() {
        var router = KeyRouterState()
        #expect(router.route(.escape, mode: .engine, map: SurfaceKeys.gamePlaying) == .engine)
        // Phase changed (the level was cleared): Esc now means back, once.
        #expect(
            router.route(.escape, mode: .navigation, map: SurfaceKeys.gameWin)
                == .navigate(.verb("worldmap"))
        )
        #expect(!router.escapePrimed)
    }
}

// MARK: - Chords

@Suite("Keyboard: the gg chord", .tags(.acceptance))
struct KeyChordTests {

    @Test("gg jumps to the first item")
    func ggJumpsFirst() {
        var router = KeyRouterState()
        let routings = route(
            [.char("g"), .char("g")], mode: .navigation,
            map: SurfaceKeys.lessonPath, router: &router
        )
        #expect(routings == [.pending, .navigate(.first)])
    }

    @Test("g followed by anything else cancels, and that key still counts")
    func gCancelsIntoTheNextKey() {
        var router = KeyRouterState()
        let routings = route(
            [.char("g"), .char("j")], mode: .navigation,
            map: SurfaceKeys.lessonPath, router: &router
        )
        #expect(routings == [.pending, .navigate(.moveDown)])
        #expect(!router.pendingG)
    }

    @Test("on a surface with no list, g is not a chord")
    func gIsNotAChordWithoutAList() {
        var router = KeyRouterState()
        #expect(!SurfaceKeys.dojoIdle.hasListJumps)
        #expect(router.route(.char("g"), mode: .navigation, map: SurfaceKeys.dojoIdle) == .ignored)
    }

    @Test("a half-typed gg never survives into engine mode")
    func pendingChordIsDroppedWhenTheEngineTakesOver() {
        var router = KeyRouterState()
        #expect(router.route(.char("g"), mode: .navigation, map: SurfaceKeys.lessonPath) == .pending)
        #expect(router.route(.char("g"), mode: .engine, map: SurfaceKeys.gamePlaying) == .engine)
        #expect(!router.pendingG)
    }

    @Test("on the hub `g` is a destination, not the first half of a chord")
    func hubTradesTheChordForTheMnemonic() {
        // The hub is the one surface that spends `g` on a jump key (Progress).
        // It pays for that by opting out of `gg`, and the invariant test
        // `gIsReservedOnListSurfaces` is what keeps the two facts consistent.
        var router = KeyRouterState()
        #expect(!SurfaceKeys.hub.hasListJumps)
        #expect(
            router.route(.char("g"), mode: .navigation, map: SurfaceKeys.hub)
                == .navigate(.verb(Hub.Verb.progress))
        )
        #expect(!router.pendingG, "the hub must not leave a chord half-open")
    }

    @Test("every LIST surface still carries gg, so the chord is never unlearned")
    func listSurfacesKeepTheChord() {
        for surface in allSurfaces where surface.map.hasListJumps {
            var router = KeyRouterState()
            #expect(
                router.route(.char("g"), mode: .navigation, map: surface.map) == .pending,
                "\(surface.name)"
            )
            #expect(
                router.route(.char("g"), mode: .navigation, map: surface.map)
                    == .navigate(.first),
                "\(surface.name)"
            )
        }
    }
}

// MARK: - Selection

@Suite("Keyboard: list and grid selection", .tags(.unit))
struct ListCursorTests {

    @Test("j and k move one row and clamp at both ends")
    func listMovementClamps() {
        var cursor = ListCursor(count: 3)
        #expect(cursor.index == 0)
        let movedAtTop = cursor.apply(.moveUp)  // already at the top
        #expect(movedAtTop)                     // a movement action, just clamped
        #expect(cursor.index == 0)
        _ = cursor.apply(.moveDown)
        _ = cursor.apply(.moveDown)
        #expect(cursor.index == 2)
        _ = cursor.apply(.moveDown)             // already at the bottom
        #expect(cursor.index == 2)
        _ = cursor.apply(.moveUp)
        #expect(cursor.index == 1)
    }

    @Test("gg and G go to the ends")
    func jumps() {
        var cursor = ListCursor(count: 10, index: 4)
        _ = cursor.apply(.last)
        #expect(cursor.index == 9)
        _ = cursor.apply(.first)
        #expect(cursor.index == 0)
    }

    @Test("on a grid, j/k move a whole row and h/l move one card")
    func gridMovement() {
        var cursor = ListCursor(count: 10, columns: 3)
        _ = cursor.apply(.moveDown)
        #expect(cursor.index == 3)
        _ = cursor.apply(.moveRight)
        #expect(cursor.index == 4)
        _ = cursor.apply(.moveUp)
        #expect(cursor.index == 1)
        _ = cursor.apply(.moveLeft)
        #expect(cursor.index == 0)
        _ = cursor.apply(.moveLeft)             // clamps, never wraps
        #expect(cursor.index == 0)
    }

    @Test("a partial last row still clamps to the final card")
    func gridPartialLastRow() {
        var cursor = ListCursor(count: 10, columns: 3, index: 8)
        _ = cursor.apply(.moveDown)             // 8 + 3 = 11, past the end
        #expect(cursor.index == 9)
    }

    @Test("an empty list is inert, never negative")
    func emptyList() {
        var cursor = ListCursor(count: 0)
        #expect(cursor.index == 0)
        _ = cursor.apply(.moveDown)
        _ = cursor.apply(.last)
        _ = cursor.apply(.moveUp)
        #expect(cursor.index == 0)
    }

    @Test("a shrinking list pulls the selection back in range")
    func setCountReclamps() {
        var cursor = ListCursor(count: 10, index: 9)
        cursor.setCount(4)
        #expect(cursor.index == 3)
        cursor.setCount(0)
        #expect(cursor.index == 0)
    }

    @Test("apply() only consumes movements, so activate and back fall through")
    func nonMovementsAreNotConsumed() {
        var cursor = ListCursor(count: 5)
        let consumed = [
            cursor.apply(.activate),
            cursor.apply(.back),
            cursor.apply(.help),
            cursor.apply(.verb("start")),
        ]
        #expect(consumed == [false, false, false, false])
        #expect(cursor.index == 0)
    }

    @Test("selecting out of range clamps instead of crashing")
    func selectClamps() {
        var cursor = ListCursor(count: 3)
        cursor.select(99)
        #expect(cursor.index == 2)
        cursor.select(-4)
        #expect(cursor.index == 0)
    }

    @Test("the world map's cursor and its grid agree on the column count")
    func worldMapColumnsMatchTheView() {
        let cursor = ListCursor(count: 10, columns: AdventureView.columns)
        #expect(cursor.columns == 3)
    }
}

// MARK: - The surface model

@Suite("Keyboard: the surface model runs actions and blocks the engine", .tags(.acceptance))
@MainActor
struct KeyboardSurfaceModelTests {

    @Test("a navigation key runs its action and is kept from the engine")
    func navigationKeyIsBlocked() {
        let model = KeyboardSurfaceModel()
        var seen: [NavAction] = []
        let filter = model.engineFilter(
            mode: { .navigation },
            map: { SurfaceKeys.dojoIdle },
            base: { _ in .allow },
            onAction: { seen.append($0) }
        )
        let decision = filter(.char("s"))
        #expect(seen == [.verb("start")])
        if case .block(let reason) = decision {
            #expect(KeyboardSurfaceModel.isChromeBlock(reason))
        } else {
            Issue.record("a navigation key reached the engine")
        }
    }

    @Test("in engine mode the surface's own filter decides, untouched")
    func engineKeyFallsThroughToTheBaseFilter() {
        let model = KeyboardSurfaceModel()
        var seen: [NavAction] = []
        let filter = model.engineFilter(
            mode: { .engine },
            map: { SurfaceKeys.gamePlaying },
            base: { $0 == .char("x") ? .block(reason: "not yet learned") : .allow },
            onAction: { seen.append($0) }
        )
        #expect(filter(.char("j")) == .allow)
        #expect(filter(.char("x")) == .block(reason: "not yet learned"))
        #expect(seen.isEmpty)
        // …and a lock-filter block is NOT mistaken for a chrome block, so the
        // game still shimmers for a locked command.
        #expect(!KeyboardSurfaceModel.isChromeBlock("not yet learned"))
    }

    @Test("Esc Esc while capturing runs back without the engine seeing it")
    func doubleEscapeLeavesThroughTheFilter() {
        let model = KeyboardSurfaceModel()
        var seen: [NavAction] = []
        var delivered: [KeyInput] = []
        let filter = model.engineFilter(
            mode: { .engine },
            map: { SurfaceKeys.dojoDrilling },
            base: { key in delivered.append(key); return .allow },
            onAction: { seen.append($0) }
        )
        #expect(filter(.escape) == .allow)      // the engine gets the first one
        _ = filter(.escape)                     // the chrome takes the second
        #expect(seen == [.back])
        #expect(delivered == [.escape])
    }

    @Test("? opens help instead of firing an action, and any key can close it")
    func helpIsModal() {
        let model = KeyboardSurfaceModel()
        var seen: [NavAction] = []
        let filter = model.engineFilter(
            mode: { .navigation },
            map: { SurfaceKeys.lessonPath },
            onAction: { seen.append($0) }
        )
        _ = filter(.char("?"))
        #expect(model.showHelp)
        #expect(seen.isEmpty, "help must not fall through as an action")

        // While it is up, nothing else runs.
        _ = filter(.char("j"))
        #expect(seen.isEmpty)
        #expect(model.showHelp)

        _ = filter(.escape)
        #expect(!model.showHelp)
        _ = filter(.char("j"))
        #expect(seen == [.moveDown])
    }
}
