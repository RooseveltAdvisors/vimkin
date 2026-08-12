import Foundation
import Testing
@testable import Vimkin

// The pure logic under the U19 practice-feedback layer.
//
// What is tested here is the part that can be WRONG rather than merely ugly:
// where a ghost cursor claims a key would land, how a multi-key chord is
// displayed while it builds, and which effect tier a correct rep earns. The
// animation itself (easing, trails, squash, rings) is deliberately NOT unit
// tested — it is judged by eye, per `docs/release-checklist.md`.

private func engine(_ text: String, setup: String = "") -> VimEngine {
    var engine = VimEngine(text: text)
    if !setup.isEmpty { engine.feed(keys: setup) }
    return engine
}

private func doors(_ keys: [String]) -> [OutcomeDoor] {
    keys.map { OutcomeDoor(keys: $0, note: "note for \($0)") }
}

/// Ghost anchors keyed by the door that produced them.
private func anchors(_ keys: [String], in engine: VimEngine) -> [String: GhostAnchor] {
    let spec = OutcomePreviewSpec(doors: doors(keys))
    var result: [String: GhostAnchor] = [:]
    for ghost in OutcomePreview.ghosts(for: spec, engine: engine) {
        result[ghost.keys] = ghost.anchor
    }
    return result
}

private let insertDoors = ["i", "a", "I", "A", "o", "O"]

@Suite("Outcome preview: where each door actually lands", .tags(.unit))
struct OutcomePreviewGhostTests {

    @Test("the five doors into Insert land in five different places")
    func fiveDoorsAreFiveDifferentSpots() {
        // The lesson's own document, with the cursor parked on the indented line.
        let doc = "## Packing\n\n  sunscreen\n  passport"
        let landings = anchors(insertDoors, in: engine(doc, setup: "jj"))

        #expect(landings["i"] == .cell(Position(line: 2, col: 0)))
        #expect(landings["a"] == .cell(Position(line: 2, col: 1)))
        #expect(landings["I"] == .cell(Position(line: 2, col: 2)), "skips the indent")
        #expect(landings["A"] == .cell(Position(line: 2, col: 11)), "the end of the line")
        #expect(landings["o"] == .newLine(above: 3), "a fresh line below")
        #expect(landings["O"] == .newLine(above: 2), "a fresh line above")

        // The whole point of the preview: no two doors agree.
        #expect(Set(insertDoors.map { "\(landings[$0]!)" }).count == insertDoors.count)
    }

    @Test("an empty line collapses every horizontal door onto column zero")
    func emptyLine() {
        let landings = anchors(insertDoors, in: engine("abc\n\ndef", setup: "j"))

        for key in ["i", "a", "I", "A"] {
            #expect(landings[key] == .cell(Position(line: 1, col: 0)), "\(key) on an empty line")
        }
        #expect(landings["o"] == .newLine(above: 2))
        #expect(landings["O"] == .newLine(above: 1))
    }

    @Test("an all-whitespace line: I has no non-blank to find, A goes past the blanks")
    func allWhitespaceLine() {
        let landings = anchors(insertDoors, in: engine("    "))

        #expect(landings["i"] == .cell(Position(line: 0, col: 0)))
        #expect(landings["a"] == .cell(Position(line: 0, col: 1)))
        // There is no first non-blank character, so `I` stays at the line start.
        #expect(landings["I"] == .cell(Position(line: 0, col: 0)))
        #expect(landings["A"] == .cell(Position(line: 0, col: 4)))
    }

    @Test("with the cursor on the last character, a and A agree — and i and I do not")
    func cursorAtLineEnd() {
        let landings = anchors(insertDoors, in: engine("  hi", setup: "$"))

        #expect(landings["a"] == .cell(Position(line: 0, col: 4)))
        #expect(landings["A"] == .cell(Position(line: 0, col: 4)))
        #expect(landings["i"] == .cell(Position(line: 0, col: 3)))
        #expect(landings["I"] == .cell(Position(line: 0, col: 2)))
    }

    @Test("a single-character line")
    func singleCharacterLine() {
        let landings = anchors(insertDoors, in: engine("x"))

        #expect(landings["i"] == .cell(Position(line: 0, col: 0)))
        #expect(landings["a"] == .cell(Position(line: 0, col: 1)))
        #expect(landings["I"] == .cell(Position(line: 0, col: 0)))
        #expect(landings["A"] == .cell(Position(line: 0, col: 1)))
        #expect(landings["o"] == .newLine(above: 1))
        #expect(landings["O"] == .newLine(above: 0))
    }

