import Testing
@testable import Vimkin

// Verification (plan U2): a scripted replay of a vimtutor-style edit sequence
// produces a byte-identical buffer to the expected fixture.

@Suite struct FixtureReplayTests {
    @Test func vimtutorStyleEditSession() {
        var engine = VimEngine(text: """
        # Notes
        - itme one
        - item two

        say "hello" there
        """)

        // j w        — down to the typo line, onto "itme"
        // cw item Esc — fix the typo (cw acts like ce)
        // j dd       — delete the duplicate item line
        // G fh ci" goodbye Esc — replace the quoted string on the last line
        // gg p       — paste the deleted line below line 1 (linewise)
        // u          — undo the paste
        engine.feed(keys: "jwcwitem\u{1B}jddGfhci\"goodbye\u{1B}ggpu")

        #expect(engine.buffer.text == """
        # Notes
        - item one

        say "goodbye" there
        """)
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(engine.mode == .normal)
    }

    @Test func replayEmitsExpectedEventStream() {
        var engine = VimEngine(text: "one two\nthree")
        let events = engine.feed(keys: "wdw2ddu")
        // w → move; dw → delete word; 2dd → delete 2 lines; u → undo
        let verbs = events.map(\.verb)
        #expect(verbs == [.move, .delete, .delete, .undo])
        let categories = events.map(\.category)
        #expect(categories == [.singleMotion, .operatorMotion, .operatorMotion, .action])
    }
}
