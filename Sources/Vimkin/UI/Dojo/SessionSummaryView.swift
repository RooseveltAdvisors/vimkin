// SessionSummaryView.swift — the end-of-set screen.
//
// Ethical-gamification rules (plan R7): accuracy is the headline, time is a
// friendly aside, mastery movement is shown as a gain rather than a rank, and
// a clean set gets praise instead of a "next weakness" nag.

import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionSummary
    var onPracticeAgain: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headline
                if summary.totalAttempts > 0 {
                    improvedPanel
                    weakestPanel
                    skillTable
                }
                controls
            }
            .frame(maxWidth: 680)
            .padding(24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 8) {
            Text(summary.totalAttempts == 0 ? "—" : "\(summary.accuracyPercent)%")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(accuracyTint)
            Text(summary.totalAttempts == 0 ? "Nothing practiced yet" : "accuracy")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(DojoTheme.paper.opacity(0.55))

            if summary.totalAttempts > 0 {
                Text(
                    "\(summary.drillsCompleted) of \(summary.drillsPlanned) drills"
                        + " · \(DojoTheme.unhurriedDuration(summary.duration))"
                )
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(DojoTheme.paper.opacity(0.7))

                if summary.unhurriedAttempts > 0 {
                    Text("\(summary.unhurriedAttempts) of those you took your time over — that counts.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DojoTheme.cyan.opacity(0.8))
                }
            } else {
                Text("Finish a lesson to unlock a skill, then come back.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(DojoTheme.paper.opacity(0.6))
            }
        }
        .padding(.top, 12)
    }

    private var accuracyTint: Color {
        switch summary.accuracy {
        case 0.9...: return DojoTheme.leaf
        case 0.6..<0.9: return DojoTheme.cyan
        default: return DojoTheme.amber
        }
    }

    // MARK: - Panels

    @ViewBuilder
    private var improvedPanel: some View {
        let gains = summary.improved
        if !gains.isEmpty {
            DojoPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What got stronger")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(DojoTheme.leaf)
                    ForEach(gains, id: \.commandID) { skill in
                        HStack {
                            keyBadge(skill.commandKeys)
                            Text(skill.commandID)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(DojoTheme.paper.opacity(0.55))
                            Spacer()
                            Text("+\(Int(skill.masteryDelta.rounded()))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(DojoTheme.leaf)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var weakestPanel: some View {
        DojoPanel {
            VStack(alignment: .leading, spacing: 8) {
                if let weakest = summary.weakestSkill {
                    Text("Worth another pass")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(DojoTheme.amber)
                    HStack(spacing: 10) {
                        keyBadge(weakest.commandKeys)
                        Text(
                            "\(weakest.correct) of \(weakest.attempts) right —"
                                + " it'll come up more often next set."
                        )
                        .font(DojoTheme.mono)
                        .foregroundStyle(DojoTheme.paper.opacity(0.8))
                    }
                } else {
                    Text("Clean set")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(DojoTheme.leaf)
                    Text("Every drill first try. Nothing to flag.")
                        .font(DojoTheme.mono)
                        .foregroundStyle(DojoTheme.paper.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var skillTable: some View {
        DojoPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("This set")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(DojoTheme.paper.opacity(0.8))
                ForEach(summary.practiceNext, id: \.commandID) { skill in
                    HStack(spacing: 12) {
                        keyBadge(skill.commandKeys)
                        Text("\(skill.correct)/\(skill.attempts)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(DojoTheme.paper.opacity(0.7))
                            .frame(width: 52, alignment: .leading)
                        masteryBar(skill)
                        Text("\(Int(skill.masteryAfter.rounded()))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(DojoTheme.paper.opacity(0.55))
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func masteryBar(_ skill: SkillSummary) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DojoTheme.paper.opacity(0.10))
                Capsule()
                    .fill(DojoTheme.cyan.opacity(0.35))
                    .frame(width: width * min(1, max(0, skill.masteryBefore / 100)))
                Capsule()
                    .fill(DojoTheme.cyan)
                    .frame(width: width * min(1, max(0, skill.masteryAfter / 100)))
                    .opacity(0.85)
            }
        }
        .frame(height: 8)
    }

    private func keyBadge(_ keys: String) -> some View {
        Text(keys.isEmpty ? "?" : keys)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(DojoTheme.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DojoTheme.amber, in: RoundedRectangle(cornerRadius: 6))
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { onPracticeAgain() } label: {
                HStack(spacing: 8) {
                    Text("Practice again")
                    Keycap(label: "⏎")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DojoTheme.cyan)

            Button { onDone() } label: {
                HStack(spacing: 8) {
                    Text("Done")
                    Keycap(label: "Esc")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DojoTheme.paper.opacity(0.65))
        }
        .font(DojoTheme.mono)
        .padding(.top, 6)
    }
}
