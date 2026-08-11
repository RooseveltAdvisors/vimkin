import Foundation

/// Pure streak transition logic — ethical streaks (plan R7): "any practice
/// today" counts, missed days consume banked grace instead of breaking the
/// streak, and grace regenerates with consistency.
public enum StreakModel {
    /// Grace days a fresh profile starts with, and the bank cap.
    public static let graceCap = 2
    /// Consecutive practiced days (no misses) per regenerated grace day.
    public static let regenRunLength = 7

    /// The streak state after practicing on `day`, where `missedDays` is the
    /// number of whole calendar days between the previous practice day and
    /// `day` with no practice (0 = consecutive day or same day).
    ///
    /// Rules:
    /// - Same day again: no change (a day counts once).
    /// - Consecutive day: streak +1; the no-miss run grows and every
    ///   `regenRunLength` days regenerates one grace day (capped).
    /// - Missed day(s) with enough grace banked: consume one grace per missed
    ///   day, streak continues (+1 for today); the no-miss run restarts.
    /// - Missed day(s) beyond the bank: streak resets to 1; bank untouched.
    public static func recordingPractice(
        _ state: StreakState, day: String, missedDays: Int
    ) -> StreakState {
        var next = state

        guard state.lastPracticeDay != day else { return state }

        if state.lastPracticeDay == nil {
            // First practice ever.
            next.current = 1
            next.consecutiveRun = 1
        } else if missedDays == 0 {
            next.current += 1
            next.consecutiveRun += 1
            if next.consecutiveRun.isMultiple(of: regenRunLength) {
                next.graceBank = min(graceCap, next.graceBank + 1)
            }
        } else if missedDays <= state.graceBank {
            next.graceBank -= missedDays
            next.current += 1
            next.consecutiveRun = 1 // a bridged miss is not "consecutive"
        } else {
            next.current = 1
            next.consecutiveRun = 1
        }

        next.lastPracticeDay = day
        return next
    }
}
