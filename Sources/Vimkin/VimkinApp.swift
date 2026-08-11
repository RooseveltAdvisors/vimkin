import SwiftUI

@main
struct VimkinApp: App {
    var body: some Scene {
        WindowGroup("Vimkin") {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    var body: some View {
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
            }
        }
    }
}
