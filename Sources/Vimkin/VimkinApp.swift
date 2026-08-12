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
    @State private var showPlayground = false
    // U6 (dojo): sheet + the lookup overlay's "Practice this →" hand-off.
    @State private var showDojo = false
    @State private var practiceCommandID: String?

    var body: some View {
        if showPlayground {
            PlaygroundView(onBack: { showPlayground = false })
        } else {
            titleScreen
        }
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
                Button("Playground") { showPlayground = true }
                    .buttonStyle(.borderedProminent)
                    .font(.system(.body, design: .monospaced))
                    .padding(.top, 24)
                Button("Practice") { showDojo = true }
                    .buttonStyle(.bordered)
                    .font(.system(.body, design: .monospaced))
            }
        }
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
