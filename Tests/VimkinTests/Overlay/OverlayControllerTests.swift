import Foundation
import Testing
@testable import Vimkin

/// The overlay controller's outward contract: the notification the dojo screen
/// listens on, and the exact name string that contract is spelled with.
/// (The overlay's search path over the real database is pinned by
/// `OverlayLookupTests` — integration tier.)
@Suite("Overlay controller: the \"Practice this →\" notification contract", .tags(.acceptance))
struct OverlayControllerTests {

    /// Cross-thread capture box for the notification observer closure.
    private final class ReceivedBox: @unchecked Sendable {
        var objects: [Any?] = []
    }

    @Test("practiceCommand posts vimkin.practiceCommand with the command id as object")
    @MainActor
    func practiceNotificationCarriesCommandID() {
        let controller = OverlayController(database: CommandDatabase(commands: []))
        let received = ReceivedBox()

        let token = NotificationCenter.default.addObserver(
            forName: OverlayController.practiceCommandNotification,
            object: nil,
            queue: nil
        ) { note in
            received.objects.append(note.object)
        }
        defer { NotificationCenter.default.removeObserver(token) }

        controller.practiceCommand(id: "grammar.delete-inside-quotes")

        #expect(received.objects.count == 1)
        #expect(received.objects.first as? String == "grammar.delete-inside-quotes")
    }

    @Test("the notification name is the dojo-facing contract string")
    func notificationNameContract() {
        #expect(OverlayController.practiceCommandNotification.rawValue == "vimkin.practiceCommand")
    }
}
