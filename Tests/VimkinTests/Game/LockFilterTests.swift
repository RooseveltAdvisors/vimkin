import Foundation
import Testing
@testable import Vimkin

@Suite("Game: the skill gate")
struct LockFilterTests {

    private func filter(
        for level: Level, unlocking unlocked: Set<String> = []
    ) throws -> LockFilter {
        LockFilter.make(level: level, database: try gameCommands(), unlockedCommandIDs: unlocked)
    }

    @Test("a level's own commands pass the gate")
    func allowedKeysPass() throws {
        let level = try #require(try world1().level(order: 1))
        let gate = try filter(for: level)
        for key in "hjkl" {
            #expect(gate.decision(for: .char(key), awaitingLiteral: false) == .allow)
        }
    }

    @Test("commands the level did not hand out are blocked")
    func lockedKeysBlocked() throws {
        let level = try #require(try world1().level(order: 1))
        let gate = try filter(for: level)
        for key in "wbe0$^GfdcyxpuvI" {
            let decision = gate.decision(for: .char(key), awaitingLiteral: false)
            #expect(decision != .allow, "`\(key)` should be locked in level 1")
        }
    }

    @Test("a block explains itself and points at the lesson that teaches it")
    func blockReasonNamesTheLesson() throws {
        let level = try #require(try world1().level(order: 1))
        let gate = try filter(for: level)
        guard case .block(let reason) = gate.decision(for: .char("d"), awaitingLiteral: false) else {
            Issue.record("`d` should be locked in level 1")
            return
        }
        #expect(reason.contains("Lesson"))
        #expect(reason.contains("Tier"))
        #expect(!reason.lowercased().contains("error"))
        #expect(!reason.lowercased().contains("wrong"))
    }

    @Test("an already-learned command still blocked reads as a toolkit note, not a lesson")
    func learnedButOutOfToolkit() throws {
        let level = try #require(try world1().level(order: 1))
        let gate = try filter(for: level, unlocking: ["operator.delete"])
        guard case .block(let reason) = gate.decision(for: .char("d"), awaitingLiteral: false) else {
            Issue.record("`d` should still be locked — the LEVEL decides the toolkit")
            return
        }
        #expect(reason.contains("this level's toolkit"))
    }

    @Test("Escape is never locked — the player can always come home")
    func escapeIsNeverLocked() throws {
        for level in try world1().levels {
            let gate = try filter(for: level)
            #expect(gate.decision(for: .escape, awaitingLiteral: false) == .allow)
        }
    }

    @Test("mid-command arguments are let through — otherwise `f\"` is untypeable")
    func literalArgumentsPass() throws {
        let level = try #require(try world1().level(order: 5))
        let gate = try filter(for: level)
        // `"` is not a command key in this level's toolkit…
        #expect(gate.decision(for: .char("\""), awaitingLiteral: false) != .allow)
        // …but as the argument of a pending `f`, it must reach the engine.
        #expect(gate.decision(for: .char("\""), awaitingLiteral: true) == .allow)
    }

    @Test("`f` plus its target actually moves the cursor through the gate")
    func findTargetSurvivesTheGate() throws {
        let level = try #require(try world1().level(order: 5))
        var state = try gatedState(for: level)
        let before = state.engine.cursor
        state.send(keys: "f-")
        #expect(state.engine.cursor != before)
        #expect(state.keystrokes == 2)
    }

    @Test("a named key is not its spelling — Esc never unlocks E, s or c")
    func escSpellingIsNotClaimed() throws {
        let database = try gameCommands()
        let escape = try #require(database.command(id: "action.escape"))
        #expect(LockFilter.inputCharacters(for: escape).isEmpty)
        let write = try #require(database.command(id: "cmd.write"))
        #expect(LockFilter.inputCharacters(for: write) == [":"])
    }

    @Test("the boss level hands out insert mode; earlier levels do not")
    func insertIsBossOnly() throws {
        let world = try world1()
        let boss = try #require(world.level(order: 10))
        #expect(try filter(for: boss).decision(for: .char("i"), awaitingLiteral: false) == .allow)
        for level in world.levels where level.order < 10 {
            let gate = try filter(for: level)
            #expect(
                gate.decision(for: .char("i"), awaitingLiteral: false) != .allow,
                "\(level.id) should not hand out insert mode"
            )
        }
    }
}
