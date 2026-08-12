import Foundation
import Testing
@testable import Vimkin

@Suite("Overlay lookup: search-to-result over the real command database", .tags(.integration))
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
}
