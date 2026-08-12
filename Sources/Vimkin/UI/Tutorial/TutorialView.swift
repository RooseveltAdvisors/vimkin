// TutorialView.swift — the learning path (plan U5): every lesson grouped by
// curriculum stage, with lock and mastery state read from the ProgressStore.
//
// Ethical gamification (plan R7): the header reports a TREND ("practised 12 of
// the last 40 days") rather than a streak you can lose, locked rows say what
// opens them instead of dangling a reward, and nothing here is timed.

import SwiftUI

public struct TutorialView: View {
    private let store: ProgressStore
    private let onBack: () -> Void

    @State private var progress: TutorialProgress?
    @State private var loadError: String?
    @State private var openLesson: Lesson?
    /// Bumped when a lesson closes so the path re-reads the store.
    @State private var revision = 0
    /// Keyboard shell (U15): the path is one long j/k list across all stages.
    @State private var keyboard = KeyboardSurfaceModel()
    @State private var cursor = ListCursor(count: 0)
    /// U21 — the one-screen "how this works", first visit only.
    @State private var firstRun = FirstRunStore()
    @State private var showGuide = false

    public init(store: ProgressStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            TutorialTheme.background.ignoresSafeArea()
            if let lesson = openLesson {
                LessonView(lesson: lesson, store: store) {
                    openLesson = nil
                    revision += 1
                }
            } else {
                path
            }
            if showGuide, openLesson == nil {
                FirstRunGuideView(guide: ModeGuide.guide(for: .lessons)) { dismissGuide() }
            }
        }
        .task { showGuide = firstRun.shouldShowGuide(for: .lessons) }
    }

    private func dismissGuide() {
        showGuide = false
        firstRun.markSeen(.lessons)
    }

    // MARK: - Path

    private var path: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(TutorialTheme.hairline)
            if let progress {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            ForEach(progress.database.tiers, id: \.self) { tier in
                                stage(tier: tier, progress: progress)
                            }
                        }
                        .padding(28)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: cursor.index) { _, index in
                        guard ordered.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(ordered[index].id, anchor: .center)
                        }
                    }
                }
            } else {
                Text(loadError ?? "loading lessons…")
                    .font(TutorialTheme.mono)
                    .foregroundStyle(TutorialTheme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .keyboardSurface(keyboard, map: SurfaceKeys.lessonPath, onAction: handle)
        .onChange(of: ordered.count) { _, count in cursor.setCount(count) }
    }

    // MARK: - Keyboard

    /// The path as the keyboard sees it: every lesson, in stage order, one flat
    /// list — so `j` walks off the bottom of Stage 1 into the top of Stage 2.
    private var ordered: [Lesson] {
        guard let progress else { return [] }
        return progress.database.tiers.flatMap { progress.database.lessons(tier: $0) }
    }

    private func handle(_ action: NavAction) {
        // While the guide is up, any navigation key means "got it".
        if showGuide {
            dismissGuide()
            return
        }
        if cursor.apply(action) { return }
        switch action {
        case .activate:
            guard let progress, ordered.indices.contains(cursor.index) else { return }
            let lesson = ordered[cursor.index]
            if progress.isUnlocked(lesson, in: store) { openLesson = lesson }
        case .back:
            onBack()
        default:
            break
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Button(action: onBack) {
                Text("← Vimkin").font(TutorialTheme.mono)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TutorialTheme.dim)
            .keyboardShortcut("l", modifiers: .command)

            Text("Learn")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(TutorialTheme.paper)

            Spacer()

            if let progress {
                let done = progress.completedCount(in: store)
                Text("\(done) of \(progress.lessonCount) lessons")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(TutorialTheme.dim)
            }
            let trend = store.practiceTrend()
            Text("practised \(trend.practicedDays) of the last \(trend.windowDays) days")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(TutorialTheme.faint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .id(revision)
    }

    private func stage(tier: Int, progress: TutorialProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TutorialTheme.tierLabel(tier).uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(TutorialTheme.vimkin.opacity(0.85))
                .tracking(1.2)
            ForEach(progress.database.lessons(tier: tier)) { lesson in
                row(lesson: lesson, progress: progress)
                    .id(lesson.id)
            }
        }
    }

    private func row(lesson: Lesson, progress: TutorialProgress) -> some View {
        let unlocked = progress.isUnlocked(lesson, in: store)
        let complete = progress.isComplete(lesson, in: store)
        let mastery = progress.masteryState(lesson, in: store)
        let selected = ordered.indices.contains(cursor.index)
            && ordered[cursor.index].id == lesson.id

        return Button {
            if unlocked { openLesson = lesson }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                marker(complete: complete, unlocked: unlocked)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(lesson.title)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(unlocked ? TutorialTheme.paper : TutorialTheme.faint)
                        if complete, let label = TutorialTheme.masteryLabel(mastery) {
                            Text(label)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(TutorialTheme.masteryColor(mastery))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    TutorialTheme.masteryColor(mastery).opacity(0.14),
                                    in: Capsule()
                                )
                        }
                    }
                    Text(unlocked ? teaseLine(lesson) : "opens when you finish the lesson above")
                        .font(.system(size: 12))
                        .foregroundStyle(unlocked ? TutorialTheme.dim : TutorialTheme.faint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(keysPreview(lesson))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(unlocked ? TutorialTheme.glow.opacity(0.75) : TutorialTheme.faint)
            }
            .padding(14)
            .background(TutorialTheme.panel.opacity(unlocked ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(complete ? TutorialTheme.success.opacity(0.35) : TutorialTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .navSelected(selected)
        }
        .buttonStyle(.plain)
        // Locked rows stay reachable by the cursor (so `j` never skips a gap)
        // but the click target is off, exactly as before.
        .disabled(!unlocked)
    }

    private func marker(complete: Bool, unlocked: Bool) -> some View {
        ZStack {
            Circle()
                .fill(complete ? TutorialTheme.success.opacity(0.18) : TutorialTheme.glow.opacity(unlocked ? 0.12 : 0.05))
                .frame(width: 26, height: 26)
            Text(complete ? "✓" : (unlocked ? "▸" : "•"))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    complete ? TutorialTheme.success : (unlocked ? TutorialTheme.glow : TutorialTheme.faint)
                )
        }
    }

    /// First sentence of the concept card — enough to know what the lesson is for.
    private func teaseLine(_ lesson: Lesson) -> String {
        let plain = lesson.concept.replacingOccurrences(of: "`", with: "")
        guard let dot = plain.firstIndex(of: ".") else { return plain }
        return String(plain[...dot])
    }

    private func keysPreview(_ lesson: Lesson) -> String {
        Array(Set(lesson.steps.map(\.canonicalKeys)))
            .sorted()
            .prefix(3)
            .map { $0.replacingOccurrences(of: "\u{1B}", with: "Esc").replacingOccurrences(of: "\n", with: "⏎") }
            .joined(separator: "  ")
    }

    private func load() {
        guard progress == nil else { return }
        do {
            progress = TutorialProgress(database: try LessonDatabase.load())
        } catch {
            loadError = "could not load lessons: \(error)"
        }
    }
}
