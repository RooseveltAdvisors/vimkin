// Motions.swift — pure motion resolution over a TextBuffer.
// Every function is deterministic and side-effect free.

/// How a motion's span combines with an operator (:h exclusive, :h linewise).
enum MotionSpan: Equatable, Sendable {
    case charwiseExclusive
    case charwiseInclusive
    case linewise
}

/// Persisted last-find state for `;` and `,`.
struct FindState: Equatable, Hashable, Sendable {
    var char: Character
    var forward: Bool
    var till: Bool
}

/// Result of resolving a motion from a position.
struct MotionResult: Equatable, Sendable {
    var target: Position
    var span: MotionSpan
    /// Updated last-find state (set by f/t/F/T; carried through otherwise).
    var newLastFind: FindState?
    /// Sticky column behavior: nil = set desired col to target col; .max = sticky line end ($).
    var desiredCol: Int?
}

enum CharClass: Int {
    case whitespace = 0
    case word = 1
    case punct = 2

    init(_ c: Character) {
        if c == " " || c == "\t" {
            self = .whitespace
        } else if c.isLetter || c.isNumber || c == "_" {
            self = .word
        } else {
            self = .punct
        }
    }
}

struct MotionResolver {
    let buffer: TextBuffer

    // MARK: position stepping

    /// Next position in reading order; steps onto col 0 of the next line after the
    /// last char of a line (an empty line's only position is col 0). nil at buffer end.
    func next(_ p: Position) -> Position? {
        let len = buffer.lineLength(p.line)
        if p.col + 1 < len {
            return Position(line: p.line, col: p.col + 1)
        }
        if p.line + 1 < buffer.lineCount {
            return Position(line: p.line + 1, col: 0)
        }
        return nil
    }

    /// Previous position in reading order. nil at buffer start.
    func prev(_ p: Position) -> Position? {
        if p.col > 0 {
            return Position(line: p.line, col: p.col - 1)
        }
        if p.line > 0 {
            let prevLine = p.line - 1
            return Position(line: prevLine, col: max(0, buffer.lineLength(prevLine) - 1))
        }
        return nil
    }

    func isEmptyLine(_ i: Int) -> Bool { buffer.lineLength(i) == 0 }

    func charClass(at p: Position) -> CharClass? {
        buffer.char(at: p).map(CharClass.init)
    }

    var lastPosition: Position {
        let lastLine = buffer.lineCount - 1
        return Position(line: lastLine, col: max(0, buffer.lineLength(lastLine) - 1))
    }

    // MARK: word motions (:h word-motions — a word is a run of word chars OR a run of
    // punct chars; an empty line counts as a word for w and b, but not for e)

    func wordForward(from p: Position) -> Position {
        var cur = p
        // Phase 1: leave the current word (skip the rest of its class run).
        if let cls = charClass(at: cur), cls != .whitespace {
            while let n = next(cur), charClass(at: n) == cls, n.line == cur.line {
                cur = n
            }
        }
        // Phase 2: advance at least once, then skip whitespace; stop at a non-blank
        // char or at an empty line (which is itself a word).
        guard var n = next(cur) else { return lastPosition }
        while true {
            if isEmptyLine(n.line) { return n }
            if let cls = charClass(at: n), cls != .whitespace { return n }
            guard let nn = next(n) else { return lastPosition }
            n = nn
        }
    }

    func wordBackward(from p: Position) -> Position {
        guard var cur = prev(p) else { return p }
        // Skip whitespace backwards; an empty line is a word — stop there.
        while true {
            if isEmptyLine(cur.line) { return cur }
            if let cls = charClass(at: cur), cls != .whitespace { break }
            guard let pp = prev(cur) else { return Position(line: 0, col: 0) }
            cur = pp
        }
        // Walk back to the start of this class run (same line).
        guard let cls = charClass(at: cur) else { return cur }
        while cur.col > 0 {
            let p2 = Position(line: cur.line, col: cur.col - 1)
            if charClass(at: p2) == cls {
                cur = p2
            } else {
                break
            }
        }
        return cur
    }

