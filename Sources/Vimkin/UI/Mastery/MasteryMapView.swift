// MasteryMapView.swift — the "where do I stand" home surface (plan U12).
//
// The calm end of the split: no clock, no score, no rank. It answers one
// question — what do I know, and what is slipping — and gives exactly one
// action: practise the thing that is going rusty.
//
// Ethical rules it renders (plan R7):
//   • RUSTY is the only colour that shouts, because it is the only call to
//     action. Everything else is reported, not judged.
//   • The trend line reads "practised 32 of the last 40 days" — a fact, never
//     "you missed 8 days".
//   • XP is celebratory and stated as a total; it gates nothing, so it is small.
//   • Locked commands are "still to come", never a deficit.

import SwiftUI

public struct MasteryMapView: View {
    private let store: ProgressStore
    private let database: CommandDatabase
    private let onClose: () -> Void

    /// Bumped after a practice hand-off so the map re-reads the store.
    @State private var revision = 0

    public init(
        store: ProgressStore,
        database: CommandDatabase? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.store = store
        self.database = database ?? (try? CommandDatabase.load()) ?? CommandDatabase(commands: [])
        self.onClose = onClose
    }

    private var map: MasteryMap {
        _ = revision
        return MasteryMap.build(database: database, store: store)
    }

    public var body: some View {
        let map = self.map
        return ZStack {
            LinearGradient(
                colors: [DojoTheme.background, DojoTheme.plum],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(DojoTheme.paper.opacity(0.08))
                ScrollView {
                    VStack(spacing: 16) {
                        standingBar(map)
                        practiceNextPanel(map)
                        ForEach(map.tiers) { tier in
                            tierPanel(tier)
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Label("Close", systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DojoTheme.paper.opacity(0.7))

            Text("Progress")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(DojoTheme.paper)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Standing

    private func standingBar(_ map: MasteryMap) -> some View {
        ArcadePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 28) {
                    stat("\(map.count(of: .mastered))", "mastered", ArcadeTheme.leaf)
                    stat("\(map.count(of: .learning))", "learning", ArcadeTheme.cyan)
                    stat("\(map.count(of: .rusty))", "going rusty", ArcadeTheme.coral)
                    stat("\(map.lockedCount)", "still to come", DojoTheme.paper.opacity(0.5))
                    Spacer()
                    stat("\(map.totalXP)", "XP", ArcadeTheme.amber)
                }

                // The honest trend — progress over perfection.
                VStack(alignment: .leading, spacing: 6) {
                    Text(trendLine(map))
                        .font(DojoTheme.mono)
                        .foregroundStyle(DojoTheme.paper.opacity(0.85))
                    trendBar(map.trend)
                    Text(streakLine(map))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DojoTheme.paper.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trendLine(_ map: MasteryMap) -> String {
        let trend = map.trend
        guard trend.practicedDays > 0 else {
            return "No practice logged yet — a single set starts the line."
        }
        return "Practised \(trend.practicedDays) of the last \(trend.windowDays) days."
    }

    private func streakLine(_ map: MasteryMap) -> String {
        let streak = map.currentStreak
        let grace = map.graceDaysAvailable
        let graceNote = grace > 0 ? " · \(grace) grace day\(grace == 1 ? "" : "s") banked" : ""
        guard streak > 0 else { return "Streak starts whenever you do.\(graceNote)" }
        return "\(streak) day\(streak == 1 ? "" : "s") running\(graceNote)"
    }

    private func trendBar(_ trend: PracticeTrend) -> some View {
        let fraction = trend.windowDays > 0
            ? Double(trend.practicedDays) / Double(trend.windowDays)
            : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DojoTheme.paper.opacity(0.10))
                Capsule()
                    .fill(ArcadeTheme.cyan.opacity(0.75))
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 8)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(DojoTheme.paper.opacity(0.45))
        }
    }

    // MARK: - Practise next

    @ViewBuilder
    private func practiceNextPanel(_ map: MasteryMap) -> some View {
        let rusty = map.rustySkills
        ArcadePanel {
            VStack(alignment: .leading, spacing: 10) {
                if rusty.isEmpty {
                    Text("Nothing going rusty")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(ArcadeTheme.leaf)
                    Text(
                        map.unlockedCount == 0
                            ? "Finish a lesson and your first skill shows up here."
                            : "Everything you've learned is still holding. Nice."
                    )
                    .font(DojoTheme.mono)
                    .foregroundStyle(DojoTheme.paper.opacity(0.7))
                } else {
                    Text("Worth a pass")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(ArcadeTheme.coral)
                    Text("You had these. Five minutes brings them back.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DojoTheme.paper.opacity(0.55))
                    ForEach(rusty) { skill in
                        skillRow(skill, prominent: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tiers

    private func tierPanel(_ tier: MasteryTierGroup) -> some View {
        ArcadePanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Tier \(tier.tier) · \(tier.title)")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(DojoTheme.paper.opacity(0.9))
                    Spacer()
                    Text("\(tier.skills.count) of \(tier.totalCommands) unlocked")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DojoTheme.paper.opacity(0.45))
                }

                if tier.isUntouched {
                    Text("Still ahead of you — \(tier.lockedCount) command\(tier.lockedCount == 1 ? "" : "s") to unlock.")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(DojoTheme.paper.opacity(0.45))
                } else {
                    ForEach(tier.skills) { skill in
                        skillRow(skill, prominent: false)
                    }
                    if tier.lockedCount > 0 {
                        Text("+ \(tier.lockedCount) still to unlock")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(DojoTheme.paper.opacity(0.35))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One command's row. Rusty rows are tappable — they hand off to a focused
    /// dojo session via the same notification the lookup overlay posts.
    private func skillRow(_ skill: MasterySkill, prominent: Bool) -> some View {
        let tint = ArcadeTheme.stateTint(skill.state)
        return Button {
            practice(skill)
        } label: {
            HStack(spacing: 12) {
                Text(skill.commandKeys)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(DojoTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint, in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 86, alignment: .leading)

                Text(skill.title)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(DojoTheme.paper.opacity(prominent ? 0.95 : 0.75))
                    .lineLimit(1)

                Spacer(minLength: 8)

                masteryBar(skill, tint: tint)

                Text(ArcadeTheme.stateLabel(skill.state))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.9))
                    .frame(width: 96, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, prominent ? 8 : 0)
            .background(
                prominent ? tint.opacity(0.10) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Practise \(skill.commandKeys) in the dojo")
    }

    private func masteryBar(_ skill: MasterySkill, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DojoTheme.paper.opacity(0.10))
                Capsule()
                    .fill(tint.opacity(0.8))
                    .frame(width: proxy.size.width * min(1, max(0, skill.score / 100)))
            }
        }
        .frame(width: 120, height: 7)
    }

    /// The hand-off: the dojo (and the app shell) already subscribe to this
    /// notification for the lookup overlay's "Practice this →", so a tap here
    /// reuses that path rather than inventing a second one.
    private func practice(_ skill: MasterySkill) {
        NotificationCenter.default.post(
            name: OverlayController.practiceCommandNotification,
            object: skill.commandID
        )
        revision &+= 1
    }
}
