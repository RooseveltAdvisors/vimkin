import AppKit
import SwiftUI

/// Owns the lookup panel's lifecycle: show/hide/toggle, screen-change
/// reposition, and the "practice this" hand-off to the dojo (a
/// NotificationCenter post the dojo subscribes to later).
///
/// The panel is created lazily so the controller's non-UI surface (the
/// practice notification) is unit-testable without touching AppKit windows.
@MainActor
final class OverlayController {
    /// Posted when the user picks "Practice this" on a lookup result.
    /// `object` is the command id (`String`), e.g. `"grammar.delete-inside-quotes"`.
    nonisolated static let practiceCommandNotification = Notification.Name("vimkin.practiceCommand")

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

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }

        let searchView = OverlaySearchView(
            database: database,
            onPractice: { [weak self] id in self?.practiceCommand(id: id) },
            onDismiss: { [weak self] in self?.hide() }
        )
        let panel = OverlayPanel(content: searchView)
        panel.onDismiss = { [weak self] in self?.hide() }
        self.panel = panel
        return panel
    }
}
