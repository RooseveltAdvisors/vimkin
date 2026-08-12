// SurfaceKeyMaps.swift — the binding table for every surface in the app (U15).
//
// One file so the whole keyboard vocabulary can be read (and reviewed for
// collisions) in one sitting. Two house rules hold across the app:
//
//   • `Esc` and `q` always mean "one level back"; `?` always opens help.
//   • A surface that is CAPTURING for the VimEngine gets a map whose bindings
//     are empty. It still carries chips, because the player still needs to be
//     told how to get out (`Esc Esc`) and what the ⌘-shortcuts are — ⌘ combos
//     are structurally invisible to the engine (`KeyCaptureView.translate`
//     drops them), which is exactly why chrome verbs live there while a
//     practice surface is running.

import Foundation

public enum SurfaceKeys {

    // MARK: - Shared pieces

    /// `Esc` + `q` → back, and `?` → help. Every surface gets these.
    private static func common(back: NavAction = .back) -> [KeyInput: NavAction] {
        [.escape: back, .char("q"): back, .char("?"): .help]
    }

    /// `j`/`k` (+ `↑`/`↓`-equivalents are handled by the arrow bindings below)
    /// and `G`. The `gg` half is a chord, resolved by `KeyRouterState`.
    private static func listMotions(columns: Bool = false) -> [KeyInput: NavAction] {
        var motions: [KeyInput: NavAction] = [
            .char("j"): .moveDown,
            .char("k"): .moveUp,
            .char("G"): .last,
            .enter: .activate,
        ]
        if columns {
            motions[.char("l")] = .moveRight
            motions[.char("h")] = .moveLeft
        }
        return motions
    }

    private static let listChips: [KeyChip] = [
        KeyChip("j k", "move"),
        KeyChip("gg G", "first / last", inBar: false),
        KeyChip("⏎", "open"),
    ]

    private static let backChips: [KeyChip] = [
        KeyChip("Esc q", "back"),
        KeyChip("?", "keys"),
    ]

    /// Chips shared by every capturing surface.
    private static let engineChips: [KeyChip] = [
        KeyChip("Esc Esc", "leave"),
        KeyChip("⌘L", "leave", inBar: false),
        KeyChip("⌘/", "keys"),
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
            KeyChip("j k", "move"),
            KeyChip("⏎", "open"),
            KeyChip("a d l p g y", "jump straight there", inBar: false),
            KeyChip("?", "keys"),
            KeyChip("⌘⇧V", "lookup"),
            KeyChip("q", "quit"),
        ]
    )

    // MARK: - Adventure

    public static let worldMap = KeyMap(
        title: "World map",
        bindings: merge(listMotions(columns: true), common()),
        chips: [
            KeyChip("h j k l", "move"),
            KeyChip("gg G", "first / last", inBar: false),
            KeyChip("⏎", "enter level"),
        ] + backChips,
        hasListJumps: true
    )

    public static let gameIntro = KeyMap(
        title: "Level briefing",
        bindings: merge(
            [.enter: .verb("begin"), .char("b"): .verb("begin")],
            common()
        ),
        chips: [KeyChip("⏎ b", "begin")] + backChips
    )

    public static let gamePlaying = engine(
        "In the level",
        [KeyChip("every key", "goes to the editor")]
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
            KeyChip("⏎", "next level"),
            KeyChip("r", "replay"),
            KeyChip("m Esc", "world map"),
            KeyChip("?", "keys"),
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
        chips: [KeyChip("⏎ s", "start practising")] + backChips
    )

    public static let lessonPractice = engine(
        "Practising",
        commands: ["k": .verb("showKeys")],
        [
            KeyChip("every key", "goes to the editor"),
            KeyChip("⌘K", "show me the keys"),
        ]
    )

    public static let lessonComplete = KeyMap(
        title: "Lesson learned",
        bindings: merge([.enter: .back], common()),
        chips: [KeyChip("⏎ Esc", "back to lessons"), KeyChip("?", "keys")]
    )

    // MARK: - Practice dojo

    public static let dojoIdle = KeyMap(
        title: "Practice Dojo",
        bindings: merge(
            [.enter: .verb("start"), .char("s"): .verb("start")],
            common()
        ),
        chips: [KeyChip("⏎ s", "start a set")] + backChips
    )

    public static let dojoDrilling = engine(
        "Drilling",
        commands: ["r": .verb("reset"), "j": .verb("skip"), "e": .verb("finish")],
        [
            KeyChip("every key", "goes to the editor"),
            KeyChip("⌘R", "reset document"),
            KeyChip("⌘J", "skip drill"),
            KeyChip("⌘E", "end the set"),
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
            KeyChip("⏎ p", "practice again"),
            KeyChip("d Esc", "done"),
            KeyChip("?", "keys"),
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
            KeyChip("⏎ s", "start the run"),
            KeyChip("p", "practise it"),
        ] + backChips
    )

    public static let arcadeRunning = engine(
        "Running",
        commands: ["j": .verb("skip"), "e": .verb("end")],
        [
            KeyChip("every key", "goes to the editor"),
            KeyChip("⌘J", "skip drill"),
            KeyChip("⌘E", "end the run"),
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
            KeyChip("⏎", "run again"),
            KeyChip("d Esc", "done"),
            KeyChip("?", "keys"),
        ]
    )

    // MARK: - Progress

    public static let mastery = KeyMap(
        title: "Progress",
        bindings: merge(listMotions(), common()),
        chips: [
            KeyChip("j k", "move"),
            KeyChip("gg G", "first / last", inBar: false),
            KeyChip("⏎", "practise this"),
        ] + backChips,
        hasListJumps: true
    )

    // MARK: - Playground

    public static let playground = engine(
        "Playground",
        commands: ["j": .verb("nextDoc"), "k": .verb("prevDoc")],
        [
            KeyChip("every key", "goes to the editor"),
            KeyChip("⌘J ⌘K", "next / previous document"),
        ]
    )

    // MARK: - Lookup overlay

    public static let lookup = KeyMap(
        title: "Lookup",
        bindings: [:],
        chips: [
            KeyChip("↑ ↓", "move"),
            KeyChip("⏎", "practise this"),
            KeyChip("Esc", "close"),
        ]
    )
}