    @Test("every Insert door is tinted as Insert; a motion door is not")
    func ghostsCarryTheModeTheyLeaveYouIn() {
        let spec = OutcomePreviewSpec(doors: doors(insertDoors))
        for ghost in OutcomePreview.ghosts(for: spec, engine: engine("hello")) {
            #expect(ghost.mode == .insert, "\(ghost.keys) should open Insert")
        }
        let motions = OutcomePreview.ghosts(
            for: OutcomePreviewSpec(doors: doors(["w", "$", "G"])),
            engine: engine("one two\nthree")
        )
        #expect(motions.allSatisfy { $0.mode == .normal })
        #expect(motions.map(\.anchor) == [
            .cell(Position(line: 0, col: 4)),
            .cell(Position(line: 0, col: 6)),
            .cell(Position(line: 1, col: 0)),
        ])
    }

    @Test("previewing never disturbs the engine it previews")
    func previewIsNonDestructive() {
        let before = engine("  sunscreen")
        _ = OutcomePreview.ghosts(for: OutcomePreviewSpec(doors: doors(insertDoors)), engine: before)
        #expect(before.mode == .normal)
        #expect(before.cursor == Position(line: 0, col: 0))
        #expect(before.buffer.text == "  sunscreen")
    }

    @Test("no preview means no ghosts")
    func noSpecNoGhosts() {
        #expect(OutcomePreview.ghosts(for: nil, engine: engine("x")).isEmpty)
    }

    @Test("a wrong door is corrected by naming the difference, never by scolding")
    func correctionNamesTheDifference() {
        let spec = OutcomePreviewSpec(doors: [
            OutcomeDoor(keys: "i", note: "types BEFORE the cursor"),
            OutcomeDoor(keys: "a", note: "types AFTER the cursor"),
        ])
        #expect(
            OutcomePreview.correction(pressed: "a", expected: "i", spec: spec)
                == "you pressed `a` — that types AFTER the cursor; try `i`"
        )
        // The right key needs no correction, and an un-previewed key falls back
        // to the step's own authored hint (nil here).
        #expect(OutcomePreview.correction(pressed: "i", expected: "i", spec: spec) == nil)
        #expect(OutcomePreview.correction(pressed: "x", expected: "i", spec: spec) == nil)
        #expect(OutcomePreview.correction(pressed: "a", expected: "i", spec: nil) == nil)
    }
}

@Suite("Chord display: the grammar composing, one key at a time", .tags(.unit))
struct ChordTrackerTests {

    @Test("d then i then w builds diw, and resolves only when the command closes")
    func dawnOfAChord() {
        var tracker = ChordTracker()

        #expect(tracker.record("d", midCommand: true) == .building(["d"]))
        #expect(tracker.display == "d")

        #expect(tracker.record("i", midCommand: true) == .building(["d", "i"]))
        #expect(tracker.display == "di")

        #expect(tracker.record("w", midCommand: false) == .completed(["d", "i", "w"]))
        #expect(tracker.display == "diw")
        #expect(tracker.isResolved)
    }

    @Test("a single key that completes on its own is its own chord")
    func singleKeyChord() {
        var tracker = ChordTracker()
        #expect(tracker.record("x", midCommand: false) == .completed(["x"]))
        #expect(tracker.display == "x")
    }

    @Test("the next key after a resolved chord starts a fresh row")
    func resolvedChordIsClearedByTheNextKey() {
        var tracker = ChordTracker()
        tracker.record("d", midCommand: true)
        tracker.record("w", midCommand: false)
        #expect(tracker.display == "dw")

        #expect(tracker.record("c", midCommand: true) == .building(["c"]))
        #expect(tracker.display == "c")
    }

    @Test("reset drops the row")
    func resetDropsTheRow() {
        var tracker = ChordTracker()
        tracker.record("d", midCommand: true)
        tracker.reset()
        #expect(tracker.keys.isEmpty)
        #expect(!tracker.isResolved)
    }

    @Test("the hub mirrors a real diw typed into a real engine")
    func hubMirrorsARealEngine() {
        let session = EditorSession(text: "hello there world")
        let hub = KeyFeedbackHub()
        for key in [KeyInput.char("d"), .char("i"), .char("w")] {
            session.feed(key)
            hub.observe(key, session: session)
        }
        #expect(hub.chord == ["d", "i", "w"])
        #expect(!hub.chordIsBuilding, "the command closed")

        // Typing literal text in Insert mode is not grammar — never a chord.
        for key in [KeyInput.char("i"), .char("a"), .char("b")] {
            session.feed(key)
            hub.observe(key, session: session)
        }
        #expect(hub.chord == ["b"])
    }

    @Test("key-caps carry a printable label for every input")
    func keyLabels() {
        #expect(KeyGlyph.label(for: .char("d")) == "d")
        #expect(KeyGlyph.label(for: .escape) == "Esc")
        #expect(KeyGlyph.label(for: .enter) == "⏎")
        #expect(KeyGlyph.label(for: .char(" ")) == "␣")
        #expect(KeyGlyph.label(forKeys: "\u{1B}") == "Esc")
    }
}

