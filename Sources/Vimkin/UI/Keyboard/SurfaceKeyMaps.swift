// SurfaceKeyMaps.swift — the binding table for every surface in the app (U15).
//
// One file so the whole keyboard vocabulary can be read (and reviewed for
// collisions) in one sitting. The conventions it implements are written down in
// `docs/keymap.md`, derived from Jon's own tmux (`C-a` prefix, then ONE mnemonic
// key per action) and neovim (leader + which-key groups, with a popup that SHOWS
// the continuations). Four house rules hold across the app:
//
//   • `Esc` and `q` always mean "one level back"; `?` always opens help.
//   • `h j k l` moves, `gg`/`G` jumps to the ends, `⏎` opens — on every
//     navigation surface, list or grid. (`ListCursor` clamps, so `h`/`l` on a
//     one-column list simply steps one item.)
//   • A surface that is CAPTURING for the VimEngine gets a map whose bindings
//     are empty. It still carries chips, because the player still needs to be
//     told how to get out (`Esc Esc`) and what the ⌘-shortcuts are — ⌘ combos
//     are structurally invisible to the engine (`KeyCaptureView.translate`
//     drops them), which is exactly why chrome verbs live there while a
//     practice surface is running.
//   • Every chip names a which-key GROUP, so `?` can band the map instead of
//     dumping it. See `KeyChip.group`.

import Foundation

public enum SurfaceKeys {

    // MARK: - Which-key group names

    /// The four bands every surface's `?` map is drawn in. Named once so a new
    /// surface cannot invent a fifth spelling of "Leave".
    public enum Group {
        public static let move = "Move"
        public static let go = "Go"
        public static let leave = "Leave"
        public static let keys = "Keys"
        public static let practising = "While practising"
        public static let search = "Search"
    }

    // MARK: - Shared pieces

    /// `Esc` + `q` → back, and `?` → help. Every surface gets these.
    private static func common(back: NavAction = .back) -> [KeyInput: NavAction] {
        [.escape: back, .char("q"): back, .char("?"): .help]
    }

    /// `h j k l` and `G`. The `gg` half is a chord, resolved by
    /// `KeyRouterState`. On a one-column list `h`/`l` step a single item, which
    /// is what `ListCursor` does with `columns == 1` — so the same four keys
    /// move on every navigation surface, exactly as `docs/keymap.md` says.
    private static func listMotions() -> [KeyInput: NavAction] {
        [
            .char("j"): .moveDown,
            .char("k"): .moveUp,
            .char("l"): .moveRight,
            .char("h"): .moveLeft,
            .char("G"): .last,
            .enter: .activate,
        ]
    }

    private static let listChips: [KeyChip] = [
        KeyChip("h j k l", "move", group: Group.move),
        KeyChip("gg G", "first / last", inBar: false, group: Group.move),
        KeyChip("⏎", "open", group: Group.go),
    ]

    private static let backChips: [KeyChip] = [
        KeyChip("Esc q", "back", group: Group.leave),
        KeyChip("?", "keys", group: Group.keys),
    ]

    /// Chips shared by every capturing surface.
    private static let engineChips: [KeyChip] = [
        KeyChip("Esc Esc", "leave", group: Group.leave),
        KeyChip("⌘L", "leave", inBar: false, group: Group.leave),
        KeyChip("⌘/", "keys", group: Group.keys),
    ]

    /// A capturing surface: no plain-key bindings at all, so nothing can be
    /// stolen from the engine. `KeyRouterState` enforces this independently.
    /// Chrome verbs ride on ⌘, which the engine never sees.
    private static func engine(
        _ title: String,
        commands: [Character: NavAction] = [:],
        _ chips: [KeyChip]
    ) -> KeyMap {
        KeyMap(
            title: title,
            bindings: [:],
            commandBindings: commands.merging(["l": .back]) { existing, _ in existing },
            chips: chips + engineChips
        )
    }

    private static func merge(_ parts: [KeyInput: NavAction]...) -> [KeyInput: NavAction] {
        parts.reduce(into: [:]) { out, part in out.merge(part) { _, new in new } }
    }

    // MARK: - Hub (the home screen)

