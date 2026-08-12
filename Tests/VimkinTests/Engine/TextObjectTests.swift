import Testing
@testable import Vimkin

// Batch 4 — text objects: iw aw i" a" i( a( ip ap with d/c/y.
// Behavior references: :h text-objects (iw, aw, i", a", ib/i(, ab/a(, ip, ap).

@Suite(.tags(.unit)) struct WordObjectTests {
    @Test func diwDeletesInnerWord() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "ll")  // middle of "hello"
        let events = engine.feed(keys: "diw")
        #expect(engine.buffer.text == " world")
        #expect(engine.cursor == Position(line: 0, col: 0))
        let e = try! #require(events.first)
        #expect(e.verb == .delete)
        #expect(e.modifier == .inside)
        #expect(e.target == .textObject(.word))
        #expect(e.category == .fullGrammar)
    }

    @Test func diwOnWhitespaceDeletesWhitespaceRun() {
        var engine = VimEngine(text: "a   b")
        engine.feed(keys: "ll")  // on middle space
        engine.feed(keys: "diw")
        #expect(engine.buffer.text == "ab")
    }

    @Test func dawDeletesWordAndTrailingSpace() {
        var engine = VimEngine(text: "one two three")
        engine.feed(keys: "w")   // on "two"
        engine.feed(keys: "daw")
        #expect(engine.buffer.text == "one three")
    }

    @Test func dawOnLastWordEatsLeadingSpace() {
        // :h aw — when there is no trailing white space, the leading white space is included
        var engine = VimEngine(text: "one two")
        engine.feed(keys: "w")
        engine.feed(keys: "daw")
        #expect(engine.buffer.text == "one")
    }

    @Test func ciwEntersInsertInPlace() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "ciw")
        #expect(engine.buffer.text == " world")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func yiwYanksWordCharwise() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "ll")
        engine.feed(keys: "yiw")
        #expect(engine.register == .charwise("hello"))
        #expect(engine.buffer.text == "hello world")
    }
}

