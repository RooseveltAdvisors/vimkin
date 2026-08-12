// DojoView.swift — the Practice Dojo surface (plan U6): calm, adaptive drills
// on real documents.
//
// Deliberately absent from this file: any countdown, timer bar, "hurry",
// streak-loss warning, or harsh red. Accuracy first, speed second (KTD 5) —
// elapsed time appears exactly once, in the summary, phrased as encouragement.

import SwiftUI

public struct DojoView: View {
    @State private var model: DojoModel
    /// Graded game-feel (plan U8): chains onto the drill editor's event hook, so
    /// a `diw` lands harder than a `w` while the drill judging is untouched.
    @State private var juice = JuiceConductor(audio: JuiceAudio())
    /// Key-cap + chord row (plan U19): the same "what did I just press, and is
    /// the engine still waiting for more of it?" surface the lessons use.
    @State private var keys = KeyFeedbackHub()
    /// Command id handed over by the lookup overlay's "Practice this →".
    private let focusCommandID: String?
    private let onClose: () -> Void
    /// Keyboard shell (U18). The dojo is a SHEET, so `Esc` getting back out of
    /// it is the difference between a keyboard app and a focus trap.
    @State private var keyboard = KeyboardSurfaceModel()

    public init(
        focusCommandID: String? = nil,
        model: DojoModel? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model ?? DojoModel.bundled())
        self.focusCommandID = focusCommandID
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [DojoTheme.background, DojoTheme.plum],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(DojoTheme.paper.opacity(0.08))
                content
            }
        }
        .onAppear {
            guard model.phase == .idle else { return }
            if let focusCommandID {
                model.startFocusedSession(commandID: focusCommandID)
            }
        }
        .keyboardSurface(
            keyboard, map: map, mode: mode,
            hasInnerCapture: model.phase == .drilling, onAction: navigate
        )
    }

    // MARK: - Keyboard

    /// Only the drill itself is the engine's; the start card and the summary
    /// either side of it are ordinary menus.
    private var mode: InputMode { model.phase == .drilling ? .engine : .navigation }

    private var map: KeyMap {
        switch model.phase {
        case .idle: return SurfaceKeys.dojoIdle
        case .drilling: return SurfaceKeys.dojoDrilling
        case .summary: return SurfaceKeys.dojoSummary
        }
    }

    private func navigate(_ action: NavAction) {
        switch action {
        case .verb("start"):
            guard !model.generator.eligibleCommandIDs.isEmpty else { return }
            model.startSession()
        case .verb("reset"):
            model.restartDrill()
        case .verb("skip"):
            model.skipDrill()
        case .verb("finish"):
            model.finishEarly()
        case .verb("again"):
            model.startSession()
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
                    Label("Close", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                    Keycap(label: model.phase == .drilling ? "⌘L" : "Esc")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DojoTheme.paper.opacity(0.7))
            .keyboardShortcut("l", modifiers: .command)

            Text("Practice Dojo")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(DojoTheme.paper)

            if let focus = model.focusCommandID {
                Text("focused on \(focus)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DojoTheme.cyan.opacity(0.85))
            }

            Spacer()

            if let drill = model.currentDrill {
                Text(drill.documentName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DojoTheme.paper.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle: startCard
        case .drilling: drillStage
        case .summary: SessionSummaryView(
            summary: model.summary ?? .empty,
            onPracticeAgain: { model.startSession() },
            onDone: { model.reset(); onClose() }
        )
        }
    }

    // MARK: - Idle

    private var startCard: some View {
        let unlocked = model.generator.eligibleCommandIDs
        return VStack(spacing: 18) {
            Spacer()
            Text("A calm set of drills on real documents.")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(DojoTheme.paper)
            Text("No timer. No streak to lose. Get it right, then get it smooth.")
                .font(DojoTheme.mono)
                .foregroundStyle(DojoTheme.paper.opacity(0.6))

            if unlocked.isEmpty {
                DojoPanel {
                    VStack(spacing: 8) {
                        Text("Nothing unlocked yet")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(DojoTheme.amber)
                        Text("Finish a lesson in the tutorial and its command shows up here.")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(DojoTheme.paper.opacity(0.65))
                    }
                }
            } else {
                DojoPanel {
                    VStack(spacing: 6) {
                        Text("\(unlocked.count) skill\(unlocked.count == 1 ? "" : "s") unlocked")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(DojoTheme.cyan)
                        Text("The set leans toward whatever has gone rusty.")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(DojoTheme.paper.opacity(0.65))
                    }
                }
                Button { model.startSession() } label: {
                    HStack(spacing: 8) {
                        Text("Start a set")
                        Keycap(label: "⏎")
                    }
                    .font(DojoTheme.mono)
                }
                .buttonStyle(.borderedProminent)
                .tint(DojoTheme.cyan)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Drilling

    @ViewBuilder
    private var drillStage: some View {
        if let drill = model.currentDrill, let editor = model.editor, let session = model.session {
            VStack(spacing: 14) {
                instructionBar(drill)
                progressDots(session)

                EditorView(
                    session: editor,
                    // The chrome routes first, so `Esc Esc` leaves the set; in
                    // engine mode every key falls through to the drill.
                    filter: keyboard.engineFilter(
                        mode: { .engine },
                        map: { SurfaceKeys.dojoDrilling },
                        onAction: navigate
                    ),
                    feedback: keys
                )
                    .id(model.editorGeneration)
                    .frame(minHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(DojoTheme.paper.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        KeyPressVisualizer(hub: keys).padding(18)
                    }
                    .wobble(trigger: keys.wobble, amplitude: 10)

                feedbackStrip
                footerControls
            }
            .padding(18)
            .juice(juice)
            // A fresh editor arrives with every drill; re-chain onto its hook.
            .task(id: model.editorGeneration) {
                juice.attach(to: editor)
                keys.clearChord()
            }
            .onChange(of: model.feedback) { _, judgement in
                switch judgement {
                case .correct: keys.grade(.right)
                case .nearMiss, .incorrect: keys.grade(.wrong)
                case nil: break
                }
            }
        } else {
            ProgressView().tint(DojoTheme.cyan)
        }
    }

    private func instructionBar(_ drill: Drill) -> some View {
        DojoPanel {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "sparkle")
                    .foregroundStyle(DojoTheme.amber)
                Text(drill.instruction)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(DojoTheme.paper)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }

    private func progressDots(_ session: DrillSession) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(session.dotStates.enumerated()), id: \.offset) { _, state in
                Circle()
                    .fill(DojoTheme.dotColor(state))
                    .frame(width: state == .current ? 11 : 8, height: state == .current ? 11 : 8)
            }
            Spacer()
            Text("\(min(session.index + 1, session.drills.count)) of \(session.drills.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(DojoTheme.paper.opacity(0.45))
        }
        .animation(.easeOut(duration: 0.18), value: session.index)
    }

    @ViewBuilder
    private var feedbackStrip: some View {
        switch model.feedback {
        case .none:
            feedbackRow(
                icon: "keyboard",
                tint: DojoTheme.paper.opacity(0.35),
                text: "Take your time — accuracy first."
            )
        case .correct:
            feedbackRow(icon: "checkmark.circle.fill", tint: DojoTheme.leaf, text: "That's it.")
        case .nearMiss(let miss):
            feedbackRow(icon: "arrow.triangle.branch", tint: DojoTheme.amber, text: miss.feedback)
        case .incorrect(let hint):
            feedbackRow(icon: "arrow.counterclockwise", tint: DojoTheme.coral, text: hint)
        }
    }

    private func feedbackRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(DojoTheme.mono)
                .foregroundStyle(DojoTheme.paper.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.2), value: model.feedback)
    }

    /// Every control here is ⌘-keyed rather than plain-keyed, and that is
    /// forced by the mode rule, not a preference: while a drill is running the
    /// engine owns every ordinary key, so a bare `r` must reach the buffer.
    /// ⌘ combos never reach the engine, which makes them the one safe channel
    /// for chrome mid-drill.
    private var footerControls: some View {
        HStack(spacing: 14) {
            drillControl("Reset this document", "⌘R", "r") { model.restartDrill() }
            drillControl("Skip", "⌘J", "j") { model.skipDrill() }
            Spacer()
            drillControl("Finish set", "⌘E", "e") { model.finishEarly() }
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(DojoTheme.paper.opacity(0.6))
    }

    private func drillControl(
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
