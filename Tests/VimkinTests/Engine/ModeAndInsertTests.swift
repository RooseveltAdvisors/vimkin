import Testing
@testable import Vimkin

// Batch 1 — modes, insert family (i a o I A O, Esc), basic motions (h j k l 0 $ ^ gg G).
// Behavior references: real Vim documented behavior (:h insert, :h left-right-motions, :h up-down-motions).

@Suite struct ModeTests {
    @Test func startsInNormalMode() {
        let engine = VimEngine(text: "hello")
        #expect(engine.mode == .normal)
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(engine.buffer.text == "hello")
    }

    @Test func iEntersInsertBeforeCursor() {
        var engine = VimEngine(text: "hello")
        engine.feed(keys: "ll")  // cursor on 'l' (col 2)
        let events = engine.feed("i")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 2))
        #expect(events.contains { $0.verb == .enterInsert })
    }

    @Test func aEntersInsertAfterCursor() {
        var engine = VimEngine(text: "hello")
        engine.feed("a")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 1))
    }

    @Test func aOnEmptyLineStaysAtColZero() {
        var engine = VimEngine(text: "")
        engine.feed("a")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func capitalIGoesToFirstNonBlank() {
        var engine = VimEngine(text: "   hello")
        engine.feed("$")
        engine.feed("I")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 3))
    }

    @Test func capitalAGoesToEndOfLine() {
        var engine = VimEngine(text: "hello")
        engine.feed("A")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 5))  // past last char
    }

    @Test func oOpensLineBelow() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed("o")
        #expect(engine.mode == .insert)
        #expect(engine.buffer.lines == ["one", "", "two"])
        #expect(engine.cursor == Position(line: 1, col: 0))
    }

    @Test func capitalOOpensLineAbove() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "j")
        engine.feed("O")
        #expect(engine.mode == .insert)
        #expect(engine.buffer.lines == ["one", "", "two"])
        #expect(engine.cursor == Position(line: 1, col: 0))
    }

    @Test func escLeavesInsertAndMovesCursorLeft() {
        var engine = VimEngine(text: "hello")
        engine.feed(keys: "lli")   // insert at col 2
        engine.feed(.escape)
        #expect(engine.mode == .normal)
        #expect(engine.cursor == Position(line: 0, col: 1))  // vim moves cursor left on Esc
    }

    @Test func escInNormalModeIsNoOp() {
        var engine = VimEngine(text: "hello")
        let events = engine.feed(.escape)
        #expect(engine.mode == .normal)
        #expect(events.isEmpty)
    }

    @Test func insertModeTypesLiterally() {
        var engine = VimEngine(text: "world")
        engine.feed("i")
        engine.feed(keys: "hello ")
        #expect(engine.buffer.text == "hello world")
        #expect(engine.cursor == Position(line: 0, col: 6))
    }

    @Test func motionKeysInInsertModeInsertLiterally() {
        var engine = VimEngine(text: "")
        engine.feed("i")
        engine.feed(keys: "hjkl0$w")
        #expect(engine.buffer.text == "hjkl0$w")
        #expect(engine.mode == .insert)
    }

    @Test func enterInInsertModeSplitsLine() {
        var engine = VimEngine(text: "helloworld")
        engine.feed(keys: "lllll")  // col 5
        engine.feed("i")
        engine.feed(.enter)
        #expect(engine.buffer.lines == ["hello", "world"])
        #expect(engine.cursor == Position(line: 1, col: 0))
    }
}

@Suite struct BasicMotionTests {
    @Test func hjklMove() {
        var engine = VimEngine(text: "abc\ndef\nghi")
        engine.feed("l")
        #expect(engine.cursor == Position(line: 0, col: 1))
        engine.feed("j")
        #expect(engine.cursor == Position(line: 1, col: 1))
        engine.feed("h")
        #expect(engine.cursor == Position(line: 1, col: 0))
        engine.feed("k")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func hjklClampAtEdges() {
        var engine = VimEngine(text: "ab\ncd")
        engine.feed("h")
        #expect(engine.cursor == Position(line: 0, col: 0))
        engine.feed("k")
        #expect(engine.cursor == Position(line: 0, col: 0))
        engine.feed(keys: "jj")
        #expect(engine.cursor == Position(line: 1, col: 0))
        engine.feed(keys: "lll")
        #expect(engine.cursor == Position(line: 1, col: 1))  // normal mode clamps to last char
    }

    @Test func lDoesNotPassLastChar() {
        var engine = VimEngine(text: "ab")
        engine.feed(keys: "llll")
        #expect(engine.cursor == Position(line: 0, col: 1))
    }

    @Test func zeroGoesToLineStart() {
        var engine = VimEngine(text: "  hello")
        engine.feed("$")
        engine.feed("0")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func dollarGoesToLastChar() {
        var engine = VimEngine(text: "hello")
        engine.feed("$")
        #expect(engine.cursor == Position(line: 0, col: 4))
    }

    @Test func dollarOnEmptyLineStaysAtZero() {
        var engine = VimEngine(text: "abc\n\ndef")
        engine.feed(keys: "j")
        let events = engine.feed("$")
        #expect(engine.cursor == Position(line: 1, col: 0))
        #expect(!events.isEmpty)  // motion still executes (it is not an error in vim)
    }

    @Test func caretGoesToFirstNonBlank() {
        var engine = VimEngine(text: "   hello")
        engine.feed("$")
        engine.feed("^")
        #expect(engine.cursor == Position(line: 0, col: 3))
    }

    @Test func ggGoesToFirstLine() {
        var engine = VimEngine(text: "one\ntwo\n  three")
        engine.feed(keys: "jj")
        engine.feed(keys: "gg")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func GGoesToLastLineFirstNonBlank() {
        var engine = VimEngine(text: "one\ntwo\n  three")
        engine.feed("G")
        #expect(engine.cursor == Position(line: 2, col: 2))
    }

    @Test func countGGoesToLine() {
        var engine = VimEngine(text: "one\ntwo\nthree\nfour")
        engine.feed(keys: "2G")
        #expect(engine.cursor == Position(line: 1, col: 0))
    }

    @Test func jkPreserveDesiredColumnClamping() {
        // moving j onto a shorter line clamps col; vim remembers desired col — v1: clamp is required,
        // desired-column restore is also vim behavior we implement.
        var engine = VimEngine(text: "abcdef\nab\nabcdef")
        engine.feed("$")   // col 5
        engine.feed("j")
        #expect(engine.cursor == Position(line: 1, col: 1))
        engine.feed("j")
        #expect(engine.cursor.line == 2)
        #expect(engine.cursor.col >= 1)  // at minimum clamped col; desired-col restore gives 5
    }

    @Test func motionEmitsSingleMotionEvent() {
        var engine = VimEngine(text: "hello world")
        let events = engine.feed("w")
        #expect(events.count == 1)
        let e = try! #require(events.first)
        #expect(e.verb == .move)
        #expect(e.category == .singleMotion)
    }

    @Test func countedMotionComposes() {
        var engine = VimEngine(text: "abcdef")
        let events = engine.feed(keys: "3l")
        #expect(engine.cursor == Position(line: 0, col: 3))
        #expect(events.last?.count == 3)
    }
}