    /// The hub deliberately does NOT enable the `gg` chord, and that is a real
    /// design trade rather than an oversight: the home screen binds `g` to
    /// Progress, and a key cannot be both a mnemonic and a chord opener. Six
    /// entries, each one keystroke away, is worth more here than "jump to
    /// first" — and every LIST in the app (world map, lesson path, progress)
    /// still carries `gg`/`G`, so the chord is never unlearned. The invariant
    /// is enforced by a test: no surface may bind `g` while `hasListJumps`.
    ///
    /// The hub is a MNEMONIC surface, not a list, so `h`/`l` are not movement
    /// here either — `l` is Lessons, the same letter the launcher uses.
    public static let hub = KeyMap(
        title: "Vimkin",
        bindings: merge(
            [
                .char("j"): .moveDown,
                .char("k"): .moveUp,
                .enter: .activate,
                .char("?"): .help,
                .char("q"): .verb(Hub.Verb.quit),
            ],
            // The jump keys come from `Hub` itself, so the menu and the binding
            // table are the SAME list — a card can never advertise a key the
            // keyboard does not answer to.
            Dictionary(
                uniqueKeysWithValues: Hub.entries(HubStatus()).map {
                    (KeyInput.char($0.key), NavAction.verb($0.verb))
                }
            )
        ),
        chips: [
            KeyChip("j k", "move", group: Group.move),
            KeyChip("⏎", "open", group: Group.go),
            KeyChip("a d l p g y", "jump straight there", inBar: false, group: Group.go),
            KeyChip("?", "keys", group: Group.keys),
            KeyChip("⌘⇧Space", "launcher", group: Group.keys),
            KeyChip("q", "quit", group: Group.leave),
        ]
    )

    // MARK: - Launcher (the front door, summoned by ⌘⇧Space)

    /// The launcher's own map, shown by `?` inside the panel.
    ///
    /// `bindings` stays empty on purpose: the launcher has a search field, so
    /// its precedence rule ("typing searches; `:` addresses the program") is
    /// not a `KeyMap` lookup — it lives in `LauncherKeys.route`, which is also
    /// where these chips come from. One table, two readers.
    public static let launcher = KeyMap(
        title: "Launcher",
        bindings: [:],
        chips: [
            // The search field's own placeholder already says "type", so the
            // chip is map-only — the bar is 640pt wide and a truncated
            // key-cap label is worse than no label.
            KeyChip(
                "type", "search in plain English",
                inBar: false, group: Group.search
            ),

            KeyChip("⏎", "practise the match", group: Group.search, barLabel: "practise"),
            KeyChip("⌃N ⌃P", "move through matches", group: Group.search, barLabel: "move"),
            KeyChip("↑ ↓", "move through matches", inBar: false, group: Group.search),
        ]
            + [
                // Vim's own way to address the program. Typing is a search, so
                // a destination costs one extra key rather than costing every
                // search that begins with a mnemonic letter.
                KeyChip(":", "go to a surface", group: Group.go, barLabel: "go"),
            ]
            + LauncherKeys.destinations.map {
                KeyChip(":\(String($0.key))", $0.title, inBar: false, group: Group.go)
            }
            + [
                KeyChip("?", "this map", group: Group.keys),
                KeyChip("Esc", "dismiss", group: Group.leave),
            ]
    )

    // MARK: - Adventure

    public static let worldMap = KeyMap(
        title: "World map",
        bindings: merge(listMotions(), common()),
        chips: [
            KeyChip("h j k l", "move", group: Group.move),
            KeyChip("gg G", "first / last", inBar: false, group: Group.move),
            KeyChip("⏎", "enter level", group: Group.go),
        ] + backChips,
        hasListJumps: true
    )

    public static let gameIntro = KeyMap(
        title: "Level briefing",
        bindings: merge(
            [.enter: .verb("begin"), .char("b"): .verb("begin")],
            common()
        ),
        chips: [KeyChip("⏎ b", "begin", group: Group.go)] + backChips
    )

    public static let gamePlaying = engine(
        "In the level",
        commands: ["r": .verb("replay")],
        [
            KeyChip("every key", "goes to the editor", group: Group.practising),
            KeyChip("⌘R", "reset the page", group: Group.practising),
        ]
    )

    public static let gameWin = KeyMap(
        title: "Level cleared",
        bindings: merge(
            [
                .char("r"): .verb("replay"),
                .char("n"): .verb("next"),
                .enter: .activate,
                .char("m"): .verb("worldmap"),
            ],
            common(back: .verb("worldmap"))
        ),
        chips: [
            KeyChip("⏎", "next level", group: Group.go),
            KeyChip("r", "replay", group: Group.go),
            KeyChip("m Esc", "world map", group: Group.leave),
            KeyChip("?", "keys", group: Group.keys),
        ]
    )

    // MARK: - Learn

    public static let lessonPath = KeyMap(
        title: "Learn",
        bindings: merge(listMotions(), common()),
        chips: listChips + backChips,
        hasListJumps: true
    )

