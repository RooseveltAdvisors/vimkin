import Foundation
import Testing
@testable import Vimkin

/// The reality gate for generated drills: an unsolvable drill is worse than no
/// drill. Every generated drill is replayed through a REAL VimEngine from its
/// own start state, and the drill's own success predicate must fire.
@Suite("Dojo: every generated drill is solvable", .tags(.integration))
struct DrillSolvabilityTests {

    @Test("a large seeded sample of generated drills is solved by its canonical keys")
    func generatedDrillsAreSolvable() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: allDrillableIDs)

        var drills: [Drill] = []
        for seed in 0..<25 {
            drills += generator.makeSession(length: 12, seed: UInt64(seed))
        }
        #expect(drills.count == 300)

        var unsolved: [String] = []
        for drill in drills {
            guard let attempt = replay(drill.solutionKeys, on: drill) else {
                unsolved.append("\(drill.id): start unreachable")
                continue
            }
            if !drill.succeeds(attempt) {
                unsolved.append("\(drill.id): keys `\(drill.solutionKeys)` did not satisfy the goal")
            }
        }
        #expect(unsolved.isEmpty, "unsolvable drills:\n\(unsolved.prefix(10).joined(separator: "\n"))")
    }

    @Test("every drillable command yields at least one solvable drill on the real corpus")
    func everyDrillableCommandHasASolvableDrill() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: allDrillableIDs)

        for commandID in allDrillableIDs {
            let drills = generator.makeFocusedSession(commandID: commandID, length: 3, seed: 21)
            #expect(!drills.isEmpty, "no drill sites for \(commandID)")
            for drill in drills {
                let attempt = try #require(
                    replay(drill.solutionKeys, on: drill),
                    "unreachable start for \(commandID)"
                )
                #expect(drill.succeeds(attempt), "\(commandID) drill not solvable at \(drill.start)")
            }
        }
    }

    @Test("every drill actually changes something — no no-op drills")
    func drillsAreNonDegenerate() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: allDrillableIDs)
        let drills = generator.makeSession(length: 15, seed: 8)

        for drill in drills {
            let attempt = try #require(replay(drill.solutionKeys, on: drill))
            #expect(!attempt.events.isEmpty, "\(drill.id) emitted no events")
            let moved = attempt.after.cursor != attempt.before.cursor
            let edited = attempt.after.text != attempt.before.text
            let switched = attempt.after.mode != attempt.before.mode
            #expect(moved || edited || switched, "\(drill.id) is a no-op")
        }
    }

    @Test("positioning keys land the engine exactly on the drill's start cursor")
    func positioningIsExact() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: allDrillableIDs)
        for drill in generator.makeSession(length: 15, seed: 12) {
            let engine = try #require(
                DrillEngineSupport.engine(text: drill.documentText, at: drill.start)
            )
            #expect(engine.cursor == drill.start)
            #expect(engine.mode == .normal)
            #expect(engine.buffer.text == drill.documentText)
        }
    }
}
