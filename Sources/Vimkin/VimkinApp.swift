import SwiftUI

@main
struct VimkinApp: App {
    // Owns the lookup overlay + global summon hotkey (U10). See UI/Overlay/.
    @NSApplicationDelegateAdaptor(VimkinAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Vimkin") {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    /// Where the app currently is. The hub by default.
    private enum Route {
        case hub
        case play
        case learn
        case playground
        /// The date-seeded daily run (U12) — the one scored, timed surface.
        case arcade
        /// The mastery map (U12) — the calm "where do I stand" surface.
        case progress
    }

    @State private var route: Route = .hub
    /// The local progress spine (U9), shared by every learning surface.
    @State private var store = ProgressStore()
    /// The arcade's own board (U12), deliberately separate from `store`.
    @State private var leaderboard = ArcadeLeaderboardStore()
    /// The command database, loaded once for the whole shell.
    @State private var database = (try? CommandDatabase.load()) ?? CommandDatabase(commands: [])
    /// Built on the way into the arcade, so entering it does not re-read the
    /// bundled corpus on every re-render of the shell.
    @State private var arcadeModel: ArcadeModel?
    // The dojo is a sheet rather than a route: the lookup overlay's
    // "Practice this →" — and the mastery map's rusty-skill rows — can raise it
    // from anywhere in the app.
    @State private var showDojo = false
    @State private var practiceCommandID: String?
    /// The hub's keyboard shell (U18). Every route below owns its own.
    @State private var keyboard = KeyboardSurfaceModel()
    @State private var cursor = ListCursor(count: Hub.jumpKeys.count)
    /// Level results, read on the hub for Adventure's status line and owned
    /// here so the number is fresh when you come back from a level.
    @State private var levelResults = GameProgressStore()
    @State private var levelCount = 0

    var body: some View {
        routeContent
            // Attached HERE rather than to the title screen, so the practice
            // hand-off works from every surface (the mastery map posts it too).
            .sheet(isPresented: $showDojo) {
                DojoView(focusCommandID: practiceCommandID) {
                    showDojo = false
                    practiceCommandID = nil
                }
                .frame(minWidth: 860, minHeight: 620)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: OverlayController.practiceCommandNotification)
            ) { note in
                practiceCommandID = note.object as? String
                showDojo = true
            }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch route {
        case .hub:
            hub
        case .play:
            AdventureView(progress: store, onExit: goHome)
        case .learn:
            TutorialView(store: store, onBack: goHome)
        case .playground:
            PlaygroundView(onBack: goHome)
        case .arcade:
            ArcadeView(model: arcadeModel, onClose: goHome)
        case .progress:
            MasteryMapView(store: store, database: database, onClose: goHome)
        }
    }

    /// Back to the hub, re-reading the level results so Adventure's status line
    /// is right the moment you land (the adventure surface owns its own store).
    private func goHome() {
        levelResults = GameProgressStore()
        route = .hub
    }

    /// Enters the daily run, building its model on first visit.
    private func openArcade() {
        if arcadeModel == nil {
            arcadeModel = ArcadeModel.bundled(store: store, leaderboard: leaderboard)
        }
        route = .arcade
    }

    // MARK: - Hub

    /// The live numbers behind the hub's status lines, read fresh on each draw.
    private var hubStatus: HubStatus {
        let lessons = try? LessonDatabase.load()
        let today = ArcadeDay.key(for: Date())
        return HubStatus(
            levelsCleared: levelResults.state.results.values.filter(\.completed).count,
            levelCount: levelCount,
            todaysScore: leaderboard.result(day: today)?.score,
            lessonsLearned: store.state.completedLessons.count,
            lessonCount: lessons?.lessons.count ?? 0,
            skillsUnlocked: store.unlockedCommands.count,
            practicedDays: store.practiceTrend().practicedDays,
            windowDays: store.practiceTrend().windowDays,
            documentCount: Corpus.documentNames.count
        )
    }

