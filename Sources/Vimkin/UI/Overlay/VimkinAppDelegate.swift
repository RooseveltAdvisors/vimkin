import AppKit

/// App delegate bridged in via `@NSApplicationDelegateAdaptor`: owns the
/// lookup overlay + global summon hotkey without touching the main
/// WindowGroup's UX. Default shortcut Cmd+Shift+V when none is stored
/// (applied inside HotkeyManager's load path).
final class VimkinAppDelegate: NSObject, NSApplicationDelegate {
    private(set) var overlayController: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let database = (try? CommandDatabase.load()) ?? CommandDatabase(commands: [])
        let controller = OverlayController(database: database)
        overlayController = controller

        HotkeyManager.shared.onTrigger { [weak controller] in
            controller?.toggle()
        }
    }
}
