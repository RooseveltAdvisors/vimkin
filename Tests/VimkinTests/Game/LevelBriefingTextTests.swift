import Foundation
import Testing
@testable import Vimkin

// The objective a level shows is DERIVED from the level, so it can never
// contradict it. These pin the derivation over hand-built levels; the bundled
// World 1 is checked by `InstructionClarityContentTests`.

private func makeLevel(
    order: Int = 1,
    par: Int = 20,
    vimkins: [Vimkin],
    extraGoals: [RescueCondition] = []
) -> Level {
    Level(
        id: "test-\(order)",
        title: "Test page",
        order: order,
        intro: "atmosphere",
        teaches: "h j k l",
        allowedCommandIDs: ["motion.left"],
        par: par,
        solution: "h",
        vimkins: vimkins,
        extraGoals: extraGoals,
        document: "a page"
    )
}

private func reachVimkin(_ id: String, line: Int = 0, col: Int = 0) -> Vimkin {
    Vimkin(id: id, position: Position(line: line, col: col), condition: .cursorReaches(Position(line: line, col: col)))
}

private func writtenVimkin(_ id: String, text: String) -> Vimkin {
    Vimkin(id: id, position: Position(line: 1, col: 1), condition: .textPresent(text))
}

@Suite("A level explains its own objective in plain words", .tags(.unit))
struct LevelBriefingTextTests {

    @Test("an all-reach level says that moving onto a Vimkin frees it")
    func reachOnlyObjective() {
        let level = makeLevel(vimkins: [reachVimkin("Pip"), reachVimkin("Bo", line: 3)])
        let objective = LevelBriefing.objective(for: level)
        #expect(objective.lowercased().contains("cursor"))
        #expect(objective.lowercased().contains("vimkin"))
        #expect(objective.lowercased().contains("free"))
        #expect(LevelBriefing.extraObjectives(for: level).isEmpty)
    }

    @Test("a level with a written rescue says the word has to be mended")
    func mixedRescueObjective() {
        let level = makeLevel(
            vimkins: [reachVimkin("Pip"), writtenVimkin("Wickern", text: "lantern")]
        )
        #expect(LevelBriefing.objective(for: level).lowercased().contains("mend"))
        let extras = LevelBriefing.extraObjectives(for: level)
        #expect(extras.count == 1)
        #expect(extras[0].contains("lantern"))
    }

    @Test("an extra goal becomes a sentence naming where to finish")
    func extraGoalBecomesASentence() {
        let level = makeLevel(
            vimkins: [reachVimkin("Pip")],
            extraGoals: [.cursorReaches(Position(line: 0, col: 36))]
        )
        let extras = LevelBriefing.extraObjectives(for: level)
        #expect(extras.count == 1)
        // 1-based on screen: a player counts lines from one, not zero.
        #expect(extras[0].contains("line 1"))
        #expect(extras[0].contains("column 37"))
    }

    @Test("nothing is 'remaining' while Vimkins are still trapped")
    func noRemainingLineMidLevel() {
        let level = makeLevel(
            vimkins: [reachVimkin("Pip"), reachVimkin("Bo", line: 2)],
            extraGoals: [.cursorReaches(Position(line: 0, col: 5))]
        )
        #expect(LevelBriefing.remaining(for: level, rescued: 1, isComplete: false) == nil)
    }

    @Test("every Vimkin free and the level still open names what is left")
    func remainingLineAppearsWhenOnlyTheExtraGoalIsLeft() throws {
        // This is the boss-level trap, exactly: the HUD reads 4/4 and the level
        // will not end, and before U21 nothing on screen said why.
        let level = makeLevel(
            vimkins: [reachVimkin("Pip"), reachVimkin("Bo", line: 2)],
            extraGoals: [.cursorReaches(Position(line: 0, col: 36))]
        )
        let remaining = try #require(
            LevelBriefing.remaining(for: level, rescued: 2, isComplete: false)
        )
        #expect(remaining.lowercased().contains("everyone is free"))
        #expect(remaining.contains("line 1"))
    }

    @Test("a finished level says nothing — the win panel is talking")
    func noRemainingLineOnceComplete() {
        let level = makeLevel(
            vimkins: [reachVimkin("Pip")],
            extraGoals: [.cursorReaches(Position(line: 0, col: 5))]
        )
        #expect(LevelBriefing.remaining(for: level, rescued: 1, isComplete: true) == nil)
    }

    @Test("an ordinary level has nothing extra to say when the last one pops")
    func noRemainingLineWithoutExtraGoals() {
        let level = makeLevel(vimkins: [reachVimkin("Pip")])
        #expect(LevelBriefing.remaining(for: level, rescued: 1, isComplete: false) == nil)
    }

    @Test("par is explained as a target, never a limit")
    func parIsExplained() {
        let note = LevelBriefing.parNote(for: makeLevel(par: 26, vimkins: [reachVimkin("Pip")]))
        #expect(note.contains("26"))
        #expect(note.lowercased().contains("not a limit"))
    }
}

@Suite("The HUD objective stays short enough to read at a glance", .tags(.unit))
struct LevelBriefingShortFormTests {

    @Test("the short form fits on one HUD line and still names the mechanic")
    func shortFormIsShortAndClear() {
        let level = makeLevel(
            vimkins: [reachVimkin("Pip"), writtenVimkin("Wickern", text: "lantern")]
        )
        let short = LevelBriefing.shortObjective(for: level)
        #expect(short.count <= 48, "the HUD line truncates past about fifty characters")
        #expect(short.lowercased().contains("cursor"))
        #expect(short.lowercased().contains("vimkin"))
        #expect(short.count < LevelBriefing.objective(for: level).count)
    }

    @Test("a mend-only level says so rather than talking about the cursor")
    func mendOnlyLevelShortForm() {
        let level = makeLevel(vimkins: [writtenVimkin("Wickern", text: "lantern")])
        #expect(LevelBriefing.shortObjective(for: level).lowercased().contains("mend"))
    }
}
