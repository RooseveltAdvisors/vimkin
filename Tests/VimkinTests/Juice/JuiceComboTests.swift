// JuiceComboTests — the combo tracker: consecutive composed commands feel
// progressively better, the boost is capped, and it decays after a pause.
//
// Ethical-gamification constraint (plan R7): a combo can only ADD. Nothing here
// punishes — a plain motion between two `diw`s costs nothing, and a decayed
// combo never drops below the tier's own base intensity.

import Testing
@testable import Vimkin

@Suite("Juice: combo tracker", .tags(.unit))
struct JuiceComboTests {
    private let grammar = CommandEvent(
        verb: .delete, modifier: .inside, target: .textObject(.word), category: .fullGrammar
    )
    private let operatorMotion = CommandEvent(
        verb: .delete, target: .motion(.wordForward), category: .operatorMotion
    )
    private let motion = CommandEvent(verb: .move, target: .motion(.wordForward), category: .singleMotion)

    @Test("N consecutive composed commands raise intensity monotonically, then cap")
    func comboRaisesIntensityMonotonicallyAndCaps() {
        var combo = JuiceCombo()
        var time = 0.0
        var intensities: [Double] = []

        for _ in 0 ..< (combo.configuration.cap + 6) {
            time += 0.5 // well inside the decay window
            intensities.append(combo.register(grammar, at: time)!.intensity)
        }

        // Monotonic non-decreasing…
        for (previous, next) in zip(intensities, intensities.dropFirst()) {
            #expect(next >= previous)
        }
        // …strictly rising while under the cap…
        #expect(intensities[1] > intensities[0])
        // …and flat once the cap is reached (never above 1.0).
        #expect(intensities.last! <= 1.0)
        #expect(intensities.last! == intensities[combo.configuration.cap])
        #expect(combo.count == combo.configuration.cap)
    }

    @Test("the combo decays after a pause, back to the bare tier intensity")
    func comboDecaysAfterAPause() {
        var combo = JuiceCombo()
        var time = 0.0
        for _ in 0 ..< combo.configuration.cap {
            time += 0.5
            _ = combo.register(grammar, at: time)
        }
        let hot = combo.register(grammar, at: time + 0.5)!.intensity
        #expect(combo.count == combo.configuration.cap)

        // A short pause sheds part of the combo…
        let partial = combo.register(grammar, at: time + 0.5 + combo.configuration.decayInterval * 2)!.intensity
        #expect(partial < hot)
        #expect(combo.count < combo.configuration.cap)

        // …and a long pause sheds all of it: back to the raw mapper value.
        let cold = combo.register(grammar, at: time + 10_000)!
        #expect(cold.intensity == JuiceMapper.juice(for: grammar)!.intensity)
        #expect(combo.count == 1) // this very command starts the next run
    }

    @Test("decay is monotonic in the length of the pause")
    func longerPausesDecayMore() {
        func intensityAfterPause(_ pause: Double) -> Double {
            var combo = JuiceCombo()
            var time = 0.0
            for _ in 0 ..< combo.configuration.cap {
                time += 0.5
                _ = combo.register(grammar, at: time)
            }
            return combo.register(grammar, at: time + pause)!.intensity
        }

        let interval = JuiceCombo.Configuration().decayInterval
        let samples = [0.1, interval, interval * 2, interval * 4, interval * 40].map(intensityAfterPause)
        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next <= previous)
        }
        #expect(samples.last! < samples.first!)
    }

    @Test("a plain motion between composed commands never breaks the run (no punishment)")
    func plainMotionsDoNotBreakTheCombo() {
        var combo = JuiceCombo()
        var time = 0.0
        for _ in 0 ..< 4 {
            time += 0.4
            _ = combo.register(grammar, at: time)
        }
        let before = combo.count

        time += 0.4
        let motionJuice = combo.register(motion, at: time)!
        #expect(combo.count == before)             // untouched
        #expect(motionJuice.tier == .whisper)      // still graded by category

        time += 0.4
        #expect(combo.register(grammar, at: time)!.intensity > 0)
        #expect(combo.count == before + 1)         // the run continued
    }

    @Test("operator+motion counts as composed grammar for the combo")
    func operatorMotionFeedsTheCombo() {
        var combo = JuiceCombo()
        _ = combo.register(operatorMotion, at: 1)
        #expect(combo.count == 1)
        _ = combo.register(operatorMotion, at: 1.4)
        #expect(combo.count == 2)
    }

    @Test("the combo boost never pushes any tier past full intensity")
    func comboNeverExceedsOne() {
        var combo = JuiceCombo()
        var time = 0.0
        for _ in 0 ..< 200 {
            time += 0.2
            for event in [grammar, operatorMotion, motion] {
                let juice = combo.register(event, at: time)!
                #expect(juice.intensity <= 1.0)
                #expect(juice.intensity >= 0.0)
            }
        }
    }

    @Test("a combo run is deterministic — same timeline in, same intensities out")
    func comboIsDeterministic() {
        func run() -> [Double] {
            var combo = JuiceCombo()
            return (1 ... 12).map { combo.register(grammar, at: Double($0) * 0.5)!.intensity }
        }
        #expect(run() == run())
    }
}
