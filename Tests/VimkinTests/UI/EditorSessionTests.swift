import Testing
@testable import Vimkin

@Suite("EditorSession: engine plumbing + event publishing")
struct EditorSessionTests {
    @Test func feedXInNormalModeMutatesBufferAndEmitsEvent() {
        let session = EditorSession(text: "hello")
        var published: [CommandEvent] = []
        session.onEvents = { published += $0 }

        let events = session.feed(.char("x"))

        #expect(session.buffer.text == "ello")
        #expect(events.count == 1)
        #expect(events[0].verb == .deleteChar)
        #expect(events[0].category == .action)
        #expect(published == events)
    }

    @Test func modeSwitchesAreReflected() {
        let session = EditorSession(text: "abc")
        #expect(session.mode == .normal)

        session.feed(.char("i"))
        #expect(session.mode == .insert)

        session.feed(.escape)
        #expect(session.mode == .normal)

        session.feed(.char("v"))
        #expect(session.mode == .visual)

        session.feed(.escape)
        session.feed(.char("d"))
        #expect(session.mode == .operatorPending)

        session.feed(.escape)
        session.feed(.char(":"))
        #expect(session.mode == .commandLine)
        session.feed(.char("w"))
        #expect(session.commandLine == "w")
    }

    @Test func onEventsFiresOnlyWhenEventsAreEmitted() {
        let session = EditorSession(text: "one two")
        var callCount = 0
        session.onEvents = { _ in callCount += 1 }

        session.feed(.char("d"))   // pending operator: no events
        #expect(callCount == 0)

        session.feed(.char("w"))   // dw completes: one batch
        #expect(callCount == 1)
        #expect(session.buffer.text == "two")
    }

    @Test func feedKeysStringConvenience() {
        let session = EditorSession(text: "say \"hi there\" now")
        session.feed(keys: "fhdi\"")
        #expect(session.buffer.text == "say \"\" now")
    }

    @Test func selectionExposedInVisualModeInclusiveBothOrders() {
        let session = EditorSession(text: "abcdef")
        #expect(session.selection == nil)

        session.feed(keys: "llv")          // anchor at col 2
        session.feed(keys: "ll")           // cursor at col 4
        let forward = session.selection
        #expect(forward?.lowerBound == Position(line: 0, col: 2))
        #expect(forward?.upperBound == Position(line: 0, col: 4))

        session.feed(keys: "hhhh")         // cursor at col 0, before anchor
        let backward = session.selection
        #expect(backward?.lowerBound == Position(line: 0, col: 0))
        #expect(backward?.upperBound == Position(line: 0, col: 2))

        session.feed(.escape)
        #expect(session.selection == nil)
    }

    @Test func languageDerivedFromDocumentName() {
        #expect(EditorSession(text: "", documentName: "notes.md").language == .markdown)
        #expect(EditorSession(text: "", documentName: "api.json").language == .json)
        #expect(EditorSession(text: "", documentName: "config.yaml").language == .yaml)
        #expect(EditorSession(text: "", documentName: "plain.txt").language == .plain)
        #expect(EditorSession(text: "").language == .plain)
    }

    @Test func insertModeCursorMaySitOnePastLineEnd() {
        // The known engine quirk the renderer must handle: `A` on "ab" puts the
        // bar cursor at col == lineLength (2).
        let session = EditorSession(text: "ab")
        session.feed(.char("A"))
        #expect(session.mode == .insert)
        #expect(session.cursor == Position(line: 0, col: 2))
        #expect(session.cursor.col == session.buffer.lineLength(0))
    }
}
