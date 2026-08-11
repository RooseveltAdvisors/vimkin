import Testing
@testable import Vimkin

// Batch 5a — visual charwise mode (v) and the minimal command line (:w :q :wq).

@Suite struct VisualModeTests {
    @Test func vEntersVisualEscLeaves() {
        var engine = VimEngine(text: "hello")
        let enter = engine.feed("v")
        #expect(engine.mode == .visual)
        #expect(enter.first?.verb == .enterVisual)
        let leave = engine.feed(.escape)
        #expect(engine.mode == .normal)
        #expect(leave.first?.verb == .leaveVisual)
    }

    @Test func vTogglesOff() {
        var engine = VimEngine(text: "hello")
        engine.feed("v")
        engine.feed("v")
        #expect(engine.mode == .normal)
    }

    @Test func visualMotionExtendsSelectionAndDDeletesInclusive() {
        var engine = VimEngine(text: "hello world")
        engine.feed("v")
        engine.feed(keys: "llll")  // select "hello" (cols 0-4 inclusive)
        let events = engine.feed("d")
        #expect(engine.buffer.text == " world")
        #expect(engine.mode == .normal)
        #expect(engine.cursor == Position(line: 0, col: 0))
        #expect(engine.register == .charwise("hello"))
        let e = try! #require(events.first)
        #expect(e.verb == .delete)
        #expect(e.target == .selection)
    }

    @Test func visualBackwardSelectionDeletes() {
        var engine = VimEngine(text: "hello")
        engine.feed("$")
        engine.feed("v")
        engine.feed(keys: "hh")   // select "llo" backward
        engine.feed("d")
        #expect(engine.buffer.text == "he")
    }

    @Test func visualYankKeepsBufferAndMovesToStart() {
        var engine = VimEngine(text: "hello world")
        engine.feed(keys: "w")
        engine.feed("v")
        engine.feed(keys: "llll")
        engine.feed("y")
        #expect(engine.buffer.text == "hello world")
        #expect(engine.register == .charwise("world"))
        #expect(engine.mode == .normal)
        #expect(engine.cursor == Position(line: 0, col: 6))  // start of selection
    }

    @Test func visualCEntersInsert() {
        var engine = VimEngine(text: "hello world")
        engine.feed("v")
        engine.feed(keys: "llll")
        engine.feed("c")
        #expect(engine.buffer.text == " world")
        #expect(engine.mode == .insert)
        #expect(engine.cursor == Position(line: 0, col: 0))
    }

    @Test func visualXDeletesLikeD() {
        var engine = VimEngine(text: "hello")
        engine.feed("v")
        engine.feed(keys: "ll")
        engine.feed("x")
        #expect(engine.buffer.text == "lo")
    }

    @Test func visualSpansLines() {
        var engine = VimEngine(text: "abc\ndef")
        engine.feed(keys: "ll")   // col 2
        engine.feed("v")
        engine.feed(keys: "jh")   // to (1,1)
        engine.feed("d")
        #expect(engine.buffer.text == "abf")
        #expect(engine.register == .charwise("c\nde"))
    }

    @Test func visualDeleteIsUndoable() {
        var engine = VimEngine(text: "hello")
        engine.feed("v")
        engine.feed(keys: "ll")
        engine.feed("d")
        #expect(engine.buffer.text == "lo")
        engine.feed("u")
        #expect(engine.buffer.text == "hello")
    }
}

@Suite struct CommandLineTests {
    @Test func colonEntersCommandLineMode() {
        var engine = VimEngine(text: "hi")
        engine.feed(":")
        #expect(engine.mode == .commandLine)
        #expect(engine.commandLine == "")
    }

    @Test func typedCharsAccumulateInPrompt() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":wq")
        #expect(engine.mode == .commandLine)
        #expect(engine.commandLine == "wq")
    }

    @Test func wqEmitsWriteQuitEvent() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":wq")
        let events = engine.feed(.enter)
        #expect(engine.mode == .normal)
        #expect(engine.commandLine == "")
        let e = try! #require(events.first)
        #expect(e.verb == .writeQuit)
        #expect(e.category == .commandLine)
    }

    @Test func wEmitsWriteEvent() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":w")
        let events = engine.feed(.enter)
        #expect(events.first?.verb == .write)
    }

    @Test func qEmitsQuitEvent() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":q")
        let events = engine.feed(.enter)
        #expect(events.first?.verb == .quit)
    }

    @Test func unknownCommandNoOpsOnEnter() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":zz")
        let events = engine.feed(.enter)
        #expect(engine.mode == .normal)
        #expect(events.isEmpty)
        #expect(engine.buffer.text == "hi")
    }

    @Test func escCancelsPrompt() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":wq")
        let events = engine.feed(.escape)
        #expect(engine.mode == .normal)
        #expect(engine.commandLine == "")
        #expect(events.isEmpty)
    }

    @Test func commandLineDoesNotTouchBuffer() {
        var engine = VimEngine(text: "hi")
        engine.feed(keys: ":wq")
        engine.feed(.enter)
        #expect(engine.buffer.text == "hi")
        #expect(engine.cursor == Position(line: 0, col: 0))
    }
}

@Suite struct DeterminismTests {
    // Property: an identical key sequence on an identical buffer always yields an
    // identical engine state (buffer, cursor, mode, register, events).
    static let recordedSequences: [(text: String, keys: String)] = [
        ("hello world", "dw"),
        ("hello world\nsecond line\nthird", "wdiwj2ddu"),
        ("say \"hi there\" now", "fhdi\"iREPLACED\u{1B}u"),
        ("one two three four", "3wdbP$x;,"),
        ("f(a, b)\ncall(x)\n\npara two", "f1ci(newargs\u{1B}jdapu"),
        ("alpha beta\ngamma delta", "yyjp2Gdd"),
        ("abc def ghi", "vlld$P:wq\n"),
        ("line one\n\nline three", "GddggP"),
        ("mixed.punct_word here", "wdwfhx3lD"),
        ("count me in", "2fnx$bcw123\u{1B}0"),
    ]

    @Test func identicalReplaysYieldIdenticalStates() {
        for (text, keys) in Self.recordedSequences {
            var a = VimEngine(text: text)
            var b = VimEngine(text: text)
            let eventsA = a.feed(keys: keys)
            let eventsB = b.feed(keys: keys)
            #expect(a == b, "engines diverged for keys: \(keys)")
            #expect(eventsA == eventsB, "events diverged for keys: \(keys)")
        }
    }

    @Test func replayFromSameStateContinuesIdentically() {
        // Split replay (feed in two chunks) must equal single replay.
        for (text, keys) in Self.recordedSequences {
            var whole = VimEngine(text: text)
            whole.feed(keys: keys)
            var split = VimEngine(text: text)
            let mid = keys.count / 2
            let prefix = String(keys.prefix(mid))
            let suffix = String(keys.suffix(keys.count - mid))
            split.feed(keys: prefix)
            split.feed(keys: suffix)
            #expect(whole == split, "split replay diverged for keys: \(keys)")
        }
    }
}
