import Foundation
import Testing
@testable import Vimkin

@Suite("Streaks and grace days", .tags(.integration))
struct StreakTests {
    func makeStore() -> (ProgressStore, TestClock) {
        let clock = TestClock(now: day(0))
        let store = ProgressStore(
            directory: temporaryDirectory(),
            alternateDirectories: [],
            now: { clock.now },
            calendar: testCalendar
        )
        return (store, clock)
    }

    private func practice(_ store: ProgressStore) {
        store.recordRep(commandID: "motion.right", outcome: .correct)
    }

    @Test("daily practice builds a streak; same-day reps count once")
    func basicStreak() {
        let (store, clock) = makeStore()
        #expect(store.currentStreak == 0)

        practice(store)
        practice(store) // second rep same day
        #expect(store.currentStreak == 1)

        clock.advance(days: 1)
        practice(store)
        #expect(store.currentStreak == 2)
    }

    @Test("missing a day with grace available preserves the streak and consumes one grace")
    func graceConsumption() {
        let (store, clock) = makeStore()
        #expect(store.graceDaysAvailable == 2)

        practice(store) // day 0
        clock.advance(days: 2) // day 1 missed
        practice(store) // day 2

        #expect(store.graceDaysAvailable == 1)
        #expect(store.currentStreak == 2) // preserved, not reset
    }

    @Test("missing a day with zero grace resets the streak")
    func streakResetWithoutGrace() {
        let (store, clock) = makeStore()
        // Burn both banked grace days with two separate single-day misses.
        practice(store) // day 0
        clock.advance(days: 2)
        practice(store) // day 2, grace -> 1
        clock.advance(days: 2)
        practice(store) // day 4, grace -> 0
        #expect(store.graceDaysAvailable == 0)
        #expect(store.currentStreak == 3)

        clock.advance(days: 2) // day 5 missed with no grace left
        practice(store) // day 6
        #expect(store.currentStreak == 1) // reset
    }

    @Test("an unbridgeable gap shows a broken streak even before the next practice")
    func brokenStreakVisibleWithoutPractice() {
        let (store, clock) = makeStore()
        practice(store)
        #expect(store.currentStreak == 1)

        clock.advance(days: 10) // 9 missed days >> grace bank
        #expect(store.currentStreak == 0)
    }

    @Test("grace regenerates after 7 consecutive practiced days, capped at 2")
    func graceRegeneration() {
        let (store, clock) = makeStore()
        practice(store) // day 0
        clock.advance(days: 2)
        practice(store) // day 2 — consumes one grace
        #expect(store.graceDaysAvailable == 1)

        // 6 more consecutive days → 7-day no-miss run on day 8 → +1 grace.
        for _ in 0..<6 {
            clock.advance(days: 1)
            practice(store)
        }
        #expect(store.graceDaysAvailable == 2)

        // Another 14 consecutive days would earn 2 more — but the bank is capped.
        for _ in 0..<14 {
            clock.advance(days: 1)
            practice(store)
        }
        #expect(store.graceDaysAvailable == StreakModel.graceCap)
    }

    @Test("trend counts practiced days in the trailing window: N of the last 40")
    func trendMessageData() {
        let (store, clock) = makeStore()
        // 40-day pattern: practice on even days only → 20 practiced days.
        for offset in 0..<40 {
            if offset % 2 == 0 { practice(store) }
            clock.advance(days: 1)
        }
        clock.advance(days: -1) // "today" = day 39 (last day of the pattern)

        let trend = store.practiceTrend(windowDays: 40)
        #expect(trend.windowDays == 40)
        #expect(trend.practicedDays == 20)

        // A smaller window over the same log: days 30-39 → 5 practiced.
        let short = store.practiceTrend(windowDays: 10)
        #expect(short.practicedDays == 5)
    }
}
