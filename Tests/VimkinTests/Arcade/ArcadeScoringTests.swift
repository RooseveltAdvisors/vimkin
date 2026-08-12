import Foundation
import Testing

@testable import Vimkin

@Suite("Arcade: scoring — speed counts, accuracy still dominates")
struct ArcadeScoringTests {

    // MARK: - The invariant (property test)

    @Test("PROPERTY: a fast wrong answer NEVER outscores a slower right one")
    func accuracyDominatesSpeed() {
        // 20k generated pairs: an arbitrarily fumbled-but-fast drill against an
        // arbitrarily clean-but-slow one, at arbitrary combo lengths. The clean
        // one must win every single time — this is the pedagogy, as a property.
        var random = SeededGenerator(seed: 0xA2CA_DE01)
        var checked = 0

        for _ in 0..<20_000 {
            // The right-but-slow answer: no misses, and as slow as we like.
            let slowElapsed = Double(random.next(upperBound: UInt64(300_000))) / 1000  // 0…300s
            // The wrong-but-fast answer: at least one miss, and as fast as we
            // like — including literally instant.
            let fastElapsed = Double(random.next(upperBound: UInt64(2_000))) / 1000     // 0…2s
            let misses = 1 + Int(random.next(upperBound: UInt64(6)))
            let cleanCombo = Int(random.next(upperBound: UInt64(30)))       // any combo, incl. none
            let fumbledCombo = Int(random.next(upperBound: UInt64(30)))     // even a (bogus) hot one

            let clean = ArcadeScoring.points(
                cleared: true, elapsed: slowElapsed, misses: 0, comboLength: cleanCombo
            )
            let fumbled = ArcadeScoring.points(
                cleared: true, elapsed: fastElapsed, misses: misses, comboLength: fumbledCombo
            )
            #expect(
                clean > fumbled,
                """
                accuracy stopped dominating: clean(slow \(slowElapsed)s, combo \(cleanCombo)) \
                = \(clean) ≤ fumbled(fast \(fastElapsed)s, \(misses) misses, combo \(fumbledCombo)) \
                = \(fumbled)
                """
            )

            // …and a drill never cleared at all scores below both.
            let unsolved = ArcadeScoring.points(
                cleared: false, elapsed: 0, misses: 0, comboLength: 30
            )
            #expect(unsolved == 0)
            #expect(unsolved < fumbled)
            checked += 1
        }
        #expect(checked == 20_000)
    }

    @Test("the invariant is structural: one miss costs more than all the speed there is")
    func missPenaltyExceedsSpeedCeiling() {
        // This single inequality is what makes the property above hold. If a
        // tuning pass ever inverts it, the property test fails loudly — and so
        // does this, naming the reason.
        #expect(ArcadeScoring.missPenalty > ArcadeScoring.speedBonusCeiling)
        #expect(ArcadeScoring.fastestFumbledClear < ArcadeScoring.slowestCleanClear)
    }

    @Test("a fumbled clear scores at ×1 no matter how hot the run was")
    func fumbleGetsNoComboMultiplier() {
        for combo in 0..<40 {
            #expect(ArcadeScoring.comboMultiplier(comboLength: combo, misses: 1) == 1)
            #expect(ArcadeScoring.comboMultiplier(comboLength: combo, misses: 3) == 1)
        }
    }

    // MARK: - Speed

    @Test("speed pays on a continuous curve, with no threshold cliff")
    func speedIsContinuous() {
        #expect(ArcadeScoring.speedBonus(elapsed: 0) == ArcadeScoring.speedBonusCeiling)

        var previous = ArcadeScoring.speedBonus(elapsed: 0)
        var largestStep = 0.0
        for tenth in 1...600 {  // 0.1s … 60s
            let bonus = ArcadeScoring.speedBonus(elapsed: Double(tenth) / 10)
            #expect(bonus < previous, "speed bonus must decay monotonically")
            largestStep = max(largestStep, previous - bonus)
            previous = bonus
        }
        // No cliff: no 0.1s of hesitation ever costs more than a point.
        #expect(largestStep < 1.5)
        #expect(previous > 0, "the bonus decays toward zero but never goes negative")
    }

    @Test("a negative elapsed (clock skew) is clamped, never a bonus over the ceiling")
    func negativeElapsedIsClamped() {
        #expect(ArcadeScoring.speedBonus(elapsed: -30) == ArcadeScoring.speedBonusCeiling)
    }

    @Test("faster is worth more, all else equal")
    func fasterScoresHigher() {
        let quick = ArcadeScoring.points(cleared: true, elapsed: 1, misses: 0, comboLength: 1)
        let slow = ArcadeScoring.points(cleared: true, elapsed: 25, misses: 0, comboLength: 1)
        #expect(quick > slow)
        #expect(slow >= ArcadeScoring.basePoints, "correctness alone is always paid")
    }

    // MARK: - Combo

    @Test("the combo multiplier rises step by step and stops at the ceiling")
    func comboRisesToCeiling() {
        #expect(ArcadeScoring.comboMultiplier(comboLength: 0) == 1)
        #expect(ArcadeScoring.comboMultiplier(comboLength: 1) == 1)
        #expect(abs(ArcadeScoring.comboMultiplier(comboLength: 2) - 1.15) < 1e-9)
        #expect(abs(ArcadeScoring.comboMultiplier(comboLength: 3) - 1.30) < 1e-9)

        var previous = 1.0
        for length in 1...50 {
            let multiplier = ArcadeScoring.comboMultiplier(comboLength: length)
            #expect(multiplier >= previous)
            #expect(multiplier <= ArcadeScoring.comboCeiling)
            previous = multiplier
        }
        #expect(ArcadeScoring.comboMultiplier(comboLength: 50) == ArcadeScoring.comboCeiling)
    }

    @Test("a cleared drill is always worth something")
    func clearedDrillsHaveAFloor() {
        let disastrous = ArcadeScoring.points(
            cleared: true, elapsed: 300, misses: 12, comboLength: 0
        )
        #expect(disastrous == ArcadeScoring.minimumClearedPoints)
        #expect(disastrous > 0)
    }

    @Test("the popped score is the rounded points")
    func scoreRoundsPoints() {
        for misses in 0...3 {
            for elapsed in [0.0, 1.5, 9.0, 40.0] {
                let points = ArcadeScoring.points(
                    cleared: true, elapsed: elapsed, misses: misses, comboLength: 4
                )
                let score = ArcadeScoring.score(
                    cleared: true, elapsed: elapsed, misses: misses, comboLength: 4
                )
                #expect(score == Int(points.rounded()))
            }
        }
    }
}
