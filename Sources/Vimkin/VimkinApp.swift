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
    /// Where the app currently is. Title screen by default.
    private enum Route {
        case title
        case play
        case learn
        case playground
        /// The date-seeded daily run (U12) — the one scored, timed surface.
        case arcade
        /// The mastery map (U12) — the calm "where do I stand" surface.
        case progress
    }

    @State private var route: Route = .title
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
        case .title:
            titleScreen
        case .play:
            AdventureView(progress: store, onExit: { route = .title })
        case .learn:
            TutorialView(store: store, onBack: { route = .title })
        case .playground:
            PlaygroundView(onBack: { route = .title })
        case .arcade:
            ArcadeView(model: arcadeModel, onClose: { route = .title })
        case .progress:
            MasteryMapView(store: store, database: database, onClose: { route = .title })
        }
    }

    /// Enters the daily run, building its model on first visit.
    private func openArcade() {
        if arcadeModel == nil {
            arcadeModel = ArcadeModel.bundled(store: store, leaderboard: leaderboard)
        }
        route = .arcade
    }

    private var titleScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.15), Color(red: 0.13, green: 0.11, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Vimkin")
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("learn vim. rescue the vimkins.")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 12) {
                    Button("Adventure") { route = .play }
                        .buttonStyle(.borderedProminent)
                    Button("Learn") { route = .learn }
                        .buttonStyle(.bordered)
                    Button("Practice") { showDojo = true }
                        .buttonStyle(.bordered)
                    Button("Daily Run") { openArcade() }
                        .buttonStyle(.bordered)
                    Button("Progress") { route = .progress }
                        .buttonStyle(.bordered)
                    Button("Playground") { route = .playground }
                        .buttonStyle(.bordered)
                }
                .font(.system(.body, design: .monospaced))
                .padding(.top, 24)
            }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Title") { onBack() }
                Picker("Document", selection: $selectedName) {
                    ForEach(documents) { doc in
                        Text(doc.name).tag(doc.name)
                    }
                }
                .frame(maxWidth: 320)
                Spacer()
            }
            .padding(10)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))

            if let session {
                EditorView(session: session)
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
    }

    private func openSelected() {
        guard let doc = documents.first(where: { $0.name == selectedName }) else {
            session = nil
            return
        }
        session = EditorSession(document: doc)
    }
}
