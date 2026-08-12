// ArcadeView.swift — the Daily Run surface (plan U12).
//
// This is deliberately the OPPOSITE of `DojoView`. The dojo has no clock, no
// score, and no way to fail by being slow; the arcade puts a draining timer at
// the top of the screen, pops a number on every clear, and lets the juice run
// loud. Both are true to KTD 5: practice is calm, the daily run is the one
// place speed is allowed to matter — and accuracy still outweighs it in the
// scoring (see `ArcadeScoring`).

import SwiftUI

public struct ArcadeView: View {
    @State private var model: ArcadeModel
    /// Graded game-feel (U8). The arcade is where it should be loudest.
    @State private var juice = JuiceConductor(audio: JuiceAudio())
    /// Redraw clock — the HUD reads real time, so it needs a heartbeat.
    @State private var displayNow = Date()
    /// Keyboard shell (U18). The run itself is the engine's; the front door and
    /// the result card either side of it are menus.
    @State private var keyboard = KeyboardSurfaceModel()

    private let onClose: () -> Void

    private static let heartbeat = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public init(model: ArcadeModel? = nil, onClose: @escaping () -> Void = {}) {
        _model = State(initialValue: model ?? ArcadeModel.bundled())
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [ArcadeTheme.background, ArcadeTheme.plum],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(ArcadeTheme.paper.opacity(0.08))
                content
            }
        }
        .onReceive(Self.heartbeat) { now in
            displayNow = now
            model.tick()
        }
        .keyboardSurface(
            keyboard, map: map, mode: mode,
            hasInnerCapture: model.phase == .running, onAction: navigate
        )
    }

    // MARK: - Keyboard

    private var mode: InputMode { model.phase == .running ? .engine : .navigation }

    private var map: KeyMap {
        switch model.phase {
        case .idle: return SurfaceKeys.arcadeIdle
        case .running: return SurfaceKeys.arcadeRunning
        case .result: return SurfaceKeys.arcadeResult
        }
    }

    private func navigate(_ action: NavAction) {
        switch action {
        case .verb("start"), .activate:
            guard model.isReady else { return }
            model.startDailyRun()
        case .verb("practise"):
            guard model.isReady else { return }
            model.startPracticeRun()
        case .verb("skip"):
            model.skipDrill()
        case .verb("end"):
            model.endRun()
        case .verb("done"), .back:
            model.reset()
            onClose()
        default:
            break
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.reset()
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Label("Close", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                    Keycap(label: model.phase == .running ? "⌘L" : "Esc")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ArcadeTheme.paper.opacity(0.7))
            .keyboardShortcut("l", modifiers: .command)

            Text("Daily Run")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(ArcadeTheme.paper)
            Text(model.today)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ArcadeTheme.amber.opacity(0.8))

            Spacer()

            if let streak = streakLine {
                Text(streak)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ArcadeTheme.paper.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var streakLine: String? {
        let streak = model.leaderboard.dailyStreak(endingOn: model.today)
        guard streak > 0 else { return nil }
        return "\(streak) day\(streak == 1 ? "" : "s") in a row"
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle: frontDoor
        case .running: runStage
        case .result:
            ArcadeResultView(
                result: model.lastResult ?? ArcadeRunResult(
                    day: model.today, score: 0, drillsCleared: 0, drillsPlanned: 0,
                    attempts: 0, correctAttempts: 0, bestCombo: 0, duration: 0
                ),
                leaderboard: model.leaderboard,
                wasRecorded: model.lastResultWasRecorded,
                hits: model.session?.hits ?? [],
                canPlayScoredRun: model.canPlayScoredRun,
                onPlayScored: { model.startDailyRun() },
                onPractice: { model.startPracticeRun() },
                onDone: { model.reset(); onClose() }
            )
        }
    }

    // MARK: - Front door

    private var frontDoor: some View {
        VStack(spacing: 18) {
            Spacer()

            if !model.isReady {
                ArcadePanel {
                    VStack(spacing: 8) {
                        Text("Nothing unlocked yet")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(ArcadeTheme.amber)
                        Text("Finish a lesson and today's gauntlet has something to draw from.")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(ArcadeTheme.paper.opacity(0.65))
                    }
                }
            } else if let played = model.todaysResult {
                comeBackTomorrow(played)
            } else {
                todaysCard
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var todaysCard: some View {
        VStack(spacing: 16) {
            Text("Today's gauntlet")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(ArcadeTheme.paper)
            Text("Three minutes. Everyone gets the same run today. Speed counts here.")
                .font(ArcadeTheme.mono)
                .foregroundStyle(ArcadeTheme.paper.opacity(0.6))

            ArcadePanel {
                HStack(spacing: 28) {
                    statTile("drills", "\(model.todaysGauntlet.count)", ArcadeTheme.cyan)
                    statTile(
                        "clock",
                        ArcadeTheme.clockText(ArcadeRun.defaultTimeLimit),
                        ArcadeTheme.amber
                    )
                    if let best = model.leaderboard.bestScore {
                        statTile("your best", "\(best)", ArcadeTheme.leaf)
                    }
                }
            }

            Button { model.startDailyRun() } label: {
                HStack(spacing: 8) {
                    Text("Start the run")
                    Keycap(label: "⏎")
                }
                .font(ArcadeTheme.mono)
            }
            .buttonStyle(.borderedProminent)
            .tint(ArcadeTheme.amber)
        }
    }

    private func comeBackTomorrow(_ result: ArcadeRunResult) -> some View {
        VStack(spacing: 16) {
            Text("\(result.score)")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(ArcadeTheme.amber)
            Text("today's run is in the books")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(ArcadeTheme.paper.opacity(0.55))

            ArcadePanel {
                VStack(spacing: 8) {
                    Text("Come back tomorrow for a new gauntlet.")
                        .font(ArcadeTheme.mono)
                        .foregroundStyle(ArcadeTheme.paper.opacity(0.85))
                    Text("You can replay today's run as practice — it just won't be scored.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ArcadeTheme.paper.opacity(0.55))
                }
            }

            HStack(spacing: 14) {
                Button { model.startDailyRun() } label: {
                    HStack(spacing: 8) {
                        Text("See today's result")
                        Keycap(label: "⏎")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArcadeTheme.cyan)
                Button { model.startPracticeRun() } label: {
                    HStack(spacing: 8) {
                        Text("Practise the run")
                        Keycap(label: "p")
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(ArcadeTheme.mono)
        }
    }

    private func statTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ArcadeTheme.paper.opacity(0.5))
        }
    }

    // MARK: - Running

    @ViewBuilder
    private var runStage: some View {
        if let drill = model.currentDrill, let session = model.session, let editor = model.editor {
            VStack(spacing: 12) {
                hud(session)
                instructionBar(drill)

                EditorView(
                    session: editor,
                    filter: keyboard.engineFilter(
                        mode: { .engine },
                        map: { SurfaceKeys.arcadeRunning },
                        onAction: navigate
                    )
                )
                    .id(model.editorGeneration)
                    .frame(minHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(ArcadeTheme.paper.opacity(0.08), lineWidth: 1)
                    )

                feedbackStrip
                footerControls(session)
            }
            .padding(18)
            .juice(juice)
            // A fresh editor arrives with every drill; re-chain onto its hook.
            .task(id: model.editorGeneration) { juice.attach(to: editor) }
            // Every clear gets its own celebration on top of the engine's own
            // graded juice — this is the surface where loud is correct.
            .onChange(of: model.hitPulse) {
                guard let hit = model.lastHit else { return }
                juice.emit(
                    JuiceEvent(
                        tier: hit.isFlawless ? .burst : .pop,
                        intensity: 0.55 + 0.45 * ArcadeTheme.comboHeat(hit.comboLength)
                    )
                )
            }
        } else {
            ProgressView().tint(ArcadeTheme.cyan)
        }
    }

    private func hud(_ session: ArcadeRunSession) -> some View {
        // `displayNow` is unused as a value but drives the redraw — the session
        // reads the real clock, so the view needs a heartbeat to re-render.
        let _ = displayNow
        let remaining = session.remaining
        let fraction = session.timeLimit > 0 ? remaining / session.timeLimit : 0
        let tint = ArcadeTheme.clockTint(remainingFraction: fraction)

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(ArcadeTheme.clockText(remaining))
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .monospacedDigit()

                comboBadge(session.combo)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(session.score)")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(ArcadeTheme.paper)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: session.score)
                    Text("\(session.drillsCleared) of \(session.drills.count) cleared")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ArcadeTheme.paper.opacity(0.45))
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ArcadeTheme.paper.opacity(0.10))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.1), value: fraction)
        }
        .overlay(alignment: .topTrailing) { scorePop }
    }

    @ViewBuilder
    private var scorePop: some View {
        if let hit = model.lastHit {
            Text("+\(hit.points)")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(hit.isFlawless ? ArcadeTheme.leaf : ArcadeTheme.amber)
                .id(model.hitPulse)
                .transition(.move(edge: .top).combined(with: .opacity))
                .offset(y: -22)
                .animation(.spring(duration: 0.35), value: model.hitPulse)
        }
    }

    private func comboBadge(_ combo: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
            Text("×\(max(1, combo))")
                .monospacedDigit()
        }
        .font(.system(.callout, design: .monospaced).weight(.semibold))
        .foregroundStyle(ArcadeTheme.comboTint(combo))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            ArcadeTheme.comboTint(combo).opacity(0.12),
            in: Capsule()
        )
        .scaleEffect(1 + 0.12 * ArcadeTheme.comboHeat(combo))
        .animation(.spring(duration: 0.3), value: combo)
    }

    private func instructionBar(_ drill: Drill) -> some View {
        ArcadePanel(padding: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "bolt.fill").foregroundStyle(ArcadeTheme.amber)
                Text(drill.instruction)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(ArcadeTheme.paper)
                Spacer(minLength: 0)
                Text(drill.documentName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ArcadeTheme.paper.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private var feedbackStrip: some View {
        switch model.feedback {
        case .none:
            feedbackRow(icon: "keyboard", tint: ArcadeTheme.paper.opacity(0.3), text: "Go.")
        case .correct:
            feedbackRow(icon: "checkmark.circle.fill", tint: ArcadeTheme.leaf, text: "Clean.")
        case .nearMiss(let miss):
            feedbackRow(icon: "arrow.triangle.branch", tint: ArcadeTheme.amber, text: miss.feedback)
        case .incorrect(let hint):
            feedbackRow(icon: "arrow.counterclockwise", tint: ArcadeTheme.coral, text: hint)
        }
    }

    private func feedbackRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(ArcadeTheme.mono)
                .foregroundStyle(ArcadeTheme.paper.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.15), value: model.feedback)
    }

    /// ⌘-keyed, not plain-keyed: the run is an ENGINE surface, so a bare `j`
    /// has to reach the buffer. ⌘ is the one channel the engine never sees.
    private func footerControls(_ session: ArcadeRunSession) -> some View {
        HStack(spacing: 14) {
            runControl("Skip", "⌘J", "j") { model.skipDrill() }
            Spacer()
            if !session.isScored {
                Text("practice — not scored")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(ArcadeTheme.cyan.opacity(0.8))
            }
            runControl("End run", "⌘E", "e") { model.endRun() }
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(ArcadeTheme.paper.opacity(0.6))
    }

    private func runControl(
        _ title: String, _ cap: String, _ shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Keycap(label: cap)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
    }
}
