// PracticeReward.swift — how loud a correct rep is allowed to be.
//
// The Juice layer already grades a command by its own complexity
// (`.singleMotion` → whisper, `.operatorMotion` → pop, `.fullGrammar` → burst),
// and that grading IS the pedagogy. But a whisper is the right size for moving
// around a document and the WRONG size for "you just got the rep" on a practice
// surface — a lesson rep is an achievement even when the command is small.
//
// So practice takes the mapper's grading and applies a floor: every correct rep
// is at least a `.pop`, the composed grammar still bursts, and clearing a step
// or finishing a lesson always bursts. Nothing here can exceed `.burst`, so the
// ladder the Juice layer defines is preserved.

import Foundation

public enum PracticeReward {

    /// Extra weight a rep carries over the same command performed casually.
    private static let repBoost = 0.2

    /// The feedback for a CORRECT rep, given the events the attempt emitted.
    public static func correct(events: [CommandEvent]) -> JuiceEvent {
        guard let graded = JuiceMapper.juice(for: events) else {
            // A rep with no gradeable event still happened — pop for it.
            return JuiceEvent(tier: .pop, intensity: 0.55)
        }
        let tier = max(graded.tier, .pop)
        return JuiceEvent(tier: tier, intensity: graded.intensity + repBoost)
    }

    /// Clearing a whole step: always a burst, just under the lesson's own.
    public static let stepCleared = JuiceEvent(tier: .burst, intensity: 0.85)

    /// The end of a lesson — the biggest moment in the tutorial.
    public static let lessonLearned = JuiceEvent(tier: .burst, intensity: 1)
}
