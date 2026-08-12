// WorldMapView.swift — World 1's level select (plan U7).
//
// The route owner for adventure mode: shows the ten levels of The Notebook with
// their locked / open / cleared state, and hands off to GameView. Level gating
// here is PROGRESSION (clear one, the next opens); the in-level command gate is
// LockFilter's job.

import SwiftUI

public struct AdventureView: View {
    private let onExit: () -> Void
    private let progress: ProgressStore?

    @State private var world: LevelDatabase?
    @State private var database: CommandDatabase?
    @State private var results = GameProgressStore()
    @State private var playing: Level?
    @State private var loadError: String?

    public init(progress: ProgressStore?, onExit: @escaping () -> Void) {
        self.progress = progress
        self.onExit = onExit
    }

    public var body: some View {
        Group {
            if let level = playing, let world {
                GameView(
                    level: level,
                    database: database,
                    progress: progress,
                    gameProgress: results,
                    nextLevel: world.next(after: level),
                    onAdvance: { next in playing = next },
                    onExit: { playing = nil }
                )
                .id(level.id)
            } else {
                map
            }
        }
        .task {
            if world == nil {
                do {
                    world = try LevelDatabase.loadWorld1()
                    database = try CommandDatabase.load()
                } catch {
                    loadError = "\(error)"
                }
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        ZStack {
            GameTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                if let loadError {
                    Text("World 1 could not be loaded: \(loadError)")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(GameTheme.coral)
                        .padding(24)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 250), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(world?.levels ?? []) { level in
                                card(for: level)
                            }
                        }
                        .padding(24)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("World 1 — The Notebook")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment)
                Text(subtitle)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment.opacity(0.55))
            }
            Spacer()
            Button("← Title", action: onExit)
                .buttonStyle(.bordered)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var subtitle: String {
        guard let world else { return "loading the notebook…" }
        let cleared = world.levels.filter { results.isCompleted(levelID: $0.id) }.count
        if cleared == 0 {
            return "the Entropy Worm scattered the Vimkins. go and get them back."
        }
        if cleared == world.levels.count {
            return "every Vimkin is home. the notebook is tidy again."
        }
        return "\(cleared) of \(world.levels.count) pages tidied"
    }

    private func card(for level: Level) -> some View {
        let unlocked = world.map { results.isUnlocked(level: level, in: $0) } ?? false
        let result = results.result(levelID: level.id)
        let cleared = result?.completed ?? false

        return Button {
            if unlocked { playing = level }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: "%02d", level.order))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(GameTheme.cursorCyan.opacity(unlocked ? 1 : 0.35))
                    Spacer()
                    if cleared {
                        Text("✦ cleared")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(GameTheme.vimkinAmber)
                    } else if !unlocked {
                        Text("locked")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(GameTheme.parchment.opacity(0.35))
                    }
                }
                Text(level.title)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment.opacity(unlocked ? 1 : 0.4))
                    .multilineTextAlignment(.leading)
                Text(level.teaches)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment.opacity(unlocked ? 0.6 : 0.28))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                HStack(spacing: 10) {
                    Label("\(level.vimkins.count)", systemImage: "sparkles")
                        .foregroundStyle(GameTheme.vimkinAmber.opacity(unlocked ? 0.85 : 0.3))
                    if let best = result?.bestKeystrokes, cleared {
                        Label("\(best)/\(level.par)", systemImage: "keyboard")
                            .foregroundStyle(
                                best <= level.par ? GameTheme.leaf : GameTheme.coral
                            )
                    } else {
                        Label("par \(level.par)", systemImage: "keyboard")
                            .foregroundStyle(GameTheme.parchment.opacity(unlocked ? 0.5 : 0.25))
                    }
                }
                .font(.system(.caption2, design: .monospaced))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                GameTheme.inkNavy.opacity(unlocked ? 0.85 : 0.5),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(
                    cleared
                        ? GameTheme.vimkinAmber.opacity(0.5)
                        : GameTheme.cursorCyan.opacity(unlocked ? 0.28 : 0.08),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}
