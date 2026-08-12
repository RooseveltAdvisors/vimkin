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

import SwiftUI

public struct LessonView: View {
    private let onExit: () -> Void
    @State private var coordinator: LessonCoordinator
    /// Graded game-feel (plan U8): the reward tier is keyed off the command's
    /// own complexity, so the grammar step of a lesson lands hardest.
    @State private var juice = JuiceConductor(audio: JuiceAudio())
    /// Keyboard shell (U15). The concept card and the "learned" card are chrome;
    /// the practice beat between them belongs entirely to the VimEngine.
    @State private var keyboard = KeyboardSurfaceModel()

    public init(lesson: Lesson, store: ProgressStore?, onExit: @escaping () -> Void) {
        self.onExit = onExit
        _coordinator = State(initialValue: LessonCoordinator(lesson: lesson, store: store))
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
    private var repMeter: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< max(coordinator.repsRequired, 1), id: \.self) { index in
                Circle()
                    .fill(index < coordinator.repsCompleted ? TutorialTheme.success : TutorialTheme.faint)
                    .frame(width: 8, height: 8)
            }
        }
        .animation(.easeOut(duration: 0.18), value: coordinator.repsCompleted)
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
            EditorView(
                session: coordinator.session,
                // The chrome's router sits IN FRONT of the lesson judge, so a
                // second Esc leaves without the judge ever seeing the key —
                // and every other key still reaches the lesson unchanged.
                filter: keyboard.engineFilter(
                    mode: { .engine },
                    map: { SurfaceKeys.lessonPractice },
                    base: coordinator.handle(key:),
                    onAction: navigate
                )
            )
            .id(coordinator.attemptID)
            feedbackBar
        }
        .juice(juice)
        // Every attempt builds a fresh session; re-chain onto its event hook.
        .task(id: coordinator.attemptID) { juice.attach(to: coordinator.session) }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(TutorialTheme.panel)
    }

    private var feedbackBar: some View {
        HStack(spacing: 8) {
            switch coordinator.feedback {
            case .correct(let message):
                Text("✓").foregroundStyle(TutorialTheme.success)
                Text(message)
                    .font(.system(size: 13, design: .monospaced))
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
        .onAppear { juice.emit(JuiceEvent(tier: .burst, intensity: 1)) }
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