    func wordEnd(from p: Position) -> Position {
        guard var cur = next(p) else { return p }
        // Skip whitespace and empty lines (e ignores empty lines).
        while isEmptyLine(cur.line) || charClass(at: cur) == .whitespace {
            guard let n = next(cur) else { return lastPosition }
            cur = n
        }
        // Advance to the end of this class run (same line).
        guard let cls = charClass(at: cur) else { return cur }
        while cur.col + 1 < buffer.lineLength(cur.line) {
            let n = Position(line: cur.line, col: cur.col + 1)
            if charClass(at: n) == cls {
                cur = n
            } else {
                break
            }
        }
        return cur
    }

    // MARK: find on line

    /// f/t/F/T. Returns nil when there is no match on the cursor's line (no-op in vim).
    func find(_ state: FindState, from p: Position, count: Int) -> Position? {
        let chars = Array(buffer.line(p.line))
        var col = p.col
        for _ in 0 ..< max(1, count) {
            var found: Int?
            if state.forward {
                var i = col + 1
                while i < chars.count {
                    if chars[i] == state.char { found = i; break }
                    i += 1
                }
            } else {
                var i = col - 1
                while i >= 0 {
                    if chars[i] == state.char { found = i; break }
                    i -= 1
                }
            }
            guard let f = found else { return nil }
            col = f
        }
        if state.till {
            col += state.forward ? -1 : 1
        }
        return Position(line: p.line, col: col)
    }

    // MARK: motion resolution

