import Testing
@testable import Vimkin

// Batch 2 — word motions (w b e), find motions (f t F T ; ,), counts on motions.
// Behavior references: :h word-motions, :h f, :h t, :h ;, :h ,

@Suite(.tags(.unit)) struct WordMotionTests {
    @Test func wMovesToNextWordStart() {
        var engine = VimEngine(text: "hello world")
        engine.feed("w")
        #expect(engine.cursor == Position(line: 0, col: 6))
    }

    @Test func wTreatsPunctuationAsWord() {
        // vim: "foo.bar" — w from 'f' goes to '.', then to 'b'
        var engine = VimEngine(text: "foo.bar")
        engine.feed("w")
        #expect(engine.cursor == Position(line: 0, col: 3))
        engine.feed("w")
        #expect(engine.cursor == Position(line: 0, col: 4))
    }

    @Test func wCrossesLines() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed("w")
        #expect(engine.cursor == Position(line: 1, col: 0))
    }

    @Test func wStopsOnEmptyLine() {
        // :h w — an empty line is also considered a word
        var engine = VimEngine(text: "one\n\ntwo")
        engine.feed("w")
        #expect(engine.cursor == Position(line: 1, col: 0))
        engine.feed("w")
        #expect(engine.cursor == Position(line: 2, col: 0))
    }

    @Test func wAtEndOfBufferStaysOnLastChar() {
        var engine = VimEngine(text: "hello")
        engine.feed("w")
        #expect(engine.cursor == Position(line: 0, col: 4))
    }

    @Test func bMovesToWordStart() {
        var engine = VimEngine(text: "hello world")
        engine.feed("$")
        engine.feed("b")
        #expect(engine.cursor == Position(line: 0, col: 6))
        engine.feed("b")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func bFromMiddleOfWordGoesToItsStart() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "ll")  // col 2, middle of "hello"
        engine.feed("b")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func bCrossesLinesBackward() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "j")
        engine.feed("b")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func eMovesToWordEnd() {
        var engine = VimEngine(text: "hello world")
        engine.feed("e")
        #expect(engine.cursor == Position(line: 0, col: 4))
        engine.feed("e")
        #expect(engine.cursor == Position(line: 0, col: 10))
    }

    @Test func eSkipsEmptyLines() {
        // :h e — empty lines are NOT considered words for e
        var engine = VimEngine(text: "one\n\ntwo")
        engine.feed("e")   // to 'e' of one (col 2)
        engine.feed("e")   // skips empty line, to end of "two"
        #expect(engine.cursor == Position(line: 2, col: 2))
    }

    @Test func countedWordMotion() {
        var engine = VimEngine(text: "one two three four")
        engine.feed(keys: "3w")
        #expect(engine.cursor == Position(line: 0, col: 14))  // start of "four"
    }
}

@Suite(.tags(.unit)) struct FindMotionTests {
    @Test func fMovesToChar() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "fo")
        #expect(engine.cursor == Position(line: 0, col: 4))
    }

    @Test func fWithNoMatchIsNoOp() {
        var engine = VimEngine(text: "hello")
        let events = engine.feed(keys: "fz")
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(events.isEmpty)
    }

    @Test func fDoesNotCrossLines() {
        var engine = VimEngine(text: "abc\nxyz")
        let events = engine.feed(keys: "fx")
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(events.isEmpty)
    }

    @Test func tStopsBeforeChar() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "tw")
        #expect(engine.cursor == Position(line: 0, col: 5))
    }

    @Test func FSearchesBackward() {
        var engine = VimEngine(text: "hello world")
        engine.feed("$")
        engine.feed(keys: "Fl")
        #expect(engine.cursor == Position(line: 0, col: 9))
    }

    @Test func TStopsAfterCharBackward() {
        var engine = VimEngine(text: "hello world")
        engine.feed("$")
        engine.feed(keys: "Te")
        #expect(engine.cursor == Position(line: 0, col: 2))
    }

    @Test func countedFind() {
        var engine = VimEngine(text: "a.b.c.d")
        engine.feed(keys: "2f.")
        #expect(engine.cursor == Position(line: 0, col: 3))
    }

    @Test func semicolonRepeatsLastFind() {
        var engine = VimEngine(text: "a.b.c.d")
        engine.feed(keys: "f.")
        #expect(engine.cursor == Position(line: 0, col: 1))
        engine.feed(";")
        #expect(engine.cursor == Position(line: 0, col: 3))
        engine.feed(";")
        #expect(engine.cursor == Position(line: 0, col: 5))
    }

    @Test func commaReversesLastFind() {
        var engine = VimEngine(text: "a.b.c.d")
        engine.feed(keys: "f.;;")
        #expect(engine.cursor == Position(line: 0, col: 5))
        engine.feed(",")
        #expect(engine.cursor == Position(line: 0, col: 3))
    }

    @Test func lastFindPersistsAcrossOtherCommands() {
        var engine = VimEngine(text: "a.b.c.d\nx.y.z")
        engine.feed(keys: "f.")     // last find = f .
        engine.feed(keys: "j0")     // unrelated motions
        engine.feed(keys: "w")      // more unrelated
        engine.feed(keys: "0")
        engine.feed(";")            // still repeats f.
        #expect(engine.cursor == Position(line: 1, col: 1))
    }

    @Test func semicolonWithNoPriorFindIsNoOp() {
        var engine = VimEngine(text: "a.b")
        let events = engine.feed(";")
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(events.isEmpty)
    }

    @Test func commaRepeatsTInOppositeDirection() {
        var engine = VimEngine(text: "a.b.c")
        engine.feed(keys: "t.")      // cursor col 0? t. from col 0: next '.' at 1, stop before => col 0 (no move but valid)
        engine.feed(keys: "f.")      // col 1
        engine.feed(keys: ";")       // col 3
        engine.feed(",")             // reverse F. => col 1
        #expect(engine.cursor == Position(line: 0, col: 1))
    }
}
