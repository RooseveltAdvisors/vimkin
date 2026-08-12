import Foundation
import Testing
@testable import Vimkin

@Suite("Game: state, goals, par and the engine sync invariant")
struct GameStateTests {

    // MARK: - Locked keys provably do nothing

    @Test("a locked key leaves the game state bit-for-bit identical")
    func lockedKeyChangesNothing() throws {
        let level = try #require(try world1().level(order: 1))
        var state = try gatedState(for: level)
        state.send(keys: "jj")           // get somewhere interesting first
        let before = state

        for key in "wbe0$Gfdcyxpuv" {
            let step = state.send(.char(key))
            #expect(step.wasBlocked, "`\(key)` should be locked")
            #expect(step.events.isEmpty)
            #expect(step.newlyRescued.isEmpty)
        }

        #expect(state == before, "a locked key mutated the game state")
        #expect(state.engine.buffer == before.engine.buffer)
        #expect(state.engine.cursor == before.engine.cursor)
        #expect(state.engine.mode == before.engine.mode)
        #expect(state.keystrokes == before.keystrokes, "a blocked key must not cost par")
    }

    @Test("a locked key records no mastery rep and no XP")
    @MainActor
    func lockedKeyRecordsNothing() throws {
        let level = try #require(try world1().level(order: 1))
        let store = makeGameProgressStore()
        let session = GameSession(
            level: level, database: try gameCommands(), progress: store,
            gameProgress: makeLevelResultsStore()
        )

        session.send(.char("d"))
        session.send(.char("w"))
        session.send(.char("x"))

        #expect(session.state.keystrokes == 0)
        #expect(store.state.mastery.isEmpty, "a blocked key recorded a rep")
        #expect(store.totalXP == 0, "a blocked key awarded XP")
        #expect(session.lastBlock != nil, "the player should get a toast")
    }

    @Test("a delivered command DOES record a rep and XP — playing is practice")
    @MainActor
    func deliveredCommandRecordsPractice() throws {
        let level = try #require(try world1().level(order: 1))
        let store = makeGameProgressStore()
        let session = GameSession(
            level: level, database: try gameCommands(), progress: store,
            gameProgress: makeLevelResultsStore()
        )

        session.send(.char("j"))

        #expect(session.state.keystrokes == 1)
        #expect(store.state.mastery["motion.down"] != nil)
        #expect(store.totalXP > 0)
    }

    // MARK: - Completion

    @Test("completion fires only when EVERY goal is met, never on a partial")
    func completionRequiresAllGoals() throws {
        let level = makeLevel(
            par: 20,
            vimkins: [
                Vimkin(id: "A", position: Position(line: 0, col: 0),
                       condition: .cursorReaches(Position(line: 1, col: 0))),
                Vimkin(id: "B", position: Position(line: 0, col: 0),
                       condition: .cursorReaches(Position(line: 2, col: 0))),
            ],
            document: "one\ntwo\nthree"
        )
        var state = GameState(level: level)

        let first = state.send(.char("j"))
        #expect(first.newlyRescued.map(\.id) == ["A"])
        #expect(state.rescuedCount == 1)
        #expect(!state.isComplete, "one of two goals must not complete the level")

        let second = state.send(.char("j"))
        #expect(second.newlyRescued.map(\.id) == ["B"])
        #expect(state.isComplete)
        #expect(second.justCompleted)
    }

    @Test("an extra level goal gates completion even when every Vimkin is free")
    func extraGoalsGateCompletion() throws {
        let level = makeLevel(
            vimkins: [
                Vimkin(id: "A", position: Position(line: 0, col: 0),
                       condition: .cursorReaches(Position(line: 1, col: 0)))
            ],
            extraGoals: [.cursorReaches(Position(line: 2, col: 0))],
            document: "one\ntwo\nthree"
        )
        var state = GameState(level: level)

        state.send(.char("j"))
        #expect(state.rescuedCount == state.totalVimkins)
        #expect(!state.isComplete, "the extra goal is still open")

        state.send(.char("j"))
        #expect(state.isComplete)
    }