    /// Resolve a motion for cursor movement or an operator span.
    /// Returns nil for a failed motion (find with no match, repeat-find with no state).
    func resolve(
        _ motion: Motion,
        from p: Position,
        count: Int,
        lastFind: FindState?,
        desiredCol: Int
    ) -> MotionResult? {
        let n = max(1, count)
        switch motion {
        case .left:
            let col = max(0, p.col - n)
            return MotionResult(target: Position(line: p.line, col: col), span: .charwiseExclusive, newLastFind: lastFind, desiredCol: nil)
        case .right:
            // Raw target may sit one past line end; callers clamp per mode/operator.
            let len = buffer.lineLength(p.line)
            let col = min(len, p.col + n)
            return MotionResult(target: Position(line: p.line, col: col), span: .charwiseExclusive, newLastFind: lastFind, desiredCol: nil)
        case .down:
            let line = min(buffer.lineCount - 1, p.line + n)
            let col = buffer.clampColForNormal(desiredCol, line: line)
            return MotionResult(target: Position(line: line, col: col), span: .linewise, newLastFind: lastFind, desiredCol: desiredCol)
        case .up:
            let line = max(0, p.line - n)
            let col = buffer.clampColForNormal(desiredCol, line: line)
            return MotionResult(target: Position(line: line, col: col), span: .linewise, newLastFind: lastFind, desiredCol: desiredCol)
        case .wordForward:
            var t = p
            for _ in 0 ..< n { t = wordForward(from: t) }
            return MotionResult(target: t, span: .charwiseExclusive, newLastFind: lastFind, desiredCol: nil)
        case .wordBackward:
            var t = p
            for _ in 0 ..< n { t = wordBackward(from: t) }
            return MotionResult(target: t, span: .charwiseExclusive, newLastFind: lastFind, desiredCol: nil)
        case .wordEnd:
            var t = p
            for _ in 0 ..< n { t = wordEnd(from: t) }
            return MotionResult(target: t, span: .charwiseInclusive, newLastFind: lastFind, desiredCol: nil)
        case .lineStart:
            return MotionResult(target: Position(line: p.line, col: 0), span: .charwiseExclusive, newLastFind: lastFind, desiredCol: nil)
        case .lineEnd:
            let col = max(0, buffer.lineLength(p.line) - 1)
            return MotionResult(target: Position(line: p.line, col: col), span: .charwiseInclusive, newLastFind: lastFind, desiredCol: Int.max)
        case .firstNonBlank:
            return MotionResult(target: Position(line: p.line, col: buffer.firstNonBlankCol(p.line)), span: .charwiseExclusive, newLastFind: lastFind, desiredCol: nil)
        case .fileStart:
            // gg: with a count, go to that line (vim). First non-blank column.
            let line = count > 0 ? min(buffer.lineCount - 1, count - 1) : 0
            let target = Position(line: line, col: buffer.firstNonBlankCol(line))
            return MotionResult(target: target, span: .linewise, newLastFind: lastFind, desiredCol: nil)
        case .fileEnd:
            // G: with a count, go to that line; without, the last line.
            let line = count > 0 ? min(buffer.lineCount - 1, count - 1) : buffer.lineCount - 1
            let target = Position(line: line, col: buffer.firstNonBlankCol(line))
            return MotionResult(target: target, span: .linewise, newLastFind: lastFind, desiredCol: nil)
        case .find(let c):
            let state = FindState(char: c, forward: true, till: false)
            guard let t = find(state, from: p, count: n) else { return nil }
            return MotionResult(target: t, span: .charwiseInclusive, newLastFind: state, desiredCol: nil)
        case .till(let c):
            let state = FindState(char: c, forward: true, till: true)
            guard let t = find(state, from: p, count: n) else { return nil }
            return MotionResult(target: t, span: .charwiseInclusive, newLastFind: state, desiredCol: nil)
        case .findBack(let c):
            let state = FindState(char: c, forward: false, till: false)
            guard let t = find(state, from: p, count: n) else { return nil }
            return MotionResult(target: t, span: .charwiseExclusive, newLastFind: state, desiredCol: nil)
        case .tillBack(let c):
            let state = FindState(char: c, forward: false, till: true)
            guard let t = find(state, from: p, count: n) else { return nil }
            return MotionResult(target: t, span: .charwiseExclusive, newLastFind: state, desiredCol: nil)
        case .repeatFind:
            guard let lf = lastFind else { return nil }
            guard let t = find(lf, from: p, count: n) else { return nil }
            let span: MotionSpan = lf.forward ? .charwiseInclusive : .charwiseExclusive
            return MotionResult(target: t, span: span, newLastFind: lastFind, desiredCol: nil)
        case .repeatFindReverse:
            guard let lf = lastFind else { return nil }
            let reversed = FindState(char: lf.char, forward: !lf.forward, till: lf.till)
            guard let t = find(reversed, from: p, count: n) else { return nil }
            let span: MotionSpan = reversed.forward ? .charwiseInclusive : .charwiseExclusive
            // `,` does not overwrite the stored direction (:h ,).
            return MotionResult(target: t, span: span, newLastFind: lastFind, desiredCol: nil)
        }
    }

    /// Operator-span end for the `w` motion (:h word-motions special case):
    /// when the last word moved over is at the end of a line, the operated text ends
    /// at the end of that line — dw on the last word does not join lines.
    func wordForwardOperatorEnd(from p: Position, count: Int) -> Position {
        var cur = p
        for i in 0 ..< max(1, count) {
            let t = wordForward(from: cur)
            let isLast = i == max(1, count) - 1
            if isLast {
                if t.line > cur.line {
                    // Clamp to just past the last char of the current line.
                    return Position(line: cur.line, col: buffer.lineLength(cur.line))
                }
                if t == cur {
                    // No further word (end of buffer): consume through end of line.
                    return Position(line: cur.line, col: buffer.lineLength(cur.line))
                }
                return t
            }
            if t == cur {
                // Ran out of words mid-count.
                return Position(line: cur.line, col: buffer.lineLength(cur.line))
            }
            cur = t
        }
        return cur
    }
}
