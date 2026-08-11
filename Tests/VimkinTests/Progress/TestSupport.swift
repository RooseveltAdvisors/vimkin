import Foundation
@testable import Vimkin

// Shared test scaffolding for the Progress suites: a mutable injected clock,
// a fixed calendar, fixed reference dates, and throwaway store directories.

/// Deterministic, advanceable clock injected as the store's `now`.
final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(days: Int) {
        now = testCalendar.date(byAdding: .day, value: days, to: now)!
    }
}

/// Fixed Gregorian/UTC calendar so day math never depends on the host machine.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Day N of the simulation: 2026-01-01 12:00 UTC + N days.
func day(_ offset: Int) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    components.hour = 12
    let base = testCalendar.date(from: components)!
    return testCalendar.date(byAdding: .day, value: offset, to: base)!
}

/// A unique throwaway directory for one store instance.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("VimkinProgressTests-\(UUID().uuidString)", isDirectory: true)
}