    @Test("`justCompleted` fires exactly once, on the key that finished the level")
    func completionEdgeFiresOnce() throws {
        let level = makeLevel(
            vimkins: [
                Vimkin(id: "A", position: Position(line: 0, col: 0),
                       condition: .cursorReaches(Position(line: 1, col: 0)))
            ],
            document: "one\ntwo\nthree"
        )
        var state = GameState(level: level)
        #expect(state.send(.char("j")).justCompleted)
        #expect(!state.send(.char("j")).justCompleted)
        #expect(state.isComplete, "completion latches")
    }

    @Test("a rescue latches — walking away does not re-trap a Vimkin")
    func rescuesLatch() throws {
        let level = makeLevel(
            vimkins: [
                Vimkin(id: "A", position: Position(line: 1, col: 0),
                       condition: .cursorReaches(Position(line: 1, col: 0)))
            ],
            document: "one\ntwo\nthree"
        )
        var state = GameState(level: level)
        state.send(.char("j"))
        #expect(state.rescuedCount == 1)
        state.send(.char("j"))
        #expect(state.rescuedCount == 1, "the Vimkin fell back into the page")
    }

    // MARK: - Rescue-condition vocabulary

    @Test("every rescue-condition kind is decidable from engine state")
    func allConditionKinds() throws {
        var engine = VimEngine(text: "keep the clutter here")
        #expect(GameState.isSatisfied(.cursorReaches(Position(line: 0, col: 0)), engine: engine))
        #expect(GameState.isSatisfied(.textPresent("clutter"), engine: engine))
        #expect(!GameState.isSatisfied(.textRemoved("clutter"), engine: engine))
        #expect(!GameState.isSatisfied(.registerContains("clutter"), engine: engine))

        engine.feed(keys: "wwdw")   // delete "clutter " into the register
        #expect(GameState.isSatisfied(.textRemoved("clutter"), engine: engine))
        #expect(GameState.isSatisfied(.registerContains("clutter"), engine: engine))
    }

    @Test("a text-changed rescue fires when the player types the missing letter")
    func textPresentRescue() throws {
        let level = makeLevel(
            allowed: ["action.insert-before", "action.escape", "motion.right"],
            par: 10,
            vimkins: [
                Vimkin(id: "Wick", position: Position(line: 0, col: 4),
                       condition: .textPresent("lantern"))
            ],
            document: "the lantrn is lit"
        )
        var state = GameState(level: level)
        state.send(keys: "llllllllie\u{1B}")   // walk to the `r` of `lantrn`, insert the `e`
        #expect(state.engine.buffer.text.contains("lantern"))
        #expect(state.isComplete)
    }

    // MARK: - Par accounting

    @Test("par counting matches a scripted playthrough exactly")
    func parCountingIsExact() throws {
        let level = try #require(try world1().level(order: 3))
        var state = try gatedState(for: level)
        state.send(keys: level.solution)
        #expect(state.keystrokes == level.solution.count)
        #expect(state.parDelta == level.solution.count - level.par)
        #expect(state.isUnderPar)
    }

    @Test("blocked keys are free; only delivered keys spend par")
    func blockedKeysAreFree() throws {
        let level = try #require(try world1().level(order: 1))
        var state = try gatedState(for: level)
        state.send(keys: "jdwdjy")     // j, j delivered; d w d y blocked
        #expect(state.keystrokes == 2)
    }

    @Test("a command that changes nothing still spends a keystroke — the engine saw it")
    func ineffectiveKeysStillCount() throws {
        let level = try #require(try world1().level(order: 1))
        var state = try gatedState(for: level)
        let before = state.engine.cursor
        state.send(.char("h"))   // already at col 0: vim clamps, nothing moves
        #expect(state.engine.cursor == before)
        #expect(state.keystrokes == 1, "a delivered key costs par even when nothing happens")
    }

    @Test("going over par never blocks completion — accuracy first")
    func parIsNotAGate() throws {
        let level = makeLevel(
            par: 1,
            vimkins: [
                Vimkin(id: "A", position: Position(line: 2, col: 0),
                       condition: .cursorReaches(Position(line: 2, col: 0)))
            ],
            document: "one\ntwo\nthree"
        )
        var state = GameState(level: level)
        state.send(keys: "jj")
        #expect(state.isComplete)
        #expect(!state.isUnderPar)
        #expect(state.parDelta == 1)
    }

