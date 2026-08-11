import Testing
@testable import Vimkin

// Batch 3 — operators (d c y + motions), linewise doubles (dd cc yy), x, p/P,
// register kind semantics, undo, counts composing across operator and motion.
// Behavior references: :h d, :h c, :h dd, :h p, :h u, :h word-motions (dw clamp), :h cw.

@Suite struct DeleteOperatorTests {
    @Test func dwDeletesWordAndTrailingSpace() {
        var engine = VimEngine(text: "hello world")
        let events = engine.feed(keys: "dw")
        #expect(engine.buffer.text == "world")
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(engine.mode == .normal)
        let e = try! #require(events.first)
        #expect(e.verb == .delete)
        #expect(e.target == .motion(.wordForward))
        #expect(e.category == .operatorMotion)
    }

    @Test func dwOnLastWordOfLineDeletesToEndOfLineOnly() {
        // :h word-motions — dw on the last word does not join lines
        var engine = VimEngine(text: "hello world\nnext")
        engine.feed(keys: "w")  // on "world"
        engine.feed(keys: "dw")
        #expect(engine.buffer.lines == ["hello ", "next"])
        #expect(engine.cursor == Position(line: 0, col: 5))  // clamped to last char
    }

    @Test func dDollarDeletesToEndOfLine() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "w")
        engine.feed(keys: "d$")
        #expect(engine.buffer.text == "hello ")
    }

    @Test func dZeroDeletesToLineStart() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "w")
        engine.feed(keys: "d0")
        #expect(engine.buffer.text == "world")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func dfXDeletesThroughChar() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "dfo")
        #expect(engine.buffer.text == " world")  // f is inclusive
    }

    @Test func dtXDeletesUpToChar() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "dtw")
        #expect(engine.buffer.text == "world")
    }

    @Test func dFailedFindIsNoOp() {
        var engine = VimEngine(text: "hello")
        let events = engine.feed(keys: "dfz")
        #expect(engine.buffer.text == "hello")
        #expect(engine.mode == .normal)
        #expect(events.isEmpty)
    }

    @Test func dGDeletesLinewiseToEnd() {
        var engine = VimEngine(text: "one\ntwo\nthree")
        engine.feed(keys: "j")
        engine.feed(keys: "dG")
        #expect(engine.buffer.lines == ["one"])
    }

    @Test func deDeletesThroughWordEnd() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "de")
        #expect(engine.buffer.text == " world")
    }

    @Test func escFromOperatorPendingCancels() {
        var engine = VimEngine(text: "hello")
        engine.feed("d")
        #expect(engine.mode == .operatorPending)
        engine.feed(.escape)
        #expect(engine.mode == .normal)
        engine.feed("w")  // just a motion now
        #expect(engine.buffer.text == "hello")
        #expect(engine.cursor == Position(line: 0, col: 4))
    }

    @Test func ddDeletesLine() {
        var engine = VimEngine(text: "one\ntwo\nthree")
        engine.feed(keys: "j")
        let events = engine.feed(keys: "dd")
        #expect(engine.buffer.lines == ["one", "three"])
        #expect(engine.cursor == Position(line: 1, col: 0))
        let e = try! #require(events.first)
        #expect(e.verb == .delete)
        #expect(e.target == .line)
        #expect(e.category == .operatorMotion)
    }

    @Test func ddOnLastLineMovesCursorUp() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "j")
        engine.feed(keys: "dd")
        #expect(engine.buffer.lines == ["one"])
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func ddOnOnlyLineLeavesEmptyBuffer() {
        var engine = VimEngine(text: "only")
        engine.feed(keys: "dd")
        #expect(engine.buffer.lines == [""])
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func twoDDDeletesTwoLines() {
        var engine = VimEngine(text: "one\ntwo\nthree")
        let events = engine.feed(keys: "2dd")
        #expect(engine.buffer.lines == ["three"])
        #expect(events.first?.count == 2)
    }

    @Test func d2wDeletesTwoWords() {
        var engine = VimEngine(text: "one two three")
        engine.feed(keys: "d2w")
        #expect(engine.buffer.text == "three")
    }

    @Test func countsComposeAcrossOperatorAndMotion() {
        // 2d3w = 6 words (:h o_count)
        var engine = VimEngine(text: "a b c d e f g")
        engine.feed(keys: "2d3w")
        #expect(engine.buffer.text == "g")
    }

    @Test func dDollarOnEmptyLineIsHarmless() {
        var engine = VimEngine(text: "abc\n\ndef")
        engine.feed(keys: "j")
        engine.feed(keys: "d$")
        #expect(engine.buffer.lines == ["abc", "", "def"])
        #expect(engine.mode == .normal)
    }
}

