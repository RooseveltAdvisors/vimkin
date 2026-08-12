// JuiceMapperTests — the graded-feedback contract (plan U8 / KTD 5).
//
// The pedagogy is encoded in the reward: composed grammar must FEEL bigger than
// a bare motion. These tests assert that as an ordering property, not as a pile
// of literals, so the tuning constants can move without the grading collapsing.

import CoreGraphics
import Testing
@testable import Vimkin

@Suite("Juice: CommandEvent → juice tier mapping")
struct JuiceMapperTests {
    // MARK: - Representative events, one per category

    static func event(for category: CommandEvent.Category) -> CommandEvent {
        switch category {
        case .singleMotion:
            return CommandEvent(verb: .move, target: .motion(.wordForward), category: .singleMotion)
        case .operatorMotion:
            return CommandEvent(verb: .delete, target: .motion(.wordForward), category: .operatorMotion)
        case .fullGrammar:
            return CommandEvent(
                verb: .change, modifier: .inside,
                target: .textObject(.quotedString), category: .fullGrammar
            )
        case .action:
            return CommandEvent(verb: .deleteChar, category: .action)
        case .mode:
            return CommandEvent(verb: .enterInsert, category: .mode)
        case .commandLine:
            return CommandEvent(verb: .writeQuit, category: .commandLine)
        }
    }

    // MARK: - The table

    @Test("every CommandEvent category maps to a tier — no silent gaps")
    func tableIsExhaustive() {
        for category in JuiceMapper.allCategories {
            let juice = JuiceMapper.juice(for: Self.event(for: category))
            #expect(juice != nil, "category \(category.rawValue) has no juice mapping")
        }
        // The list itself must stay in step with the engine's enum: every case
        // the engine can emit is represented exactly once.
        #expect(Set(JuiceMapper.allCategories).count == JuiceMapper.allCategories.count)
        #expect(JuiceMapper.allCategories.count == 6)
    }

    @Test("the documented tier table holds")
    func tierTable() {
        let expected: [CommandEvent.Category: JuiceTier] = [
            .singleMotion: .whisper,
            .mode: .whisper,
            .operatorMotion: .pop,
            .action: .pop,
            .commandLine: .pop,
            .fullGrammar: .burst,
        ]
        for (category, tier) in expected {
            #expect(JuiceMapper.juice(for: Self.event(for: category))?.tier == tier)
        }
    }

    @Test("a mode change whispers more quietly than a real motion")
    func modeIsTheSubtlestWhisper() {
        let mode = JuiceMapper.juice(for: Self.event(for: .mode))!
        let motion = JuiceMapper.juice(for: Self.event(for: .singleMotion))!
        #expect(mode.tier == motion.tier)          // same tier…
        #expect(mode.intensity < motion.intensity) // …but subtler
    }

    // MARK: - The grading property (this is the pedagogy)

    @Test("composed grammar always outranks a single motion — strictly")
    func composedGrammarStrictlyOutranksSingleMotion() {
        let motion = JuiceMapper.juice(for: Self.event(for: .singleMotion))!

        let composed: [CommandEvent] = [
            CommandEvent(verb: .change, modifier: .inside, target: .textObject(.quotedString), category: .fullGrammar),
            CommandEvent(verb: .delete, modifier: .inside, target: .textObject(.word), category: .fullGrammar),
            CommandEvent(verb: .yank, modifier: .around, target: .textObject(.parens), category: .fullGrammar),
            CommandEvent(verb: .delete, modifier: .around, target: .textObject(.paragraph), count: 2, category: .fullGrammar),
        ]

        for event in composed {
            let juice = JuiceMapper.juice(for: event)!
            #expect(juice.tier > motion.tier)
            #expect(juice.intensity > motion.intensity)
        }
    }

    @Test("the ladder is strictly ordered: motion < operator+motion < full grammar")
    func theLadderIsStrictlyOrdered() {
        let motion = JuiceMapper.juice(for: Self.event(for: .singleMotion))!
        let operatorMotion = JuiceMapper.juice(for: Self.event(for: .operatorMotion))!
        let grammar = JuiceMapper.juice(for: Self.event(for: .fullGrammar))!

        #expect(motion.tier < operatorMotion.tier)
        #expect(operatorMotion.tier < grammar.tier)
        #expect(motion.intensity < operatorMotion.intensity)
        #expect(operatorMotion.intensity < grammar.intensity)
    }

    @Test("tier ordering itself is whisper < pop < burst")
    func tierOrdering() {
        #expect(JuiceTier.whisper < JuiceTier.pop)
        #expect(JuiceTier.pop < JuiceTier.burst)
        #expect(JuiceTier.allCases == [.whisper, .pop, .burst])
    }

    // MARK: - Counts

    @Test("a counted command feels bigger than the same command once, same tier")
    func countNudgesIntensityWithoutChangingTier() {
        let once = JuiceMapper.juice(for: CommandEvent(verb: .delete, target: .motion(.wordForward), category: .operatorMotion))!
        let thrice = JuiceMapper.juice(for: CommandEvent(verb: .delete, target: .motion(.wordForward), count: 3, category: .operatorMotion))!

        #expect(thrice.tier == once.tier)
        #expect(thrice.intensity > once.intensity)
        // …and a huge count never escalates past a full-grammar burst.
        let huge = JuiceMapper.juice(for: CommandEvent(verb: .delete, target: .motion(.wordForward), count: 999, category: .operatorMotion))!
        #expect(huge.tier == .pop)
        #expect(huge.intensity <= 1.0)
    }

    // MARK: - Purity

    @Test("the mapper is pure: the same event always yields the same juice")
    func mapperIsDeterministic() {
        for category in JuiceMapper.allCategories {
            let event = Self.event(for: category)
            let first = JuiceMapper.juice(for: event)
            for _ in 0 ..< 50 {
                #expect(JuiceMapper.juice(for: event) == first)
            }
        }
    }

    @Test("a batch resolves to its loudest member, and an empty batch is silent")
    func batchTakesTheLoudestEvent() {
        let batch = [
            Self.event(for: .mode),
            Self.event(for: .fullGrammar),
            Self.event(for: .singleMotion),
        ]
        #expect(JuiceMapper.juice(for: batch)?.tier == .burst)
        #expect(JuiceMapper.juice(for: [CommandEvent]()) == nil)
    }

    @Test("juice carries no geometry of its own until a renderer supplies it")
    func positionIsRendererSupplied() {
        let juice = JuiceMapper.juice(for: Self.event(for: .fullGrammar))!
        #expect(juice.position == nil)
        #expect(juice.at(CGPoint(x: 10, y: 20)).position == CGPoint(x: 10, y: 20))
        #expect(juice.at(CGPoint(x: 10, y: 20)).tier == juice.tier)
    }
}