@Suite("Practice rewards: how loud a correct rep is", .tags(.unit))
struct PracticeRewardTests {

    private func event(_ category: CommandEvent.Category) -> CommandEvent {
        switch category {
        case .singleMotion:
            return CommandEvent(verb: .move, target: .motion(.wordForward), category: .singleMotion)
        case .operatorMotion:
            return CommandEvent(
                verb: .delete, target: .motion(.wordForward), category: .operatorMotion
            )
        case .fullGrammar:
            return CommandEvent(
                verb: .delete, modifier: .inside, target: .textObject(.word), category: .fullGrammar
            )
        case .action:
            return CommandEvent(verb: .deleteChar, category: .action)
        case .mode:
            return CommandEvent(verb: .enterInsert, category: .mode)
        case .commandLine:
            return CommandEvent(verb: .write, category: .commandLine)
        }
    }

    @Test("a rep is never a whisper — even the smallest correct move pops")
    func everyRepIsAtLeastAPop() {
        for category in [CommandEvent.Category.singleMotion, .mode] {
            let reward = PracticeReward.correct(events: [event(category)])
            #expect(reward.tier == .pop, "\(category.rawValue) should be floored to .pop")
        }
    }

    @Test("the graded ladder is preserved: composed grammar still bursts")
    func gradedLadderSurvivesTheFloor() {
        #expect(PracticeReward.correct(events: [event(.operatorMotion)]).tier == .pop)
        #expect(PracticeReward.correct(events: [event(.action)]).tier == .pop)
        #expect(PracticeReward.correct(events: [event(.commandLine)]).tier == .pop)
        #expect(PracticeReward.correct(events: [event(.fullGrammar)]).tier == .burst)
    }

    @Test("the loudest event in a batch wins")
    func loudestEventWins() {
        let batch = [event(.mode), event(.fullGrammar), event(.singleMotion)]
        #expect(PracticeReward.correct(events: batch).tier == .burst)
    }

    @Test("a rep with nothing gradeable in it still pops")
    func ungradedRepStillPops() {
        #expect(PracticeReward.correct(events: []).tier == .pop)
    }

    @Test("a rep is louder than the same command performed casually")
    func repsOutrankCasualCommands() throws {
        let casual = try #require(JuiceMapper.juice(for: event(.fullGrammar)))
        let rep = PracticeReward.correct(events: [event(.fullGrammar)])
        #expect(rep.intensity > casual.intensity)
        #expect(rep.intensity <= 1, "intensity is clamped — a rep cannot exceed the tier ceiling")
    }

    @Test("clearing a step and finishing a lesson both burst")
    func milestonesBurst() {
        #expect(PracticeReward.stepCleared.tier == .burst)
        #expect(PracticeReward.lessonLearned.tier == .burst)
        #expect(PracticeReward.lessonLearned.intensity >= PracticeReward.stepCleared.intensity)
    }
}

@Suite("Outcome previews authored in the lesson content", .tags(.integration))
struct LessonOutcomePreviewContentTests {

    @Test("the five-doors lesson previews every door it teaches")
    func fiveDoorsLessonHasItsPreview() throws {
        let db = try LessonDatabase.load()
        let lesson = try #require(db.lesson(id: "t1-insert-anywhere"))
        let preview = try #require(db.preview(lessonID: lesson.id))

        #expect(preview.doors.map(\.keys) == insertDoors)
        #expect(preview.caption?.isEmpty == false)
        for door in preview.doors {
            #expect(!door.note.isEmpty, "\(door.keys) needs a note — it is the wrong-key correction")
        }
    }

    @Test("every authored door resolves to a ghost on its own lesson document")
    func everyAuthoredDoorResolves() throws {
        let db = try LessonDatabase.load()
        for lesson in db.lessons {
            guard let preview = db.preview(lessonID: lesson.id) else { continue }
            let ghosts = OutcomePreview.ghosts(
                for: preview, engine: VimEngine(text: lesson.document)
            )
            #expect(ghosts.count == preview.doors.count, "\(lesson.id)")
            // A preview whose doors all land in the same place teaches nothing.
            let distinct = Set(ghosts.map { "\($0.anchor)" })
            #expect(distinct.count > 1, "\(lesson.id): the doors must differ from each other")
        }
    }

    @Test("lessons that did not opt in have no preview, and that is fine")
    func optingInIsOptional() throws {
        let db = try LessonDatabase.load()
        #expect(db.preview(lessonID: "t1-modes") == nil)
        #expect(db.previews.count < db.lessons.count)
    }
}
