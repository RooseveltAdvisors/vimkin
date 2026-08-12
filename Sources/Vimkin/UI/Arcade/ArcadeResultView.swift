// ArcadeResultView.swift — the end of a run: your score against your OWN past
// runs. No global rank, no other people, no "you placed 4,812th".
//
// The honesty rules from the dojo's summary still apply here — accuracy is
// reported next to the score rather than buried, a practice replay says so
// plainly, and a finished day says "come back tomorrow" instead of dangling a
// retry that would not count.

import SwiftUI

struct ArcadeResultView: View {
    let result: ArcadeRunResult
    let leaderboard: ArcadeLeaderboardStore
    /// True when THIS run went onto the board (false for practice, and for a
    /// day that was already recorded before you walked in).
    let wasRecorded: Bool
    let hits: [ArcadeHit]
    let canPlayScoredRun: Bool

    var onPlayScored: () -> Void = {}
    var onPractice: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headline
                selfLeaderboard
                if !hits.isEmpty { hitTable }
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
            Text("\(result.score)")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(isPersonalBest ? ArcadeTheme.leaf : ArcadeTheme.amber)
                .monospacedDigit()

            Text(isPersonalBest && wasRecorded ? "new personal best" : "score")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(
                    isPersonalBest && wasRecorded
                        ? ArcadeTheme.leaf.opacity(0.9)
                        : ArcadeTheme.paper.opacity(0.55)
                )

            Text(
                "\(result.drillsCleared) of \(result.drillsPlanned) cleared"
                    + " · \(result.accuracyPercent)% accuracy"
                    + " · best combo ×\(max(1, result.bestCombo))"
            )
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(ArcadeTheme.paper.opacity(0.7))

            if !wasRecorded {
                Text(
                    canPlayScoredRun
                        ? "practice run — not scored"
                        : "today's run was already in the books"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ArcadeTheme.cyan.opacity(0.8))
            }
        }
        .padding(.top, 12)
    }

    private var isPersonalBest: Bool {
        guard let best = leaderboard.bestScore else { return result.score > 0 }
        return result.score >= best && result.score > 0
    }

    // MARK: - Your own board

    private var selfLeaderboard: some View {
        ArcadePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("You vs you")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(ArcadeTheme.paper.opacity(0.85))

                HStack(spacing: 28) {
                    stat("best", leaderboard.bestScore.map(String.init) ?? "—", ArcadeTheme.leaf)
                    stat(
                        "average",
                        leaderboard.averageScore.map { String(Int($0.rounded())) } ?? "—",
                        ArcadeTheme.cyan
                    )
                    stat("runs", "\(leaderboard.runCount)", ArcadeTheme.paper.opacity(0.8))
                    stat(
                        "day streak",
                        "\(leaderboard.dailyStreak(endingOn: result.day))",
                        ArcadeTheme.amber
                    )
                }

                let recent = leaderboard.recentRuns(limit: 7)
                if recent.count > 1 {
                    Divider().overlay(ArcadeTheme.paper.opacity(0.08))
                    ForEach(recent) { run in
                        HStack(spacing: 12) {
                            Text(run.day)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(
                                    run.day == result.day
                                        ? ArcadeTheme.amber
                                        : ArcadeTheme.paper.opacity(0.5)
                                )
                                .frame(width: 92, alignment: .leading)
                            scoreBar(run)
                            Text("\(run.score)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(ArcadeTheme.paper.opacity(0.7))
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scoreBar(_ run: ArcadeRunResult) -> some View {
        let ceiling = max(1, leaderboard.bestScore ?? run.score)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ArcadeTheme.paper.opacity(0.08))
                Capsule()
                    .fill(run.day == result.day ? ArcadeTheme.amber : ArcadeTheme.cyan.opacity(0.6))
                    .frame(width: proxy.size.width * min(1, Double(run.score) / Double(ceiling)))
            }
        }
        .frame(height: 8)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ArcadeTheme.paper.opacity(0.45))
        }
    }

    // MARK: - The run itself

    private var hitTable: some View {
        ArcadePanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("This run")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(ArcadeTheme.paper.opacity(0.85))
                ForEach(hits) { hit in
                    HStack(spacing: 12) {
                        keyBadge(hit.commandKeys)
                        Text(String(format: "%.1fs", hit.elapsed))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(ArcadeTheme.paper.opacity(0.6))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .leading)
                        if hit.isFlawless {
                            Text("×\(hit.comboLength)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(ArcadeTheme.comboTint(hit.comboLength))
                        } else {
                            Text("\(hit.misses) miss\(hit.misses == 1 ? "" : "es")")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(ArcadeTheme.coral.opacity(0.85))
                        }
                        Spacer()
                        Text("+\(hit.points)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(ArcadeTheme.paper.opacity(0.8))
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func keyBadge(_ keys: String) -> some View {
        Text(keys.isEmpty ? "?" : keys)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(ArcadeTheme.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ArcadeTheme.amber, in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 74, alignment: .leading)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 14) {
            if canPlayScoredRun {
                Button { onPlayScored() } label: {
                    HStack(spacing: 8) {
                        Text("Start today's run")
                        Keycap(label: "⏎")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArcadeTheme.amber)
            } else {
                Button { onPractice() } label: {
                    HStack(spacing: 8) {
                        Text("Practise again")
                        Keycap(label: "p")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArcadeTheme.cyan)
            }
            Button { onDone() } label: {
                HStack(spacing: 8) {
                    Text("Done")
                    Keycap(label: "Esc")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ArcadeTheme.paper.opacity(0.65))
        }
        .font(ArcadeTheme.mono)
        .padding(.top, 6)
    }
}
