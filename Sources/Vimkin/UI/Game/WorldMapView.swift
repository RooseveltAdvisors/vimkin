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
    /// U21 — the one-screen "how this works", first visit only.
    @State private var firstRun = FirstRunStore()
    @State private var showGuide = false
    /// Why a locked page did not open. Before U21 pressing `⏎` on a locked
    /// card did nothing at all and said nothing at all.
    @State private var lockedNote: String?
    @State private var lockedNoteID = 0
    /// Keyboard shell (U18): the ten pages are one `hjkl` grid.
    @State private var keyboard = KeyboardSurfaceModel()
    @State private var cursor = ListCursor(count: 0, columns: AdventureView.columns)

    /// The grid is a FIXED three columns, not `.adaptive`.
    ///
    /// This is load-bearing for the keyboard, not a cosmetic choice: `l` must
    /// move the selection to the card the player SEES to the right, so the
    /// cursor's column count and the layout's column count have to be the same
    /// number. An adaptive grid re-flows with the window, and the moment it
    /// does, `j` starts skipping cards. One constant, used by both.
    /// `nonisolated` so the cursor arithmetic can be asserted from a plain test
    /// context — a `View` is `@MainActor`, and an immutable `Int` needs none of
    /// that isolation.
    public nonisolated static let columns = 3

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
            showGuide = firstRun.shouldShowGuide(for: .adventure)
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 16),
                                    count: Self.columns
                                ),
                                spacing: 16
                            ) {
                                ForEach(world?.levels ?? []) { level in
                                    card(for: level).id(level.id)
                                }
                            }
                            .padding(24)
                        }
                        .onChange(of: cursor.index) { _, index in
                            guard let levels = world?.levels, levels.indices.contains(index)
                            else { return }
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(levels[index].id, anchor: .center)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let lockedNote {
                VStack {
                    Spacer()
                    lockedBar(lockedNote)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                }
                .allowsHitTesting(false)
            }
            if showGuide {
                FirstRunGuideView(guide: ModeGuide.guide(for: .adventure)) { dismissGuide() }
            }
        }
        .animation(.easeOut(duration: 0.18), value: lockedNote)
        .keyboardSurface(keyboard, map: SurfaceKeys.worldMap, onAction: handle)
        .onChange(of: world?.levels.count ?? 0) { _, count in cursor.setCount(count) }
        .task(id: world?.levels.count ?? 0) { cursor.setCount(world?.levels.count ?? 0) }
    }

    // MARK: - Keyboard

    private func handle(_ action: NavAction) {
        // The guide owns no keys of its own: while it is up, ANY navigation
        // key means "got it". One less thing competing for the keyboard.
        if showGuide {
            dismissGuide()
            return
        }
        if cursor.apply(action) { return }
        switch action {
        case .activate:
            guard let world, world.levels.indices.contains(cursor.index) else { return }
            let level = world.levels[cursor.index]
            // Locked pages stay reachable by the cursor so `j` never skips a
            // gap in the grid — they just do not open. They DO say why: a
            // dead key with no explanation reads as a broken app.
            if results.isUnlocked(level: level, in: world) {
                playing = level
                lockedNote = nil
            } else {
                showLockedNote(for: level, in: world)
            }
        case .back:
            onExit()
        default:
            break
        }
    }

    private func dismissGuide() {
        showGuide = false
        firstRun.markSeen(.adventure)
    }

    private func showLockedNote(for level: Level, in world: LevelDatabase) {
        let previous = world.level(order: level.order - 1)?.title
        lockedNote = previous.map { "\(level.title) is still locked — clear \($0) first." }
            ?? "\(level.title) is still locked."
        lockedNoteID += 1
        let id = lockedNoteID
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if id == lockedNoteID { lockedNote = nil }
        }
    }

    private func lockedBar(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .foregroundStyle(GameTheme.vimkinAmber.opacity(0.9))
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
                .stroke(GameTheme.vimkinAmber.opacity(0.4), lineWidth: 1)
        )
        .transition(.opacity)
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
            Button(action: onExit) {
                HStack(spacing: 6) {
                    Text("Hub")
                        .font(.system(.body, design: .monospaced))
                    Keycap(label: "Esc")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(GameTheme.parchment.opacity(0.7))
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
        let selected = world?.levels.indices.contains(cursor.index) == true
            && world?.levels[cursor.index].id == level.id

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
                // Naked numbers beside an icon ("3 ✦ · 20/26 ⌨") told a
                // first-timer nothing. Both stats now say what they count.
                HStack(spacing: 10) {
                    Label("\(level.vimkins.count) vimkins", systemImage: "sparkles")
                        .foregroundStyle(GameTheme.vimkinAmber.opacity(unlocked ? 0.85 : 0.3))
                    if let best = result?.bestKeystrokes, cleared {
                        Label("best \(best) · par \(level.par)", systemImage: "keyboard")
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
            .navSelected(selected, radius: 14)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}
