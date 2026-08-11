import SwiftUI
import Carbon.HIToolbox

// Harvested from vimhint's HotkeyRecorder.swift (MIT), adapted to Vimkin's
// HotkeyShortcut type and dark-cozy styling. Local NSEvent monitor swallows
// keystrokes while recording (returns nil); Escape cancels; the monitor is
// removed on disappear.

struct HotkeyRecorder: View {
    @Binding var shortcut: HotkeyShortcut?

    @State private var isRecording = false
    @State private var localMonitor: Any?

    private var title: String {
        if isRecording {
            return "Press shortcut..."
        }
        return shortcut?.displayString ?? "Record shortcut"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(OverlayStyle.paper)

            Spacer(minLength: 0)

            Button(isRecording ? "Stop" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(OverlayStyle.accent.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            OverlayStyle.background.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard localMonitor == nil else { return }
        HotkeyManager.shared.beginShortcutRecording()
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            if let newShortcut = HotkeyShortcut.from(event: event) {
                shortcut = newShortcut
                stopRecording()
                return nil
            }

            return nil
        }
    }

    private func stopRecording() {
        let wasRecording = isRecording

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRecording = false

        if wasRecording {
            HotkeyManager.shared.endShortcutRecording()
        }
    }
}
