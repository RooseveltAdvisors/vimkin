// MasteryMap.swift — the "where do I stand" model (plan U12).
//
// A read-only projection of `ProgressStore` grouped by curriculum tier. Pure
// Foundation, no SwiftUI, no writes: building a map can never change a score,
// which is what lets the view rebuild it as often as it likes.
//
// Honesty rules it encodes (plan R7):
//   • RUSTY is the call to action, so it sorts first everywhere.
//   • The streak line is a TREND ("practised 32 of the last 40 days"), never a
//     guilt counter — the number is the same whether it flatters you or not.
//   • Locked commands are counted, never listed as failures. A tier you have
//     not reached is a road ahead, not a gap in your record.

import Foundation

/// One command's standing.
public struct MasterySkill: Equatable, Sendable, Identifiable {
    public let commandID: String
    public let commandKeys: String
    public let title: String
    public let tier: Int
    /// Order within the tier (curriculum order).
    public let lesson: Int
    public let state: MasteryState
    /// Effective (decay-applied) mastery score, 0-100.
    public let score: Double

    public var id: String { commandID }

    public init(
        commandID: String,
        commandKeys: String,
        title: String,
        tier: Int,
        lesson: Int,
        state: MasteryState,
        score: Double
    ) {
        self.commandID = commandID
        self.commandKeys = commandKeys
        self.title = title
        self.tier = tier
        self.lesson = lesson
        self.state = state
        self.score = score
    }

    /// The one state that asks for action: you had this, and it is slipping.
    public var needsAttention: Bool { state == .rusty }
}

/// One curriculum tier's worth of standing.
public struct MasteryTierGroup: Equatable, Sendable, Identifiable {
    public let tier: Int
    public let title: String
    /// Unlocked commands in this tier, in curriculum order.
    public let skills: [MasterySkill]
    /// Commands in this tier still behind a lesson.
    public let lockedCount: Int

    public var id: Int { tier }

    public init(tier: Int, title: String, skills: [MasterySkill], lockedCount: Int) {
        self.tier = tier
        self.title = title
        self.skills = skills
        self.lockedCount = lockedCount
    }

    public func count(of state: MasteryState) -> Int {
        skills.filter { $0.state == state }.count
    }

    /// Total commands in the tier, unlocked or not.
    public var totalCommands: Int { skills.count + lockedCount }

    /// 0…1 — mean mastery across the tier's UNLOCKED skills (0 when none).
    public var fill: Double {
        guard !skills.isEmpty else { return 0 }
        return skills.reduce(0) { $0 + $1.score } / Double(skills.count) / 100
    }

    /// Nothing unlocked here yet — the road ahead.
    public var isUntouched: Bool { skills.isEmpty }
}

/// The whole map.
public struct MasteryMap: Equatable, Sendable {
    public let tiers: [MasteryTierGroup]
    public let totalXP: Int
    public let currentStreak: Int
    public let graceDaysAvailable: Int
    public let trend: PracticeTrend

    public init(
        tiers: [MasteryTierGroup],
        totalXP: Int,
        currentStreak: Int,
        graceDaysAvailable: Int,
        trend: PracticeTrend
    ) {
        self.tiers = tiers
        self.totalXP = totalXP
        self.currentStreak = currentStreak
        self.graceDaysAvailable = graceDaysAvailable
        self.trend = trend
    }

    /// Every unlocked skill, tier order then curriculum order.
    public var allSkills: [MasterySkill] { tiers.flatMap(\.skills) }

    public func count(of state: MasteryState) -> Int {
        allSkills.filter { $0.state == state }.count
    }

    public var unlockedCount: Int { allSkills.count }

    public var lockedCount: Int { tiers.reduce(0) { $0 + $1.lockedCount } }

    /// The "practise next" affordance's running order.
    ///
    /// RUSTY FIRST, always — a skill you had and are losing is the highest-value
    /// thing you can spend five minutes on. Then learning, then unlearned, then
    /// mastered; lower score first within each band; command id breaks ties, so
    /// the order is stable across rebuilds.
    public var practiceNext: [MasterySkill] {
        allSkills.sorted { lhs, rhs in
            let lhsRank = Self.urgency(lhs.state)
            let rhsRank = Self.urgency(rhs.state)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.commandID < rhs.commandID
        }
    }

    /// Skills asking for a pass right now (rusty only). Empty is a good state,
    /// and the view says so rather than inventing a nag.
    public var rustySkills: [MasterySkill] {
        practiceNext.filter { $0.needsAttention }
    }

    /// Lower sorts first.
    private static func urgency(_ state: MasteryState) -> Int {
        switch state {
        case .rusty: return 0
        case .learning: return 1
        case .unlearned: return 2
        case .mastered: return 3
        }
    }

    // MARK: - Building

    /// Curriculum stage names (plan: tiers 1-5).
    public static func tierTitle(_ tier: Int) -> String {
        switch tier {
        case 1: return "Survive"
        case 2: return "Navigate"
        case 3: return "Edit verbs"
        case 4: return "Text-object grammar"
        case 5: return "Advanced"
        default: return "Tier \(tier)"
        }
    }

    /// Projects the store through the command database. Read-only.
    public static func build(
        database: CommandDatabase,
        store: ProgressStore,
        trendWindowDays: Int = 40
    ) -> MasteryMap {
        let unlocked = store.unlockedCommands
        let tiers = Set(database.commands.map(\.tier)).sorted().map { tier -> MasteryTierGroup in
            let commands = database.commands(tier: tier)
            let skills = commands
                .filter { unlocked.contains($0.id) }
                .map { command in
                    MasterySkill(
                        commandID: command.id,
                        commandKeys: command.keys,
                        title: command.title,
                        tier: command.tier,
                        lesson: command.lesson,
                        state: store.masteryState(commandID: command.id),
                        score: store.masteryScore(commandID: command.id)
                    )
                }
                .sorted { lhs, rhs in
                    lhs.lesson != rhs.lesson ? lhs.lesson < rhs.lesson : lhs.commandID < rhs.commandID
                }
            return MasteryTierGroup(
                tier: tier,
                title: tierTitle(tier),
                skills: skills,
                lockedCount: commands.count - skills.count
            )
        }

        return MasteryMap(
            tiers: tiers,
            totalXP: store.totalXP,
            currentStreak: store.currentStreak,
            graceDaysAvailable: store.graceDaysAvailable,
            trend: store.practiceTrend(windowDays: trendWindowDays)
        )
    }
}
