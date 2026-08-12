import AppKit
import SwiftUI

/// Owns the launcher panel's lifecycle: show/hide/toggle, screen-change
/// reposition, the "practice this" hand-off to the dojo, and (U20) the
/// "open this surface" hand-off to the main window — both NotificationCenter
/// posts the shell subscribes to.
///
/// The panel is created lazily so the controller's non-UI surface (the two
/// notifications) is unit-testable without touching AppKit windows.
@MainActor
final class OverlayController {
    /// Posted when the user picks "Practice this" on a lookup result.
    /// `object` is the command id (`String`), e.g. `"grammar.delete-inside-quotes"`.
    nonisolated static let practiceCommandNotification = Notification.Name("vimkin.practiceCommand")

    /// Posted when a launcher mnemonic opens an app surface (U20).
    /// `object` is a hub verb (`String`) — `Hub.Verb.adventure`, `…lessons`, …
    ///
    /// The launcher is the front door, so this is how it reaches the main
    /// window. It reuses the practice-notification precedent rather than
    /// inventing a second mechanism.
    nonisolated static let openSurfaceNotification = Notification.Name("vimkin.openSurface")

    private let database: CommandDatabase
    private var panel: OverlayPanel?
    // nonisolated(unsafe): only written once in init and read in deinit;
    // NotificationCenter observer tokens are thread-safe to remove.
    nonisolated(unsafe) private var screenObserver: (any NSObjectProtocol)?

    init(database: CommandDatabase) {
        self.database = database

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.reposition()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    var isVisible: Bool { panel?.isShown ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = ensurePanel()
        panel.show()
        // Nonactivating panel: takes key status for typing without activating
        // the app or stealing focus from the frontmost app's window.
        panel.makeKey()
    }

    func hide() {
        panel?.hide()
    }

    /// The "Practice this →" affordance: posts the practice notification with
    /// the command id and dismisses the panel. The dojo subscribes later.
    func practiceCommand(id: String) {
        NotificationCenter.default.post(name: Self.practiceCommandNotification, object: id)
        hide()
    }

    /// Announce that a surface should open, without touching any window.
    ///
    /// Split out from `openSurface(verb:)` so the contract the shell listens
    /// on is provable in a test process that has no windows to raise.
    func requestSurface(verb: String) {
        NotificationCenter.default.post(name: Self.openSurfaceNotification, object: verb)
    }

    /// A launcher mnemonic: tell the shell where to go, bring Vimkin forward,
    /// and get out of the way.
    ///
    /// This is the ONE path that activates the app. Summoning and searching
    /// deliberately do not — the panel is `.nonactivatingPanel` so a lookup
    /// never steals focus from whatever you were actually working in.
    func openSurface(verb: String) {
        requestSurface(verb: verb)
        hide()
        Self.raiseMainWindow()
    }

    /// Bring the main window forward. The panel is not a candidate: it can
    /// never become main (`OverlayPanel.canBecomeMain` is false).
    private static func raiseMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let main = NSApp.windows.first { $0.canBecomeMain && !($0 is OverlayPanel) }
        main?.makeKeyAndOrderFront(nil)
    }

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }

        let searchView = OverlaySearchView(
            database: database,
            onPractice: { [weak self] id in self?.practiceCommand(id: id) },
            onOpenSurface: { [weak self] verb in self?.openSurface(verb: verb) },
            onDismiss: { [weak self] in self?.hide() }
        )
        let panel = OverlayPanel(content: searchView)
        panel.onDismiss = { [weak self] in self?.hide() }
        self.panel = panel
        return panel
    }
}
