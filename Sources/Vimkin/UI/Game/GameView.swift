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
    /// Keyboard shell (U18). The briefing and the win panel are chrome; the
    /// level itself belongs entirely to the VimEngine.
    @State private var keyboard = KeyboardSurfaceModel()
    /// U21 — after a quiet spell, offer the keys instead of waiting to be
    /// asked. A level has a whole toolkit rather than one answer, so the hint
    /// re-states the objective and points at the bar.
    @State private var idle = IdleHintModel()

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
                // The chrome's router sits IN FRONT of the level's lock gate,
                // so `Esc Esc` leaves without the gate ever seeing the key —
                // and while playing, every other key falls straight through to
                // the gate exactly as before.
                filter: keyboard.engineFilter(
                    mode: { playPhase },
                    map: { playMap },
                    base: { session.state.decision(for: $0) },
                    onAction: navigate
                ),
                onBlocked: { _, reason in
                    // A menu key the chrome swallowed is not a locked command;
                    // showing the "not yet learned" toast for it would be a lie.
                    guard !KeyboardSurfaceModel.isChromeBlock(reason) else { return }
                    showToast(reason)
                },
                onKey: handle
            ) {
                SpriteSceneView(scene: scene)
                    .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 12) {
                hud
                Spacer()
                if let remaining = remainingObjective { remainingBar(remaining) }
                if let toast { toastBar(toast) }
                if idle.isDue && !showIntro && !session.state.isComplete {
                    IdleHintBar(
                        text: IdleHintBar.forLevel(
                            keys: toolkit.map(\.keys),
                            objective: LevelBriefing.shortObjective(for: level)
                        )
                    )
                }
                itemBar
            }
            .padding(18)
            .allowsHitTesting(false)

            if showIntro { introCard }
            if session.state.isComplete && !showIntro { winPanel }
        }
        .frame(minWidth: 820, minHeight: 560)
        .animation(.easeOut(duration: 0.2), value: idle.isDue)
        // The hint watches only while the level is actually being played.
        .task(id: showIntro) {
            if showIntro { idle.end() } else { idle.begin() }
        }
        .onDisappear { idle.end() }
        // `hasInnerCapture` is true because the SpriteKit surface's own
        // `KeyCaptureView` above is the one reading plain keys. This modifier
        // is here for the hint bar, the `?` overlay and the ⌘-verbs — routing
        // the same press in both places would fire the leave-chord twice.
        .keyboardSurface(
            keyboard, map: playMap, mode: playPhase,
            hasInnerCapture: true, onAction: navigate
        )
    }

    // MARK: - Keyboard

    /// The level is the only place the engine owns the keys; the briefing and
    /// the win panel in front of it are ordinary menus.
    private var playPhase: InputMode {
        showIntro || session.state.isComplete ? .navigation : .engine
    }

    private var playMap: KeyMap {
        if showIntro { return SurfaceKeys.gameIntro }
        if session.state.isComplete { return SurfaceKeys.gameWin }
        return SurfaceKeys.gamePlaying
    }

    private func navigate(_ action: NavAction) {
        switch action {
        case .verb("begin"):
            showIntro = false
        case .verb("replay"):
            session.restart()
            scene.apply(session.state, step: nil)
        case .verb("next"), .activate:
            if let nextLevel, let onAdvance { onAdvance(nextLevel) } else { onExit() }
        case .verb("worldmap"), .back:
            onExit()
        default:
            break
        }
    }

    // MARK: - Input

    private func handle(_ key: KeyInput) {
        idle.noteActivity()
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
                // The objective, ON SCREEN, the whole time. Before U21 it was
                // said nowhere: the intro card is atmosphere, and once it is
                // dismissed nothing told you that walking onto a Vimkin is what
                // frees it.
                Text(LevelBriefing.shortObjective(for: level))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GameTheme.cursorCyan.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            hudStat(
                label: "vimkins freed",
                value: "\(session.state.rescuedCount)/\(session.state.totalVimkins)",
                tint: GameTheme.vimkinAmber
            )
            // NOT a fraction: `5/26` read as "5 of 26 collected, keep going",
            // when it is a budget being spent against a target you are free to
            // ignore. The count is the number; par is named beside it.
            hudStat(
                label: "keys used · par \(level.par)",
                value: "\(session.state.keystrokes)",
                tint: session.state.isUnderPar ? GameTheme.leaf : GameTheme.coral
            )
            Button(action: onExit) {
                HStack(spacing: 6) {
                    Text("Leave")
                        .font(.system(.caption, design: .monospaced))
                    Keycap(label: "Esc")
                    Keycap(label: "Esc")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(GameTheme.parchment.opacity(0.7))
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

    /// The boss level rescues four Vimkins and then keeps going — it carries an
    /// extra goal that is not drawn anywhere in the world. Played cold, the HUD
    /// reads `4/4` while nothing happens and there is no way to find out why.
    /// This is that missing sentence.
    private var remainingObjective: String? {
        guard !showIntro else { return nil }
        return LevelBriefing.remaining(
            for: level,
            rescued: session.state.rescuedCount,
            isComplete: session.state.isComplete
        )
    }

    private func remainingBar(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(GameTheme.vimkinAmber)
            Text(message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(GameTheme.parchment)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GameTheme.plumDark.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(GameTheme.vimkinAmber.opacity(0.45), lineWidth: 1)
        )
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

                // The story line above is atmosphere. This is the brief: what
                // you actually have to do, and what the number in the corner
                // means. Derived from the level, so it can never contradict it.
                VStack(alignment: .leading, spacing: 7) {
                    Text("YOUR JOB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(GameTheme.cursorCyan.opacity(0.85))
                    briefingLine(LevelBriefing.objective(for: level))
                    ForEach(LevelBriefing.extraObjectives(for: level), id: \.self) { extra in
                        briefingLine(extra)
                    }
                    briefingLine(LevelBriefing.parNote(for: level))
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 4)

                Button { showIntro = false } label: {
                    HStack(spacing: 8) {
                        Text("Begin")
                            .font(.system(.body, design: .monospaced))
                        Keycap(label: "⏎")
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(40)
            .background(GameTheme.inkNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func briefingLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(GameTheme.vimkinAmber.opacity(0.7))
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(GameTheme.parchment.opacity(0.85))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var winPanel: some View {
        VStack(spacing: 14) {
            Text("everyone is home")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(GameTheme.vimkinAmber)
            // "under par" is golf, and a first-timer should not have to know
            // golf to read their own result — so the target is named in keys.
            Text("\(session.state.totalVimkins) rescued · \(session.state.keystrokes) keys "
                + (session.state.isUnderPar
                    ? "· inside the \(level.par)-key par"
                    : "· the par was \(level.par) — the page is still done"))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(GameTheme.parchment.opacity(0.8))
            HStack(spacing: 12) {
                Button {
                    session.restart()
                    scene.apply(session.state, step: nil)
                } label: {
                    HStack(spacing: 7) {
                        Text("Replay")
                        Keycap(label: "r")
                    }
                }
                .buttonStyle(.bordered)
                if let nextLevel, let onAdvance {
                    Button { onAdvance(nextLevel) } label: {
                        HStack(spacing: 7) {
                            Text("Next: \(nextLevel.title)")
                            Keycap(label: "⏎")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(action: onExit) {
                    HStack(spacing: 7) {
                        Text("World map")
                        Keycap(label: "m")
                    }
                }
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
