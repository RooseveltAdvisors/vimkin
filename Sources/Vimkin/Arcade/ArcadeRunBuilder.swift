// ArcadeRunBuilder.swift — turns a calendar day into THE gauntlet for that day.
//
// Two properties this file exists to guarantee:
//
//  1. **Same day ⇒ identical run.** The whole sequence is a pure function of
//     (day seed, unlocked pool). Nothing here reads a clock, and the underlying
//     site scan is FNV-salted rather than `String.hashValue`-salted, so the run
//     survives an app relaunch (see `DrillSiteFinder.stableHash`).
//  2. **Mastery does NOT steer the arcade.** The dojo's generator is adaptive —
//     it leans toward whatever has gone rusty, which changes the moment you
//     practise. If the arcade inherited that weighting, playing the dojo at
//     lunchtime would silently rewrite the afternoon's gauntlet. So the arcade
//     picks UNIFORMLY from the unlocked pool via `makeFocusedSession`, and the
//     only thing that can change today's run is unlocking a new command.
//
// The unlock gate still holds: the pool is `generator.eligibleCommandIDs`, so a
// locked command can no more appear here than in the dojo.

import Foundation

public struct ArcadeRunBuilder {
    private let generator: DrillGenerator

    public init(generator: DrillGenerator) {
        self.generator = generator
    }

    /// Commands the gauntlet can draw from today (unlocked ∧ drillable), sorted.
    public var pool: [String] { generator.eligibleCommandIDs }

    /// The gauntlet for a day key. Empty when nothing is unlocked yet.
    public func gauntlet(day: String, length: Int = ArcadeRun.defaultLength) -> [Drill] {
        let pool = self.pool
        guard !pool.isEmpty, length > 0 else { return [] }

        var random = SeededGenerator(seed: ArcadeDay.seed(forDay: day))
        var drills: [Drill] = []
        var lastCommandID: String?

        for index in 0..<length {
            // Same variety rule as the dojo: never the same command twice in a
            // row (unless the pool has nothing else to offer).
            var candidates = pool.filter { $0 != lastCommandID }
            if candidates.isEmpty { candidates = pool }

            let commandID = candidates[Int(random.next(upperBound: UInt64(candidates.count)))]
            // Pull the site seed unconditionally, so a command with no site
            // cannot shift the rest of the sequence.
            let siteSeed = random.next()
            guard let base = generator
                .makeFocusedSession(commandID: commandID, length: 1, seed: siteSeed)
                .first
            else { continue }

            drills.append(Self.rekeyed(base, day: day, index: index))
            lastCommandID = commandID
        }
        return drills
    }

    /// The gauntlet for a date.
    public func gauntlet(
        for date: Date,
        calendar: Calendar = .current,
        length: Int = ArcadeRun.defaultLength
    ) -> [Drill] {
        gauntlet(day: ArcadeDay.key(for: date, calendar: calendar), length: length)
    }

    /// `makeFocusedSession` numbers every drill it builds `#0`, so a gauntlet
    /// that draws the same command twice would carry duplicate ids. Re-key with
    /// the run position so each drill in a run is uniquely addressable.
    private static func rekeyed(_ drill: Drill, day: String, index: Int) -> Drill {
        Drill(
            id: "arcade:\(day)#\(index):\(drill.id)",
            commandID: drill.commandID,
            commandKeys: drill.commandKeys,
            solutionKeys: drill.solutionKeys,
            documentName: drill.documentName,
            documentText: drill.documentText,
            start: drill.start,
            instruction: drill.instruction,
            goal: drill.goal,
            nearMisses: drill.nearMisses
        )
    }
}
