import Foundation
import Testing
@testable import Vimkin

@Suite("Overlay lookup: search-to-result integration + practice notification")
struct OverlayLookupTests {

    // MARK: Search-to-result integration (the overlay's search path is
    // CommandDatabase.search verbatim — these pin the two canonical queries
    // from the U10 spec against the real bundled database).

    @Test("query \"delete inside quotes\" returns the di\" record first")
    func deleteInsideQuotesFirst() throws {
        let db = try CommandDatabase.load()
        let results = db.search("delete inside quotes")
        #expect(results.first?.id == "grammar.delete-inside-quotes")
        #expect(results.first?.keys == "di\"")
    }

    @Test("query \"go to end of line\" surfaces $ at the top")
    func endOfLineSurfaces() throws {
        let db = try CommandDatabase.load()
        let results = db.search("go to end of line")
        let topIDs = results.prefix(3).map(\.id)
        #expect(topIDs.contains("motion.line-end"), "expected $ in top 3, got \(topIDs)")
        let record = try #require(results.first(where: { $0.id == "motion.line-end" }))
        #expect(record.keys == "$")
    }

    // MARK: Practice notification

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
