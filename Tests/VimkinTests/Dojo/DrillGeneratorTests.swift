import Foundation
import Testing
@testable import Vimkin

@Suite("Dojo: adaptive drill generation", .tags(.integration))
struct DrillGeneratorTests {

    private static let unlocked = [
        "motion.word-forward",
        "motion.line-end",
        "action.delete-char",
        "action.delete-line",
        "grammar.delete-inner-word",
    ]

    // MARK: - Unlock gate

    @Test("200 generated drills contain ONLY unlocked commands")
    func onlyUnlockedCommands() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: Self.unlocked)
        let unlockedSet = Set(Self.unlocked)

        var drills: [Drill] = []
        for seed in 0..<20 {
            drills += generator.makeSession(length: 10, seed: UInt64(seed))
        }

        #expect(drills.count == 200)
        let seen = Set(drills.map(\.commandID))
        #expect(seen.isSubset(of: unlockedSet), "leaked locked commands: \(seen.subtracting(unlockedSet))")
    }

    @Test("a drillable but LOCKED command never appears")
    func lockedCommandNeverAppears() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: Self.unlocked)
        // Drillable, deliberately not unlocked above.
        #expect(DrillCatalog.drillableCommandIDs.contains("motion.file-top"))
        #expect(generator.canDrill(commandID: "motion.file-top"))

        for seed in 0..<20 {
            let drills = generator.makeSession(length: 10, seed: UInt64(seed))
            #expect(!drills.contains { $0.commandID == "motion.file-top" })
        }
    }

    @Test("no unlocked commands ⇒ no drills (never a locked fallback)")
    func emptyPoolYieldsNoDrills() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: [])
        #expect(generator.makeSession(length: 12, seed: 1).isEmpty)
    }

    // MARK: - Weakest-skill weighting

    @Test("the weakest skill is drilled far more often over 1000 seeded draws")
    func weakestSkillIsFavored() throws {
        let store = makeDojoStore(unlocking: Self.unlocked)
        let weak = "grammar.delete-inner-word"

        for id in Self.unlocked where id != weak {
            practiceCorrect(store, id, times: 5)   // → mastered
        }
        store.recordRep(commandID: weak, outcome: .correct)
        for _ in 0..<3 { store.recordRep(commandID: weak, outcome: .incorrect) }

        #expect(store.masteryState(commandID: weak) == .learning)
        #expect(store.masteryScore(commandID: weak) < 20)
        for id in Self.unlocked where id != weak {
            #expect(store.masteryState(commandID: id) == .mastered)
        }

        let (generator, _) = try makeDojoGenerator(unlocking: Self.unlocked, store: store)

        // Independent single-drill draws, so the no-repeat rule can't cap the
        // weak command's share.
        var counts: [String: Int] = [:]
        for seed in 0..<1000 {
            for drill in generator.makeSession(length: 1, seed: UInt64(seed)) {
                counts[drill.commandID, default: 0] += 1
            }
        }

        let total = counts.values.reduce(0, +)
        #expect(total == 1000)
        let weakShare = Double(counts[weak] ?? 0) / Double(total)
        let uniformShare = 1.0 / Double(Self.unlocked.count)

        #expect(weakShare > 2 * uniformShare, "weak share \(weakShare) vs uniform \(uniformShare)")
        let strongest = counts.filter { $0.key != weak }.values.max() ?? 0
        #expect(counts[weak, default: 0] > 3 * strongest, "counts: \(counts)")
    }

    @Test("at equal mastery the ordering is rusty > learning > mastered")
    func weightOrderingAtEqualScore() {
        let score = 60.0
        let rusty = DrillGenerator.weight(score: score, state: .rusty)
        let learning = DrillGenerator.weight(score: score, state: .learning)
        let mastered = DrillGenerator.weight(score: score, state: .mastered)
        let unlearned = DrillGenerator.weight(score: score, state: .unlearned)

        #expect(rusty > learning)
        #expect(learning > mastered)
        #expect(mastered == unlearned)
    }

    @Test("a mastered skill is ALWAYS outranked by any non-mastered skill")
    func masteredIsAlwaysOutranked() {
        // Mastered means score ≥ 80; non-mastered means score < 80.
        let strongestMastered = DrillGenerator.weight(score: 80, state: .mastered)
        let weakestLearning = DrillGenerator.weight(score: 79.999, state: .learning)
        let weakestRusty = DrillGenerator.weight(score: 79.999, state: .rusty)

        #expect(weakestLearning > strongestMastered)
        #expect(weakestRusty > weakestLearning)
        #expect(DrillGenerator.weight(score: 100, state: .mastered) > 0, "no command is ever weight 0")
    }

    @Test("lower mastery always outweighs higher mastery within a state")
    func lowerMasteryWeighsMore() {
        for state in [MasteryState.rusty, .learning, .mastered, .unlearned] {
            #expect(
                DrillGenerator.weight(score: 10, state: state)
                    > DrillGenerator.weight(score: 70, state: state)
            )
        }
    }

    @Test("real store states map to the expected weight ordering")
    func weightOrderingOnARealStore() throws {
        let ids = ["motion.word-forward", "motion.line-end", "action.delete-line"]
        let clock = TestClock(now: day(0))
        let store = ProgressStore(
            directory: temporaryDirectory(),
            alternateDirectories: [],
            now: { clock.now },
            calendar: testCalendar
        )
        for id in ids { store.markLessonCompleted(commandID: id) }

        // rusty: mastered, then left alone long enough to decay below threshold.
        practiceCorrect(store, ids[0], times: 8)
        // learning: practiced once, never mastered.
        store.recordRep(commandID: ids[1], outcome: .correct)
        // mastered: drilled to the top and kept fresh.
        practiceCorrect(store, ids[2], times: 8)

        clock.advance(days: 20)
        practiceCorrect(store, ids[2], times: 4)   // refresh only the mastered one

        #expect(store.masteryState(commandID: ids[0]) == .rusty)
        #expect(store.masteryState(commandID: ids[1]) == .learning)
        #expect(store.masteryState(commandID: ids[2]) == .mastered)

        let content = try dojoContent()
        let generator = DrillGenerator(
            database: content.database, documents: content.documents, store: store
        )
        // Both non-mastered skills outrank the mastered one — that is the
        // invariant. (Between themselves, the lower score wins: the fully
        // decayed "learning" skill is the most urgent thing in this fixture.)
        #expect(generator.weight(for: ids[0]) > generator.weight(for: ids[2]))
        #expect(generator.weight(for: ids[1]) > generator.weight(for: ids[2]))
    }

    // MARK: - Variety

    @Test("a session never repeats the same command back to back")
    func noImmediateRepeats() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: Self.unlocked)
        for seed in 0..<40 {
            let drills = generator.makeSession(length: 15, seed: UInt64(seed))
            #expect(drills.count == 15)
            for (previous, next) in zip(drills, drills.dropFirst()) {
                #expect(
                    previous.commandID != next.commandID,
                    "seed \(seed) repeated \(next.commandID) back to back"
                )
            }
        }
    }

    @Test("a single-command pool degrades gracefully instead of looping forever")
    func singleCommandPool() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: ["action.delete-line"])
        let drills = generator.makeSession(length: 5, seed: 3)
        #expect(drills.count == 5)
        #expect(drills.allSatisfy { $0.commandID == "action.delete-line" })
    }

    // MARK: - Determinism

    @Test("same seed ⇒ identical drill sequence; different seeds differ")
    func determinism() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: Self.unlocked)
        let first = generator.makeSession(length: 12, seed: 4242)
        let second = generator.makeSession(length: 12, seed: 4242)

        #expect(first.count == 12)
        #expect(first == second)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.instruction) == second.map(\.instruction))

        let other = generator.makeSession(length: 12, seed: 99)
        #expect(first.map(\.id) != other.map(\.id))
    }

    @Test("a fresh generator with the same store reproduces the same seeded session")
    func determinismAcrossGeneratorInstances() throws {
        let store = makeDojoStore(unlocking: Self.unlocked)
        let (first, _) = try makeDojoGenerator(unlocking: Self.unlocked, store: store)
        let (second, _) = try makeDojoGenerator(unlocking: Self.unlocked, store: store)
        #expect(first.makeSession(length: 10, seed: 7) == second.makeSession(length: 10, seed: 7))
    }

    @Test("drills are spread across the corpus, not clustered at the top of one file")
    func drillsAreSpreadAcrossTheCorpus() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: allDrillableIDs)
        var drills: [Drill] = []
        for seed in 0..<5 { drills += generator.makeSession(length: 15, seed: UInt64(seed)) }

        let documents = Set(drills.map(\.documentName))
        let lines = Set(drills.map(\.start.line))
        #expect(documents.count >= 4, "documents used: \(documents)")
        #expect(lines.count >= 10, "distinct start lines: \(lines.count)")
        let onFirstLine = drills.filter { $0.start.line == 0 }.count
        #expect(Double(onFirstLine) / Double(drills.count) < 0.35, "too many drills pinned to line 1")
    }

    @Test("word-object drills always name a real word, never a lone bracket")
    func wordDrillsNameRealWords() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: ["grammar.delete-inner-word"])
        let drills = generator.makeFocusedSession(
            commandID: "grammar.delete-inner-word", length: 12, seed: 31
        )
        #expect(!drills.isEmpty)
        for drill in drills {
            let attempt = try #require(replay(drill.solutionKeys, on: drill))
            let captured = DrillEngineSupport.capturedText(attempt.after.register)
            #expect(
                captured.contains(where: { $0.isLetter || $0.isNumber }),
                "\(drill.instruction) captured \(captured)"
            )
            #expect(drill.instruction.contains(captured), "\(drill.instruction)")
        }
    }

    // MARK: - Drill shape

    @Test("every drill points at a real corpus document and a reachable cursor")
    func drillsAreWellFormed() throws {
        let (generator, _) = try makeDojoGenerator(unlocking: allDrillableIDs)
        let drills = generator.makeSession(length: 15, seed: 11)
        #expect(!drills.isEmpty)

        for drill in drills {
            #expect(Corpus.documentNames.contains(drill.documentName))
            #expect(!drill.instruction.isEmpty)
            #expect(drill.instruction.contains("line \(drill.start.line + 1)"))
            #expect(!drill.solutionKeys.isEmpty)
            #expect(
                DrillEngineSupport.engine(text: drill.documentText, at: drill.start) != nil,
                "unreachable start for \(drill.id)"
            )
        }
    }
}
