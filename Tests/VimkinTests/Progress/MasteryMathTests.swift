import Foundation
import Testing
@testable import Vimkin

/// The mastery formulas as pure functions — no store, no clock, no disk.
/// (Their behaviour once a real `ProgressStore` drives them over time is pinned
/// by `MasteryModelTests` — integration tier.)
@Suite("Mastery math (pure)", .tags(.unit))
struct MasteryMathTests {

    @Test("pure update math is clamped to 0...100")
    func updateClamping() {
        #expect(MasteryModel.updatedScore(from: 100, outcome: .correct) <= 100)
        #expect(MasteryModel.updatedScore(from: 0, outcome: .incorrect) >= 0)
        #expect(MasteryModel.decayedScore(from: 5, daysSincePractice: 400, everMastered: false) == 0)
    }
}