    private var hub: some View {
        let status = hubStatus
        return HubView(status: status, selection: cursor.index) { verb in
            if let index = Hub.entries(status).firstIndex(where: { $0.verb == verb }) {
                cursor.select(index)
            }
            open(verb: verb)
        }
        .keyboardSurface(
            keyboard, map: SurfaceKeys.hub, isActive: !showDojo, onAction: handleHub
        )
        .task {
            guard levelCount == 0 else { return }
            levelCount = (try? LevelDatabase.loadWorld1())?.levels.count ?? 0
        }
    }

    private func handleHub(_ action: NavAction) {
        if cursor.apply(action) { return }
        switch action {
        case .activate:
            let entries = Hub.entries(hubStatus)
            guard entries.indices.contains(cursor.index) else { return }
            open(verb: entries[cursor.index].verb)
        case .verb(let verb):
            if let index = Hub.entries(hubStatus).firstIndex(where: { $0.verb == verb }) {
                cursor.select(index)
            }
            open(verb: verb)
        default:
            break
        }
    }

    /// The single place a hub verb turns into a route. `HubView`'s click path
    /// and the keyboard path both land here, so they can never diverge.
    private func open(verb: String) {
        switch verb {
        case Hub.Verb.adventure: route = .play
        case Hub.Verb.lessons: route = .learn
        case Hub.Verb.practice: showDojo = true
        case Hub.Verb.daily: openArcade()
        case Hub.Verb.progress: route = .progress
        case Hub.Verb.playground: route = .playground
        case Hub.Verb.quit: NSApplication.shared.terminate(nil)
        default: break
        }
    }

}

/// Temporary dev surface (U4 glue): the editor on a corpus document.
/// Replaced by the real Tutorial/Dojo surfaces in U5/U6.
struct PlaygroundView: View {
    let onBack: () -> Void

    @State private var documents: [CorpusDocument] = []
    @State private var selectedName = Corpus.documentNames[0]
    @State private var session: EditorSession?
    /// The playground is a pure ENGINE surface: the editor is always live, so
    /// every plain key is the engine's. Switching documents and leaving ride on
    /// ⌘, which `KeyCaptureView.translate` drops before the engine sees it.
    @State private var keyboard = KeyboardSurfaceModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("← Hub") { onBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(HubTheme.paper.opacity(0.7))
                    .keyboardShortcut("l", modifiers: .command)
                Picker("Document", selection: $selectedName) {
                    ForEach(documents) { doc in
                        Text(doc.name).tag(doc.name)
                    }
                }
                .frame(maxWidth: 320)
                HStack(spacing: 6) {
                    Keycap(label: "⌘J")
                    Keycap(label: "⌘K")
                    Text("switch document")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HubTheme.paper.opacity(0.4))
                }
                Spacer()
            }
            .padding(10)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))

            if let session {
                EditorView(
                    session: session,
                    filter: keyboard.engineFilter(
                        mode: { .engine },
                        map: { SurfaceKeys.playground },
                        onAction: handle
                    )
                )
                .id(selectedName)
            } else {
                Text("corpus failed to load")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            documents = (try? Corpus.loadAll()) ?? []
            openSelected()
        }
        .onChange(of: selectedName) { openSelected() }
        .keyboardSurface(
            keyboard, map: SurfaceKeys.playground, mode: .engine,
            hasInnerCapture: session != nil, onAction: handle
        )
    }

    // MARK: - Keyboard

    private func handle(_ action: NavAction) {
        switch action {
        case .back:
            onBack()
        case .verb("nextDoc"):
            step(by: 1)
        case .verb("prevDoc"):
            step(by: -1)
        default:
            break
        }
    }

    /// Walk the corpus without leaving the home row. Clamps rather than wraps,
    /// the same rule `ListCursor` uses everywhere else in the app.
    private func step(by delta: Int) {
        let names = documents.isEmpty ? Corpus.documentNames : documents.map(\.name)
        guard let current = names.firstIndex(of: selectedName) else { return }
        let next = min(max(current + delta, 0), names.count - 1)
        selectedName = names[next]
    }

    private func openSelected() {
        guard let doc = documents.first(where: { $0.name == selectedName }) else {
            session = nil
            return
        }
        session = EditorSession(document: doc)
    }
}
