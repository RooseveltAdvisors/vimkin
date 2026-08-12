// GameView.swift — the adventure surface (plan U7).
//
// A SpriteView hosting the tile world, wrapped in the SHARED KeyCaptureView
// (U4) whose lock-filter is the level's skill gate. Chrome (HUD, intro card,
// toast, win panel) is SwiftUI on top, where text stays crisp and Liquid-Glass
// adoption later is a chrome-only change.
//
// The gate is enforced twice on purpose: KeyCaptureView blocks the key before
// delivery (so the "not yet learned" shimmer fires without the engine ever
// seeing it), and GameState re-checks it (so no future UI can forget).

import SpriteKit
import SwiftUI

public struct GameView: View {
    private let level: Level
    private let database: CommandDatabase?
    private let onExit: () -> Void
    private let onAdvance: ((Level) -> Void)?
    private let nextLevel: Level?

    @State private var session: GameSession
    @State private var scene: GameScene
    @State private var showIntro = true
    @State private var toast: String?
    @State private var toastID = 0

    public init(
        level: Level,
        database: CommandDatabase?,
        progress: ProgressStore?,
        gameProgress: GameProgressStore?,
        nextLevel: Level? = nil,
        onAdvance: ((Level) -> Void)? = nil,
        onExit: @escaping () -> Void
    ) {
        let session = GameSession(
            level: level, database: database, progress: progress, gameProgress: gameProgress
        )
        self.level = level
        self.database = database
        self.nextLevel = nextLevel
        self.onAdvance = onAdvance
        self.onExit = onExit
        _session = State(initialValue: session)
        _scene = State(
            initialValue: GameScene(state: session.state, size: CGSize(width: 960, height: 600))
        )
    }

    public var body: some View {
        ZStack {
            GameTheme.background.ignoresSafeArea()

            KeyCaptureView(
                filter: { session.state.decision(for: $0) },
                onBlocked: { _, reason in showToast(reason) },
                onKey: handle
            ) {
                SpriteSceneView(scene: scene)
                    .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 12) {
                hud
                Spacer()
                if let toast { toastBar(toast) }
                itemBar
            }
            .padding(18)
            .allowsHitTesting(false)

            if showIntro { introCard }
            if session.state.isComplete && !showIntro { winPanel }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: - Input

    private func handle(_ key: KeyInput) {
        let step = session.send(key)
        scene.apply(session.state, step: step)
        if let cheer = step.newlyRescued.compactMap(\.cheer).first {
            showToast(cheer)
        }
    }

    private func showToast(_ message: String) {
        toast = message
        toastID += 1
        let id = toastID
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if id == toastID { toast = nil }
        }
    }

    // MARK: - Chrome

    private var hud: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment)
                Text(level.teaches)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment.opacity(0.5))
            }
            Spacer()
            hudStat(
                label: "vimkins",
                value: "\(session.state.rescuedCount)/\(session.state.totalVimkins)",
                tint: GameTheme.vimkinAmber
            )
            hudStat(
                label: "keys",
                value: "\(session.state.keystrokes)/\(level.par)",
                tint: session.state.isUnderPar ? GameTheme.leaf : GameTheme.coral
            )
            Button("Leave", action: onExit)
                .buttonStyle(.bordered)
                .font(.system(.caption, design: .monospaced))
                .allowsHitTesting(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GameTheme.inkNavy.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hudStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(GameTheme.parchment.opacity(0.45))
        }
    }

    /// What this level hands the player, as key-caps along the bottom of the
    /// world — the "what can I do here" affordance. It is the level's WHOLE
    /// toolkit: `LockFilter` blocks every key that is not on this bar.
    private var toolkit: [(keys: String, title: String)] {
        guard let database else { return [] }
        return level.allowedCommandIDs.compactMap { id in
            database.command(id: id).map { ($0.keys, $0.title) }
        }
    }

    private var itemBar: some View {
        HStack(spacing: 10) {
            Text("toolkit")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(GameTheme.parchment.opacity(0.4))
                .fixedSize()
            // Clipped, not expanding: a late level hands out ~18 commands, and
            // without this the bar's intrinsic width drags the whole window
            // layout wider than the window and clips the HUD at both ends.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(toolkit.enumerated()), id: \.offset) { _, item in
                        // A big toolkit becomes caps-only: ten wrapped captions
                        // is a wall of text, and the cap alone is the affordance.
                        keyCap(item.keys, toolkit.count <= 6 ? item.title : nil)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(GameTheme.inkNavy.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(GameTheme.cursorCyan.opacity(0.16), lineWidth: 1)
        )
        .opacity(toolkit.isEmpty ? 0 : 1)
    }

    private func keyCap(_ keys: String, _ title: String?) -> some View {
        HStack(spacing: 7) {
            Text(keys)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(GameTheme.inkNavy)
                .frame(minWidth: 22)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(GameTheme.parchment, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(GameTheme.vimkinAmber.opacity(0.55), lineWidth: 1)
                )
            if let title {
                Text(title)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.trailing, 4)
    }

    private func toastBar(_ message: String) -> some View {
        Text(.init(message))
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(GameTheme.parchment)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GameTheme.plumDark.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(GameTheme.cursorCyan.opacity(0.35), lineWidth: 1))
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: message)
    }

    private var introCard: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Level \(level.order)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(GameTheme.cursorCyan)
                Text(level.title)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment)
                Text(level.intro)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(GameTheme.parchment.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Text(level.teaches)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(GameTheme.vimkinAmber)
                Button("Begin") { showIntro = false }
                    .buttonStyle(.borderedProminent)
                    .font(.system(.body, design: .monospaced))
                    .padding(.top, 8)
            }
            .padding(40)
            .background(GameTheme.inkNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var winPanel: some View {
        VStack(spacing: 14) {
            Text("everyone is home")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(GameTheme.vimkinAmber)
            Text("\(session.state.totalVimkins) rescued · \(session.state.keystrokes) keys "
                + (session.state.isUnderPar ? "· under par" : "· par was \(level.par)"))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(GameTheme.parchment.opacity(0.8))
            HStack(spacing: 12) {
                Button("Replay") {
                    session.restart()
                    scene.apply(session.state, step: nil)
                }
                .buttonStyle(.bordered)
                if let nextLevel, let onAdvance {
                    Button("Next: \(nextLevel.title)") { onAdvance(nextLevel) }
                        .buttonStyle(.borderedProminent)
                }
                Button("World map", action: onExit)
                    .buttonStyle(.bordered)
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding(34)
        .background(GameTheme.plumDark.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(GameTheme.vimkinAmber.opacity(0.4), lineWidth: 1)
        )
    }
}