    // MARK: - Engine ↔ game sync invariant

    @Test("the game's view of the document equals the engine buffer after EVERY event")
    func documentStaysInSyncWithTheEngine() throws {
        for level in try world1().levels {
            var state = try gatedState(for: level)
            #expect(state.documentLines == state.engine.buffer.lines, "\(level.id): drift at key 0")
            for (index, key) in level.solution.enumerated() {
                let input: KeyInput = key == "\u{1B}" ? .escape : .char(key)
                state.send(input)
                #expect(
                    state.documentLines == state.engine.buffer.lines,
                    "\(level.id): document drifted from the engine at key \(index) (`\(key)`)"
                )
                #expect(
                    state.documentLines.joined(separator: "\n") == state.engine.buffer.text,
                    "\(level.id): joined document text drifted at key \(index)"
                )
            }
        }
    }

    @Test("a fresh level starts pristine — nothing rescued, nothing spent")
    func freshLevelIsPristine() throws {
        for level in try world1().levels {
            let state = try gatedState(for: level)
            #expect(state.keystrokes == 0)
            #expect(state.rescuedCount == 0, "\(level.id) starts with a Vimkin already free")
            #expect(!state.isComplete, "\(level.id) is complete before the player moves")
            #expect(state.engine.buffer.text == level.document)
            #expect(state.engine.cursor == Position(line: 0, col: 0))
            #expect(state.engine.mode == .normal)
        }
    }

    // MARK: - Session + persistence

    @Test("finishing a level banks the result exactly once, keeping the best run")
    @MainActor
    func completionIsBankedOnce() throws {
        let level = try #require(try world1().level(order: 1))
        let results = makeLevelResultsStore()
        let session = GameSession(
            level: level, database: try gameCommands(),
            progress: makeGameProgressStore(), gameProgress: results
        )

        session.send(keys: level.solution)
        #expect(session.state.isComplete)
        let banked = try #require(results.result(levelID: level.id))
        #expect(banked.completed)
        #expect(banked.bestKeystrokes == level.solution.count)

        // Extra wandering after the win must not inflate the recorded score.
        session.send(keys: "jjjj")
        #expect(results.result(levelID: level.id)?.bestKeystrokes == level.solution.count)
    }

    @Test("the world map unlocks the next level only after the previous is cleared")
    func worldMapGating() throws {
        let world = try world1()
        let results = makeLevelResultsStore()
        let first = try #require(world.level(order: 1))
        let second = try #require(world.level(order: 2))

        #expect(results.isUnlocked(level: first, in: world))
        #expect(!results.isUnlocked(level: second, in: world))

        results.record(level: first, keystrokes: 21, rescued: 3, completed: true)
        #expect(results.isUnlocked(level: second, in: world))
        #expect(results.furthestClearedOrder(in: world) == 1)
    }

    @Test("restart returns the level to its opening state, gate intact")
    @MainActor
    func restartIsClean() throws {
        let level = try #require(try world1().level(order: 1))
        let session = GameSession(level: level, database: try gameCommands())
        session.send(keys: level.solution)
        #expect(session.state.isComplete)

        session.restart()
        #expect(session.state.keystrokes == 0)
        #expect(!session.state.isComplete)
        #expect(session.state.rescuedCount == 0)
        #expect(session.send(.char("d")).wasBlocked, "the gate should survive a restart")
    }

    @Test("every command event surfaces on the step hook — U8's juice attach point")
    @MainActor
    func stepHookSeesEveryEvent() throws {
        let level = try #require(try world1().level(order: 1))
        let session = GameSession(level: level, database: try gameCommands())
        var categories: [CommandEvent.Category] = []
        session.onStep = { step in categories += step.events.map(\.category) }

        session.send(keys: "jjll")
        #expect(categories == Array(repeating: .singleMotion, count: 4))
    }
}