@Suite(.tags(.unit)) struct QuoteObjectTests {
    @Test func diQuoteDeletesInsideQuotes() {
        var engine = VimEngine(text: #"say "hi there" now"#)
        engine.feed(keys: "fh")  // cursor inside the quotes (on 'h' of hi)
        let events = engine.feed(keys: "di\"")
        #expect(engine.buffer.text == #"say "" now"#)
        #expect(engine.cursor == Position(line: 0, col: 5))  // between the quotes
        let e = try! #require(events.first)
        #expect(e.modifier == .inside)
        #expect(e.target == .textObject(.quotedString))
        #expect(e.category == .fullGrammar)
    }

    @Test func daQuoteDeletesQuotesToo() {
        var engine = VimEngine(text: #"say "hi" now"#)
        engine.feed(keys: "fh")
        engine.feed(keys: "da\"")
        // a" includes trailing white space after the closing quote (:h a")
        #expect(engine.buffer.text == "say now")
    }

    @Test func ciQuoteEntersInsertBetweenQuotes() {
        var engine = VimEngine(text: #"name = "old""#)
        engine.feed(keys: "fo")
        engine.feed(keys: "ci\"")
        #expect(engine.buffer.text == #"name = """#)
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 8))
        var e2 = engine
        e2.feed(keys: "new")
        e2.feed(.escape)
        #expect(e2.buffer.text == #"name = "new""#)
    }

    @Test func iQuoteWithCursorBeforeQuotesOperatesOnNextPair() {
        // vim: i" searches forward on the line when the cursor is before the quotes
        var engine = VimEngine(text: #"x = "value""#)
        let events = engine.feed(keys: "di\"")
        #expect(engine.buffer.text == #"x = """#)
        #expect(!events.isEmpty)
    }

    @Test func iQuoteWithNoQuotesOnLineIsNoOp() {
        var engine = VimEngine(text: "no quotes here")
        let events = engine.feed(keys: "di\"")
        #expect(engine.buffer.text == "no quotes here")
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(engine.mode == .normal)
        #expect(events.isEmpty)
    }

    @Test func iQuoteCursorOnOpeningQuote() {
        var engine = VimEngine(text: #""abc" def"#)
        engine.feed(keys: "di\"")
        #expect(engine.buffer.text == #""" def"#)
    }
}

@Suite(.tags(.unit)) struct ParenObjectTests {
    @Test func diParenDeletesInsideParens() {
        var engine = VimEngine(text: "call(arg1, arg2)")
        engine.feed(keys: "f1")   // inside parens (the '1' of arg1)
        engine.feed(keys: "di(")
        #expect(engine.buffer.text == "call()")
    }

    @Test func ciParenEntersInsertWithParensEmptied() {
        var engine = VimEngine(text: "f(x + y)")
        engine.feed(keys: "fx")
        let events = engine.feed(keys: "ci(")
        #expect(engine.buffer.text == "f()")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 2))  // between the parens
        #expect(events.contains { $0.verb == .change && $0.target == .textObject(.parens) })
    }

    @Test func daParenDeletesParensToo() {
        var engine = VimEngine(text: "f(x) rest")
        engine.feed(keys: "fx")
        engine.feed(keys: "da(")
        #expect(engine.buffer.text == "f rest")
    }

    @Test func iParenWithCursorOnOpenParen() {
        var engine = VimEngine(text: "f(abc)")
        engine.feed(keys: "f(")
        engine.feed(keys: "di(")
        #expect(engine.buffer.text == "f()")
    }

    @Test func iParenSpansLines() {
        var engine = VimEngine(text: "f(a,\n  b)")
        engine.feed(keys: "fa")
        engine.feed(keys: "di(")
        #expect(engine.buffer.text == "f()")
    }

    @Test func iParenOutsideAnyParensIsNoOp() {
        var engine = VimEngine(text: "no parens")
        let events = engine.feed(keys: "di(")
        #expect(engine.buffer.text == "no parens")
        #expect(events.isEmpty)
        #expect(engine.mode == .normal)
    }

    @Test func nestedParensPickInnermost() {
        var engine = VimEngine(text: "f(g(x))")
        engine.feed(keys: "fx")
        engine.feed(keys: "di(")
        #expect(engine.buffer.text == "f(g())")
    }
}

@Suite(.tags(.unit)) struct ParagraphObjectTests {
    @Test func dipDeletesParagraphLinewise() {
        var engine = VimEngine(text: "para one a\npara one b\n\npara two")
        let events = engine.feed(keys: "dip")
        #expect(engine.buffer.lines == ["", "para two"])
        // linewise register
        #expect(engine.register == .linewise(["para one a", "para one b"]))
        let e = try! #require(events.first)
        #expect(e.target == .textObject(.paragraph))
        #expect(e.category == .fullGrammar)
    }

    @Test func dapDeletesParagraphAndTrailingBlankLines() {
        var engine = VimEngine(text: "para one\n\n\npara two")
        engine.feed(keys: "dap")
        #expect(engine.buffer.lines == ["para two"])
    }

    @Test func dipOnBlankLineDeletesBlankRun() {
        var engine = VimEngine(text: "one\n\n\ntwo")
        engine.feed(keys: "j")
        engine.feed(keys: "dip")
        #expect(engine.buffer.lines == ["one", "two"])
    }

    @Test func yipThenPPastesLinewise() {
        var engine = VimEngine(text: "a\nb\n\nc")
        engine.feed(keys: "yip")
        #expect(engine.register == .linewise(["a", "b"]))
        engine.feed(keys: "p")
        #expect(engine.buffer.lines == ["a", "a", "b", "b", "", "c"])
    }
}

@Suite(.tags(.unit)) struct TextObjectEdgeTests {
    @Test func textObjectWithoutOperatorInNormalModeIsInsertEntry() {
        // "i" alone in normal mode enters insert; "iw" would then type "w"
        var engine = VimEngine(text: "abc")
        engine.feed(keys: "iw")
        #expect(engine.mode == .insert)
        #expect(engine.buffer.text == "wabc")
    }

    @Test func operatorPlusInvalidObjectKeyCancels() {
        var engine = VimEngine(text: "abc def")
        let events = engine.feed(keys: "diz")
        #expect(engine.buffer.text == "abc def")
        #expect(engine.mode == .normal)
        #expect(events.isEmpty)
    }

    @Test func undoAfterTextObjectRestores() {
        var engine = VimEngine(text: #"say "hello" there"#)
        engine.feed(keys: "fe")
        engine.feed(keys: "di\"")
        #expect(engine.buffer.text == #"say "" there"#)
        engine.feed("u")
        #expect(engine.buffer.text == #"say "hello" there"#)
    }
}