@Suite struct ChangeOperatorTests {
    @Test func cwActsLikeCeOnWord() {
        // :h cw — cw on a non-blank behaves like ce (does not eat trailing space)
        var engine = VimEngine(text: "hello world")
        let events = engine.feed(keys: "cw")
        #expect(engine.buffer.text == " world")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 0))
        let e = try! #require(events.first)
        #expect(e.verb == .change)
    }

    @Test func cwThenTypingReplacesWord() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "cw")
        engine.feed(keys: "goodbye")
        engine.feed(.escape)
        #expect(engine.buffer.text == "goodbye world")
    }

    @Test func ccClearsLineAndEntersInsert() {
        var engine = VimEngine(text: "one\ntwo\nthree")
        engine.feed(keys: "j")
        engine.feed(keys: "cc")
        #expect(engine.mode == .insert)
        #expect(engine.buffer.lines == ["one", "", "three"])
        #expect(engine.cursor == Position(line: 1, col: 0))
    }

    @Test func cDollarChangesToEndOfLine() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "w")
        engine.feed(keys: "c$")
        #expect(engine.buffer.text == "hello ")
        #expect(engine.mode == .insert)
    }
}

@Suite struct YankPutRegisterTests {
    @Test func ywYanksWithoutMutating() {
        var engine = VimEngine(text: "hello world")
        let events = engine.feed(keys: "yw")
        #expect(engine.buffer.text == "hello world")
        #expect(engine.register == .charwise("hello "))
        let e = try! #require(events.first)
        #expect(e.verb == .yank)
    }

    @Test func yyYanksLineLinewise() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "yy")
        #expect(engine.register == .linewise(["one"]))
        #expect(engine.buffer.lines == ["one", "two"])
    }

    @Test func dwThenPPastesInlineAfterCursor() {
        // charwise register kind
        var engine = VimEngine(text: "one two")
        engine.feed(keys: "dw")            // register "one " charwise; buffer "two"
        engine.feed(keys: "$")             // on 'o'... "two" last char
        let events = engine.feed("p")
        #expect(engine.buffer.text == "twoone ")
        let e = try! #require(events.first)
        #expect(e.verb == .put)
        #expect(e.category == .action)
    }

    @Test func ddThenPOpensNewLineBelow() {
        // linewise register kind
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "dd")            // register ["one"] linewise; buffer ["two"]
        engine.feed("p")
        #expect(engine.buffer.lines == ["two", "one"])
        #expect(engine.cursor == Position(line: 1, col: 0))  // first non-blank of pasted line
    }

    @Test func ddThenCapitalPPastesAbove() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "dd")
        engine.feed("P")
        #expect(engine.buffer.lines == ["one", "two"])
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func charwisePPastesBeforeCursor() {
        var engine = VimEngine(text: "abc")
        engine.feed(keys: "x")   // delete 'a' → register charwise "a", buffer "bc"
        engine.feed("$")
        engine.feed("P")
        #expect(engine.buffer.text == "bac")
    }

    @Test func charwisePCursorLandsOnLastPastedChar() {
        var engine = VimEngine(text: "one two")
        engine.feed(keys: "dw")  // "one " charwise
        engine.feed("p")         // paste after 't'
        // after dw buffer is "two", cursor col 0 on 't'; p pastes "one " after the cursor.
        #expect(engine.buffer.text == "tone wo")
        #expect(engine.cursor == Position(line: 0, col: 4))  // on the last pasted char (the space)
    }

    @Test func pWithEmptyRegisterIsNoOp() {
        var engine = VimEngine(text: "abc")
        let events = engine.feed("p")
        #expect(engine.buffer.text == "abc")
        #expect(events.isEmpty)
    }

    @Test func xDeletesCharIntoRegister() {
        var engine = VimEngine(text: "abc")
        let events = engine.feed("x")
        #expect(engine.buffer.text == "bc")
        #expect(engine.register == .charwise("a"))
        let e = try! #require(events.first)
        #expect(e.verb == .deleteChar)
        #expect(e.category == .action)
    }

    @Test func xAtEndOfLineClampsCursor() {
        var engine = VimEngine(text: "ab")
        engine.feed("$")
        engine.feed("x")
        #expect(engine.buffer.text == "a")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func xOnEmptyLineIsNoOp() {
        var engine = VimEngine(text: "")
        let events = engine.feed("x")
        #expect(engine.buffer.text == "")
        #expect(events.isEmpty)
    }

    @Test func countedXDeletesNChars() {
        var engine = VimEngine(text: "abcdef")
        engine.feed(keys: "3x")
        #expect(engine.buffer.text == "def")
        #expect(engine.register == .charwise("abc"))
    }
}

