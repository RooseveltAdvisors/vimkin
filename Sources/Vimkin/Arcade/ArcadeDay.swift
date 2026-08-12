// ArcadeDay.swift — the calendar day is the arcade's seed (plan U12).
//
// The daily run must be IDENTICAL for everyone on a given date and identical
// across app launches, so the seed is derived from the day string with a stable
// hash — never `String.hashValue`, which is seeded per process (the same reason
// `DrillSiteFinder` rolls its own FNV-1a).
//
// Every entry point takes an injected date + calendar so tests never depend on
// the host clock or time zone.

import Foundation

public enum ArcadeDay {
    /// Namespace salt, so the day seed can never collide with some other
    /// seeded surface that happens to hash the same string.
    private static let salt = "vimkin.arcade."

    /// The calendar-day key ("yyyy-MM-dd") a date falls in. Same format the
    /// progress store uses for streaks, so the two agree about "a day".
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The run seed for a day key. Deterministic across launches and machines.
    public static func seed(forDay day: String) -> UInt64 {
        stableHash(salt + day)
    }

    /// The run seed for a date.
    public static func seed(for date: Date, calendar: Calendar = .current) -> UInt64 {
        seed(forDay: key(for: date, calendar: calendar))
    }

    /// Midday on the given day key (midday so a DST shift can never round the
    /// date backwards), or nil for an unparseable key.
    public static func date(forDay day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }

    /// The day key `offset` days from `day` (negative walks backwards).
    /// Returns nil when `day` is unparseable.
    public static func day(_ day: String, offsetBy offset: Int, calendar: Calendar = .current) -> String? {
        guard let date = date(forDay: day, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: offset, to: date)
        else { return nil }
        return key(for: moved, calendar: calendar)
    }

    /// FNV-1a. Stable across processes, unlike `String.hashValue`.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
