// LessonView.swift — one lesson, in three beats (plan U5):
//
//   concept  → ONE idea, grammar-framed, on a card you read before typing
//   practice → the instruction bar + the real editor on the practice document,
//              with a rep meter and gentle inline correction
//   complete → a short "learned" moment naming what just unlocked
//
// Accuracy-first, and never punitive: a wrong key resets the page and offers a
// hint, nothing is timed, no counter ever goes backwards, and the keys can be
// revealed on request instead of being withheld as a difficulty tax.
//
// U19 — practice you can SEE. Three things were invisible before:
//
//   1. what a key DID. Ghost cursors now show, before you commit, where every
//      door of the lesson would land you (`i` here, `A` at the line end, `o` on
//      a new line below); the real cursor then FLIES to the one you chose while
//      the others fade.
//   2. what you PRESSED. A key-cap punches in on every press — cyan when it was
//      right, coral and wobbling when it wasn't — and multi-key commands build
//      a visible chord row (`d` → `di` → `diw`).
//   3. the OUTCOME. The judged page is held on screen for a beat (the editor
//      keeps rendering the session that was just judged, with input closed)
//      so the flight, the mode morph and the burst finish before the document
//      resets under you. Without that hold the page reset instantly and the
//      whole point of the rep was never seen — which is the bug this fixes.

import SwiftUI

public struct LessonView: View {
    private let onExit: () -> Void
    @State private var coordinator: LessonCoordinator
    /// Graded game-feel (plan U8): the reward tier is keyed off the command's
    /// own complexity, so the grammar step of a lesson lands hardest. On this
    /// surface it is driven by REPS (see `LessonCoordinator.onReward`), not by
    /// raw keystrokes — the achievement is getting it right, not typing.
    @State private var juice = JuiceConductor(audio: JuiceAudio())
    /// Keyboard shell (U15). The concept card and the "learned" card are chrome;
    /// the practice beat between them belongs entirely to the VimEngine.
    @State private var keyboard = KeyboardSurfaceModel()

    /// The session currently on screen. Lags `coordinator.session` by the hold
    /// window after a judged attempt, so the outcome is seen before the reset.
    @State private var displayedSession: EditorSession?
    @State private var displayedAttemptID = 0
    @State private var holding = false

    /// How long a judged attempt stays on screen before the page resets.
    private static let holdDuration = UInt64(0.72 * 1_000_000_000)

    public init(lesson: Lesson, store: ProgressStore?, onExit: @escaping () -> Void) {
        self.onExit = onExit
        let preview = (try? LessonDatabase.load())?.preview(lessonID: lesson.id)
        _coordinator = State(
            initialValue: LessonCoordinator(lesson: lesson, store: store, preview: preview)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(TutorialTheme.hairline)
            switch coordinator.phase {
            case .concept: conceptCard
            case .practice: practice
            case .complete: celebration
            }
        }
        .background(TutorialTheme.background)
        .keyboardSurface(
            keyboard, map: map, mode: mode,
            hasInnerCapture: coordinator.phase == .practice, onAction: navigate
        )
    }

    // MARK: - Keyboard

    private var mode: InputMode { coordinator.phase == .practice ? .engine : .navigation }

    private var map: KeyMap {
        switch coordinator.phase {
        case .concept: return SurfaceKeys.lessonConcept
        case .practice: return SurfaceKeys.lessonPractice
        case .complete: return SurfaceKeys.lessonComplete
        }
    }

    private func navigate(_ action: NavAction) {
        switch action {
        case .verb("start"):
            coordinator.begin()
        case .verb("showKeys"):
            coordinator.keysRevealed = true
        case .back:
            onExit()
        default:
            break
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onExit) {
                Text("← Lessons").font(TutorialTheme.mono)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TutorialTheme.dim)
            .keyboardShortcut("l", modifiers: .command)

            Text(coordinator.lesson.title)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(TutorialTheme.paper)

            Spacer()

            if coordinator.phase == .practice {
                Text("step \(coordinator.stepNumber) of \(coordinator.stepCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(TutorialTheme.dim)
                repMeter
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Reps as filled pips. It only ever fills — a miss costs a hint, not a pip.
    /// A freshly earned pip springs up to full size, so the counter is something
    /// you watch happen rather than something you notice later.
    private var repMeter: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< max(coordinator.repsRequired, 1), id: \.self) { index in
                let filled = index < coordinator.repsCompleted
                Circle()
                    .fill(filled ? TutorialTheme.success : TutorialTheme.faint)
                    .frame(width: filled ? 12 : 8, height: filled ? 12 : 8)
                    .shadow(color: TutorialTheme.success.opacity(filled ? 0.7 : 0), radius: 6)
            }
        }
        .frame(height: 14)
        .animation(.spring(response: 0.34, dampingFraction: 0.45), value: coordinator.repsCompleted)
    }

    // MARK: - Concept

