// DojoView.swift — the Practice Dojo surface (plan U6): calm, adaptive drills
// on real documents.
//
// Deliberately absent from this file: any countdown, timer bar, "hurry",
// streak-loss warning, or harsh red. Accuracy first, speed second (KTD 5) —
// elapsed time appears exactly once, in the summary, phrased as encouragement.

import SwiftUI

public struct DojoView: View {
    @State private var model: DojoModel
    /// Command id handed over by the lookup overlay's "Practice this →".
    private let focusCommandID: String?
    private let onClose: () -> Void

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
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Label("Close", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DojoTheme.paper.opacity(0.7))

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
                Button("Start a set") { model.startSession() }
                    .buttonStyle(.borderedProminent)
                    .tint(DojoTheme.cyan)
                    .font(DojoTheme.mono)
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

                EditorView(session: editor)
                    .id(model.editorGeneration)
                    .frame(minHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(DojoTheme.paper.opacity(0.08), lineWidth: 1)
                    )

                feedbackStrip
                footerControls
            }
            .padding(18)
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

    private var footerControls: some View {
        HStack(spacing: 14) {
            Button("Reset this document") { model.restartDrill() }
            Button("Skip") { model.skipDrill() }
            Spacer()
            Button("Finish set") { model.finishEarly() }
        }
        .buttonStyle(.plain)
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(DojoTheme.paper.opacity(0.6))
    }
}
