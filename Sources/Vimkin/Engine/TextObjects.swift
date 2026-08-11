// TextObjects.swift — resolution of iw aw i" a" i( a( ip ap to buffer ranges.
// Pure functions over TextBuffer; no mutation.

struct TextObjectResolver {
    let buffer: TextBuffer

    enum ObjectRange: Equatable {
        case charwise(start: Position, endExclusive: Position)
        case linewise(ClosedRange<Int>)
    }

    /// Resolve an object key + modifier at the cursor. nil = object not found (no-op in vim).
    func resolve(
        key: Character, modifier: CommandEvent.Modifier, at cursor: Position
    ) -> (ObjectRange, TextObjectKind)? {
        switch key {
        case "w":
            return wordObject(modifier: modifier, at: cursor).map { ($0, .word) }
        case "\"":
            return quoteObject(modifier: modifier, at: cursor).map { ($0, .quotedString) }
        case "(", ")":
            return parenObject(modifier: modifier, at: cursor).map { ($0, .parens) }
        case "p":
            return paragraphObject(modifier: modifier, at: cursor).map { ($0, .paragraph) }
        default:
            return nil
        }
    }

    // MARK: - iw / aw

    private func wordObject(modifier: CommandEvent.Modifier, at cursor: Position) -> ObjectRange? {
        let chars = Array(buffer.line(cursor.line))
        guard !chars.isEmpty, cursor.col < chars.count else { return nil }
        let cls = CharClass(chars[cursor.col])

        var lo = cursor.col
        while lo > 0 && CharClass(chars[lo - 1]) == cls { lo -= 1 }
        var hi = cursor.col
        while hi + 1 < chars.count && CharClass(chars[hi + 1]) == cls { hi += 1 }

        if modifier == .inside {
            return .charwise(
                start: Position(line: cursor.line, col: lo),
                endExclusive: Position(line: cursor.line, col: hi + 1)
            )
        }

        // around
        if cls == .whitespace {
            // aw on white space: the white space plus the following word (:h aw).
            var end = hi
            if end + 1 < chars.count {
                let wordCls = CharClass(chars[end + 1])
                while end + 1 < chars.count && CharClass(chars[end + 1]) == wordCls { end += 1 }
            }
            return .charwise(
                start: Position(line: cursor.line, col: lo),
                endExclusive: Position(line: cursor.line, col: end + 1)
            )
        }
        var start = lo
        var end = hi
        if end + 1 < chars.count && CharClass(chars[end + 1]) == .whitespace {
            // include trailing white space
            while end + 1 < chars.count && CharClass(chars[end + 1]) == .whitespace { end += 1 }
        } else {
            // no trailing white space: include leading white space
            while start > 0 && CharClass(chars[start - 1]) == .whitespace { start -= 1 }
        }
        return .charwise(
            start: Position(line: cursor.line, col: start),
            endExclusive: Position(line: cursor.line, col: end + 1)
        )
    }

    // MARK: - i" / a"

    private func quoteObject(modifier: CommandEvent.Modifier, at cursor: Position) -> ObjectRange? {
        let chars = Array(buffer.line(cursor.line))
        var quoteCols: [Int] = []
        for (i, c) in chars.enumerated() where c == "\"" { quoteCols.append(i) }
        guard quoteCols.count >= 2 else { return nil }

        // Pair quotes in order: (0,1), (2,3), …
        var pair: (open: Int, close: Int)?
        var i = 0
        while i + 1 < quoteCols.count {
            let open = quoteCols[i], close = quoteCols[i + 1]
            if cursor.col >= open && cursor.col <= close {
                pair = (open, close)
                break
            }
            if open > cursor.col {
                // vim: i"/a" searches forward on the line for the next quoted string
                pair = (open, close)
                break
            }
            i += 2
        }
        guard let (open, close) = pair else { return nil }

        if modifier == .inside {
            return .charwise(
                start: Position(line: cursor.line, col: open + 1),
                endExclusive: Position(line: cursor.line, col: close)
            )
        }
        // a": include the quotes plus trailing white space (or leading if none trailing).
        var start = open
        var end = close
        if end + 1 < chars.count && CharClass(chars[end + 1]) == .whitespace {
            while end + 1 < chars.count && CharClass(chars[end + 1]) == .whitespace { end += 1 }
        } else {
            while start > 0 && CharClass(chars[start - 1]) == .whitespace { start -= 1 }
        }
        return .charwise(
            start: Position(line: cursor.line, col: start),
            endExclusive: Position(line: cursor.line, col: end + 1)
        )
    }