    private var conceptCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(TutorialTheme.tierLabel(coordinator.lesson.tier).uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(TutorialTheme.vimkin.opacity(0.85))
                .tracking(1.2)

            Text(coordinator.lesson.title)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(TutorialTheme.paper)

            LessonText(text: coordinator.lesson.concept, font: .system(size: 16), color: TutorialTheme.paper.opacity(0.9))
                .lineSpacing(5)

            HStack(spacing: 8) {
                Text("you'll practise")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(TutorialTheme.dim)
                ForEach(Array(Set(coordinator.lesson.steps.map(\.canonicalKeys))).sorted(), id: \.self) { keys in
                    Keycap(label: displayKeys(keys))
                }
            }

            Button {
                coordinator.begin()
            } label: {
                Text("Start practising  ⏎")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(TutorialTheme.glow.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(TutorialTheme.glow.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(TutorialTheme.glow)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(36)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Practice

    private var practice: some View {
        VStack(spacing: 0) {
            instructionBar
            editorStage
            feedbackBar
        }
        .juice(juice)
        .onAppear {
            displayedSession = coordinator.session
            displayedAttemptID = coordinator.attemptID
            coordinator.onReward = { event in juice.emit(event) }
        }
        .onChange(of: coordinator.attemptID) { _, id in hold(untilAttempt: id) }
    }

    private var editorStage: some View {
        let shown = displayedSession ?? coordinator.session
        return ZStack(alignment: .bottomTrailing) {
            EditorView(
                session: shown,
                filter: { key in
                    // Input closes while the judged outcome is on screen, so an
                    // eager next keystroke cannot cut the animation short.
                    if holding { return .block(reason: "watch what that did") }
                    // Otherwise the chrome's router sits IN FRONT of the lesson
                    // judge: a second Esc leaves without the judge ever seeing
                    // the key, and every other key reaches the lesson unchanged.
                    return keyboard.engineFilter(
                        mode: { .engine },
                        map: { SurfaceKeys.lessonPractice },
                        base: coordinator.handle(key:),
                        onAction: navigate
                    )(key)
                },
                feedback: coordinator.keys,
                ghosts: holding ? [] : coordinator.ghosts
            )
            .id(displayedAttemptID)

            KeyPressVisualizer(hub: coordinator.keys)
                .padding(.horizontal, 22)
                .padding(.bottom, 44)
        }
        .wobble(trigger: coordinator.keys.wobble, amplitude: 10)
    }

    /// Keeps the judged page (and its animation) on screen for a beat, then
    /// swaps in the fresh attempt.
    private func hold(untilAttempt id: Int) {
        holding = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.holdDuration)
            displayedSession = coordinator.session
            displayedAttemptID = id
            holding = false
        }
    }

    private var instructionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let step = coordinator.step {
                LessonText(text: step.instruction, font: .system(size: 15, weight: .medium))
                HStack(spacing: 10) {
                    if coordinator.keysRevealed {
                        Text("press").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(TutorialTheme.dim)
                        Keycap(label: displayKeys(step.canonicalKeys))
                    } else {
                        Button {
                            coordinator.keysRevealed = true
                        } label: {
                            HStack(spacing: 6) {
                                Text("show me the keys")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(TutorialTheme.dim)
                                    .underline()
                                Keycap(label: "⌘K")
                            }
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("k", modifiers: .command)
                    }
                    Spacer()
                }
            }
            ghostLegend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(TutorialTheme.panel)
    }

    /// The one-liner over an outcome preview, while its ghosts are up.
    @ViewBuilder
    private var ghostLegend: some View {
        let ghosts = holding ? [] : coordinator.ghosts
        if !ghosts.isEmpty, let caption = coordinator.preview?.caption {
            GhostLegend(caption: caption, ghosts: ghosts)
                .transition(.opacity)
        }
    }

    private var feedbackBar: some View {
        HStack(spacing: 8) {
            switch coordinator.feedback {
            case .correct(let message):
                Text("✓").foregroundStyle(TutorialTheme.success)
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TutorialTheme.success)
            case .hint(let hint):
                Text("↺").foregroundStyle(TutorialTheme.alarm)
                LessonText(text: hint, font: .system(size: 13), color: TutorialTheme.alarm)
            case .none:
                Text("the page resets after every try — nothing here can break")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(TutorialTheme.faint)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TutorialTheme.panel.opacity(0.7))
        .animation(.easeOut(duration: 0.2), value: coordinator.feedback)
    }

    // MARK: - Complete

    private var celebration: some View {
        VStack(spacing: 18) {
            Text("learned")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(TutorialTheme.success)
            Text(coordinator.lesson.title)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(TutorialTheme.paper)

            VStack(spacing: 8) {
                Text("unlocked")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(TutorialTheme.dim)
                    .tracking(1.2)
                ForEach(unlockedKeys, id: \.self) { keys in
                    Keycap(label: keys)
                }
            }
            .padding(.top, 6)

            Button(action: onExit) {
                Text("Back to lessons  ⏎")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(TutorialTheme.success.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(TutorialTheme.success.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(TutorialTheme.success)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .juice(juice)
        // "learned" is the biggest moment in the tutorial — give it the burst.
        .onAppear { juice.emit(PracticeReward.lessonLearned) }
    }

    /// The keys behind the ids this lesson unlocked, for the celebration list.
    private var unlockedKeys: [String] {
        guard let db = try? CommandDatabase.load() else { return coordinator.lesson.teaches }
        return coordinator.lesson.teaches.map { db.command(id: $0)?.keys ?? $0 }
    }

    private func displayKeys(_ keys: String) -> String {
        keys
            .replacingOccurrences(of: "\u{1B}", with: "Esc")
            .replacingOccurrences(of: "\n", with: " ⏎")
    }
}