@Suite struct UndoTests {
    @Test func undoRestoresBufferAndCursorAfterDw() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "w")   // cursor col 6
        engine.feed(keys: "0")
        engine.feed(keys: "dw")
        #expect(engine.buffer.text == "world")
        let events = engine.feed("u")
        #expect(engine.buffer.text == "hello world")
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(events.first?.verb == .undo)
    }

    @Test func undoRestoresAfterDd() {
        var engine = VimEngine(text: "one\ntwo\nthree")
        engine.feed(keys: "j")
        engine.feed(keys: "dd")
        engine.feed("u")
        #expect(engine.buffer.lines == ["one", "two", "three"])
        #expect(engine.cursor == Position(line: 1, col: 0))
    }

    @Test func undoRestoresAfterInsertSession() {
        var engine = VimEngine(text: "hello")
        engine.feed(keys: "A")
        engine.feed(keys: " world")
        engine.feed(.escape)
        #expect(engine.buffer.text == "hello world")
        engine.feed("u")
        #expect(engine.buffer.text == "hello")
    }

    @Test func undoRestoresAfterX() {
        var engine = VimEngine(text: "abc")
        engine.feed("x")
        engine.feed("u")
        #expect(engine.buffer.text == "abc")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func undoRestoresAfterPut() {
        var engine = VimEngine(text: "one\ntwo")
        engine.feed(keys: "dd")
        engine.feed("p")
        #expect(engine.buffer.lines == ["two", "one"])
        engine.feed("u")
        #expect(engine.buffer.lines == ["two"])
    }

    @Test func undoWithEmptyHistoryIsNoOp() {
        var engine = VimEngine(text: "abc")
        let events = engine.feed("u")
        #expect(engine.buffer.text == "abc")
        #expect(events.isEmpty)
    }

    @Test func undoDoesNotRestoreRegister() {
        // vim: undo restores text, not registers
        var engine = VimEngine(text: "abc def")
        engine.feed(keys: "dw")
        engine.feed("u")
        #expect(engine.register == .charwise("abc "))
    }

    @Test func yankIsNotAnUndoStep() {
        // u after yw should undo the edit BEFORE the yank (yank is not a change)
        var engine = VimEngine(text: "abc def")
        engine.feed("x")               // change #1
        engine.feed(keys: "yw")        // not a change
        engine.feed("u")
        #expect(engine.buffer.text == "abc def")
    }
}
