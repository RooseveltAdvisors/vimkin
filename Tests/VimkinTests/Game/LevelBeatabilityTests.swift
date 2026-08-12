import Foundation
import Testing
@testable import Vimkin

/// THE LOAD-BEARING SUITE (plan U7 verification / `reality-gate`).
///
/// An unbeatable level is worse than no level. Every authored World 1 level is
/// replayed here through a REAL VimEngine behind its REAL skill gate, using
/// only the commands the level itself hands out, and must end with every goal
/// met. Nothing is mocked and nothing is stubbed: if this suite is green, the
/// world is genuinely finishable.
@Suite("Game: every World 1 level is beatable")
struct LevelBeatabilityTests {

    @Test("every level is completed by its canonical solution")
    func everyLevelIsBeatable() throws {
        var failures: [String] = []

        for level in try world1().levels {
            var state = try gatedState(for: level)
            state.send(keys: level.solution)

            if !state.isComplete {
                let stranded = state.remainingVimkins.map(\.id).joined(separator: ", ")
                let openGoals = level.extraGoals.count - state.satisfiedGoalIndices.count
                failures.append(
                    "\(level.id): NOT beatable — stranded [\(stranded)], "
                        + "\(openGoals) extra goal(s) open, "
                        + "cursor ended at \(state.engine.cursor)"
                )
            }
        }

        #expect(failures.isEmpty, "unbeatable levels:\n\(failures.joined(separator: "\n"))")
    }

    @Test("no solution key is refused by the level's own skill gate")
    func solutionsStayInsideTheToolkit() throws {
        var failures: [String] = []
        for level in try world1().levels {
            var state = try gatedState(for: level)
            for (index, key) in level.solution.enumerated() {
                let input: KeyInput = key == "\u{1B}" ? .escape : .char(key)
                let step = state.send(input)
                if let reason = step.blockReason {
                    failures.append("\(level.id): key \(index) `\(key)` blocked — \(reason)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("every canonical solution beats par")
    func solutionsBeatPar() throws {
        for level in try world1().levels {
            var state = try gatedState(for: level)
            state.send(keys: level.solution)
            #expect(
                state.keystrokes <= level.par,
                "\(level.id): canonical solution spends \(state.keystrokes) of par \(level.par)"
            )
        }
    }

    /// A rescue that fires without the player doing anything is not a puzzle.
    @Test("every Vimkin is rescued by a key, not by the level opening")
    func noVimkinIsFreeOnArrival() throws {
        for level in try world1().levels {
            var state = try gatedState(for: level)
            #expect(state.rescuedCount == 0, "\(level.id) opens with a rescue already banked")

            var rescuedBySomeKey = Set<String>()
            for key in level.solution {
                let input: KeyInput = key == "\u{1B}" ? .escape : .char(key)
                rescuedBySomeKey.formUnion(state.send(input).newlyRescued.map(\.id))
            }
            #expect(
                rescuedBySomeKey == Set(level.vimkins.map(\.id)),
                "\(level.id): \(Set(level.vimkins.map(\.id)).subtracting(rescuedBySomeKey).sorted()) were never freed by a keystroke"
            )
        }
    }

    /// Each level must actually require the thing it claims to teach: dropping
    /// the level's NEWEST commands from the toolkit must make it unbeatable.
    @Test("a level's new commands are load-bearing, not decoration")
    func newCommandsAreRequired() throws {
        let world = try world1()
        let database = try gameCommands()

        for (previous, level) in zip(world.levels, world.levels.dropFirst()) {
            let newCommands = Set(level.allowedCommandIDs)
                .subtracting(previous.allowedCommandIDs)
            guard !newCommands.isEmpty else { continue }   // levels 7-9 re-use the toolkit

            let crippled = Level(
                id: level.id, title: level.title, order: level.order, intro: level.intro,
                teaches: level.teaches,
                allowedCommandIDs: previous.allowedCommandIDs,
                par: level.par, solution: level.solution, vimkins: level.vimkins,
                extraGoals: level.extraGoals, document: level.document
            )
            var state = GameState(
                level: crippled,
                lockFilter: LockFilter.make(level: crippled, database: database)
            )
            state.send(keys: level.solution)
            #expect(
                !state.isComplete,
                "\(level.id): the canonical solution still wins without \(newCommands.sorted()) — the new commands are not actually taught"
            )
        }
    }

    /// The whole world, start to finish, on a fresh profile: level 1 unlocked,
    /// each clear opening the next, mastery and XP accumulating as you go.
    @Test("a fresh profile can play World 1 end to end")
    @MainActor
    func fullWorldPlaythrough() throws {
        let world = try world1()
        let database = try gameCommands()
        let progress = makeGameProgressStore()
        let results = makeLevelResultsStore()

        for level in world.levels {
            #expect(
                results.isUnlocked(level: level, in: world),
                "\(level.id) was still locked when the player arrived"
            )
            let session = GameSession(
                level: level, database: database, progress: progress, gameProgress: results
            )
            session.send(keys: level.solution)
            #expect(session.state.isComplete, "\(level.id) was not completed")
            #expect(results.isCompleted(levelID: level.id))
        }

        #expect(results.furthestClearedOrder(in: world) == 10)
        #expect(progress.totalXP > 0, "a full playthrough earned no XP")
        #expect(
            progress.state.mastery["motion.down"] != nil,
            "a full playthrough recorded no mastery for `j`"
        )
    }
}