    public static let lessonConcept = KeyMap(
        title: "Lesson",
        bindings: merge(
            [.enter: .verb("start"), .char("s"): .verb("start")],
            common()
        ),
        chips: [KeyChip("⏎ s", "start practising", group: Group.go)] + backChips
    )

    public static let lessonPractice = engine(
        "Practising",
        commands: ["k": .verb("showKeys")],
        [
            KeyChip("every key", "goes to the editor", group: Group.practising),
            KeyChip("⌘K", "show me the keys", group: Group.practising),
        ]
    )

    public static let lessonComplete = KeyMap(
        title: "Lesson learned",
        bindings: merge([.enter: .back], common()),
        chips: [
            KeyChip("⏎ Esc", "back to lessons", group: Group.leave),
            KeyChip("?", "keys", group: Group.keys),
        ]
    )

    // MARK: - Practice dojo

    public static let dojoIdle = KeyMap(
        title: "Practice Dojo",
        bindings: merge(
            [.enter: .verb("start"), .char("s"): .verb("start")],
            common()
        ),
        chips: [KeyChip("⏎ s", "start a set", group: Group.go)] + backChips
    )

    public static let dojoDrilling = engine(
        "Drilling",
        commands: ["r": .verb("reset"), "j": .verb("skip"), "e": .verb("finish")],
        [
            KeyChip("every key", "goes to the editor", group: Group.practising),
            KeyChip("⌘R", "reset the page", group: Group.practising),
            KeyChip("⌘J", "skip drill", group: Group.practising),
            KeyChip("⌘E", "end the set", group: Group.practising),
        ]
    )

    public static let dojoSummary = KeyMap(
        title: "Set complete",
        bindings: merge(
            [
                .enter: .verb("again"),
                .char("p"): .verb("again"),
                .char("d"): .verb("done"),
            ],
            common(back: .verb("done"))
        ),
        chips: [
            KeyChip("⏎ p", "practice again", group: Group.go),
            KeyChip("d Esc", "done", group: Group.leave),
            KeyChip("?", "keys", group: Group.keys),
        ]
    )

    // MARK: - Daily run

    public static let arcadeIdle = KeyMap(
        title: "Daily Run",
        bindings: merge(
            [
                .enter: .verb("start"),
                .char("s"): .verb("start"),
                .char("p"): .verb("practise"),
            ],
            common()
        ),
        chips: [
            KeyChip("⏎ s", "start the run", group: Group.go),
            KeyChip("p", "practise it", group: Group.go),
        ] + backChips
    )

    public static let arcadeRunning = engine(
        "Running",
        commands: ["j": .verb("skip"), "e": .verb("end")],
        [
            KeyChip("every key", "goes to the editor", group: Group.practising),
            KeyChip("⌘J", "skip drill", group: Group.practising),
            KeyChip("⌘E", "end the run", group: Group.practising),
        ]
    )

    public static let arcadeResult = KeyMap(
        title: "Run over",
        bindings: merge(
            [
                .enter: .activate,
                .char("s"): .verb("start"),
                .char("p"): .verb("practise"),
                .char("d"): .verb("done"),
            ],
            common(back: .verb("done"))
        ),
        chips: [
            KeyChip("⏎", "run again", group: Group.go),
            KeyChip("d Esc", "done", group: Group.leave),
            KeyChip("?", "keys", group: Group.keys),
        ]
    )

    // MARK: - Progress

    public static let mastery = KeyMap(
        title: "Progress",
        bindings: merge(listMotions(), common()),
        chips: [
            KeyChip("h j k l", "move", group: Group.move),
            KeyChip("gg G", "first / last", inBar: false, group: Group.move),
            KeyChip("⏎", "practise this", group: Group.go),
        ] + backChips,
        hasListJumps: true
    )

    // MARK: - Playground

    /// Document switching rides on `⌘[` / `⌘]` rather than `⌘J` / `⌘K`: those
    /// two mean "skip a drill" and "show me the keys" everywhere else in the
    /// app, and a chrome verb that means something different on one screen is
    /// exactly the collision `docs/keymap.md` exists to prevent. Brackets are
    /// the vim-native "previous / next thing" pair (`[b` / `]b`).
    public static let playground = engine(
        "Playground",
        commands: ["]": .verb("nextDoc"), "[": .verb("prevDoc")],
        [
            KeyChip("every key", "goes to the editor", group: Group.practising),
            KeyChip("⌘[ ⌘]", "previous / next document", group: Group.practising),
        ]
    )
}