    // MARK: - i( / a(

    private func parenObject(modifier: CommandEvent.Modifier, at cursor: Position) -> ObjectRange? {
        guard let (open, close) = findParenPair(at: cursor) else { return nil }
        let resolver = MotionResolver(buffer: buffer)
        if modifier == .inside {
            guard let innerStart = resolver.next(open) else { return nil }
            return .charwise(start: innerStart, endExclusive: close)
        }
        return .charwise(start: open, endExclusive: Position(line: close.line, col: close.col + 1))
    }

    private func findParenPair(at cursor: Position) -> (open: Position, close: Position)? {
        let resolver = MotionResolver(buffer: buffer)
        let cursorChar = buffer.char(at: cursor)

        var open: Position?
        if cursorChar == "(" {
            open = cursor
        } else if cursorChar == ")" {
            // Cursor on the closer: find its matching opener backward.
            var depth = 0
            var p = resolver.prev(cursor)
            while let cur = p {
                if let ch = buffer.char(at: cur) {
                    if ch == ")" { depth += 1 }
                    if ch == "(" {
                        if depth == 0 { open = cur; break }
                        depth -= 1
                    }
                }
                p = resolver.prev(cur)
            }
            guard let o = open else { return nil }
            return (o, cursor)
        } else {
            // Scan backward for the nearest unmatched opener.
            var depth = 0
            var p = resolver.prev(cursor)
            while let cur = p {
                if let ch = buffer.char(at: cur) {
                    if ch == ")" { depth += 1 }
                    if ch == "(" {
                        if depth == 0 { open = cur; break }
                        depth -= 1
                    }
                }
                p = resolver.prev(cur)
            }
        }
        guard let o = open else { return nil }

        // Find the matching closer forward from just past the opener.
        var depth = 0
        var p = resolver.next(o)
        while let cur = p {
            if let ch = buffer.char(at: cur) {
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    if depth == 0 { return (o, cur) }
                    depth -= 1
                }
            }
            p = resolver.next(cur)
        }
        return nil
    }

    // MARK: - ip / ap

    private func isBlank(_ line: Int) -> Bool { buffer.lineLength(line) == 0 }

    private func paragraphObject(modifier: CommandEvent.Modifier, at cursor: Position) -> ObjectRange? {
        let line = cursor.line
        let onBlank = isBlank(line)

        var lo = line
        while lo > 0 && isBlank(lo - 1) == onBlank { lo -= 1 }
        var hi = line
        while hi + 1 < buffer.lineCount && isBlank(hi + 1) == onBlank { hi += 1 }

        if modifier == .inside {
            return .linewise(lo ... hi)
        }

        // around
        if onBlank {
            // ap on blank lines: the blank run plus the following paragraph.
            var end = hi
            while end + 1 < buffer.lineCount && !isBlank(end + 1) { end += 1 }
            return .linewise(lo ... end)
        }
        var start = lo
        var end = hi
        if end + 1 < buffer.lineCount && isBlank(end + 1) {
            while end + 1 < buffer.lineCount && isBlank(end + 1) { end += 1 }
        } else {
            while start > 0 && isBlank(start - 1) { start -= 1 }
        }
        return .linewise(start ... end)
    }
}
