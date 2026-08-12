// TextBuffer.swift — the line-oriented text model VimEngine operates on.
// Invariant: `lines` is never empty; an empty buffer is [""].

public struct TextBuffer: Equatable, Hashable, Sendable {
    public private(set) var lines: [String]

    public init(text: String) {
        let split = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.lines = split.isEmpty ? [""] : split
    }

    public init(lines: [String]) {
        self.lines = lines.isEmpty ? [""] : lines
    }

    public var text: String { lines.joined(separator: "\n") }
    public var lineCount: Int { lines.count }

    public func line(_ i: Int) -> String {
        precondition(i >= 0 && i < lines.count, "line index out of range")
        return lines[i]
    }

    public func lineLength(_ i: Int) -> Int {
        line(i).count
    }

    /// Character at position, or nil if the column is past the end of the line.
    public func char(at p: Position) -> Character? {
        guard p.line >= 0, p.line < lines.count else { return nil }
        let chars = Array(lines[p.line])
        guard p.col >= 0, p.col < chars.count else { return nil }
        return chars[p.col]
    }

    /// Column of the first non-blank character of a line (0 for an empty line).
    public func firstNonBlankCol(_ i: Int) -> Int {
        let chars = Array(line(i))
        for (idx, c) in chars.enumerated() where c != " " && c != "\t" {
            return idx
        }
        return 0
    }

    /// Clamp a column to a valid normal-mode cursor column on the given line.
    public func clampColForNormal(_ col: Int, line i: Int) -> Int {
        let len = lineLength(i)
        return max(0, min(col, max(0, len - 1)))
    }

    /// Clamp a column to a valid insert-mode cursor column (may sit past the last char).
    public func clampColForInsert(_ col: Int, line i: Int) -> Int {
        max(0, min(col, lineLength(i)))
    }

    // MARK: - Mutations (used by the engine; internal)

    /// Insert a string (may contain newlines) at a position. Returns the position just past the inserted text.
    @discardableResult
    mutating func insert(_ s: String, at p: Position) -> Position {
        let chars = Array(lines[p.line])
        let col = min(p.col, chars.count)
        let head = String(chars[..<col])
        let tail = String(chars[col...])
        let parts = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 {
            lines[p.line] = head + s + tail
            return Position(line: p.line, col: col + s.count)
        }
        var newLines: [String] = []
        newLines.append(head + parts[0])
        if parts.count > 2 {
            newLines.append(contentsOf: parts[1 ..< parts.count - 1])
        }
        let lastPart = parts[parts.count - 1]
        newLines.append(lastPart + tail)
        lines.replaceSubrange(p.line ... p.line, with: newLines)
        return Position(line: p.line + parts.count - 1, col: lastPart.count)
    }

    /// Delete the charwise range [from, toExclusive) (may span lines). Returns the deleted text.
    @discardableResult
    mutating func deleteCharRange(from: Position, toExclusive: Position) -> String {
        guard from < toExclusive else { return "" }
        if from.line == toExclusive.line {
            var chars = Array(lines[from.line])
            let lo = min(from.col, chars.count)
            let hi = min(toExclusive.col, chars.count)
            guard lo < hi else { return "" }
            let removed = String(chars[lo ..< hi])
            chars.removeSubrange(lo ..< hi)
            lines[from.line] = String(chars)
            return removed
        }
        // Multi-line: keep head of first line + tail of last line, drop the middle.
        let firstChars = Array(lines[from.line])
        let lastChars = Array(lines[toExclusive.line])
        let lo = min(from.col, firstChars.count)
        let hi = min(toExclusive.col, lastChars.count)
        var removed = String(firstChars[lo...])
        for i in (from.line + 1) ..< toExclusive.line {
            removed += "\n" + lines[i]
        }
        removed += "\n" + String(lastChars[..<hi])
        let merged = String(firstChars[..<lo]) + String(lastChars[hi...])
        lines.replaceSubrange(from.line ... toExclusive.line, with: [merged])
        return removed
    }

    /// Delete whole lines (inclusive range). Returns the removed lines. Buffer never goes empty.
    @discardableResult
    mutating func deleteLines(_ range: ClosedRange<Int>) -> [String] {
        let lo = max(0, range.lowerBound)
        let hi = min(lines.count - 1, range.upperBound)
        guard lo <= hi else { return [] }
        let removed = Array(lines[lo ... hi])
        lines.removeSubrange(lo ... hi)
        if lines.isEmpty { lines = [""] }
        return removed
    }

    /// Insert whole lines before the given line index (index may equal lineCount to append).
    mutating func insertLines(_ newLines: [String], at index: Int) {
        let i = max(0, min(index, lines.count))
        lines.insert(contentsOf: newLines, at: i)
    }

    /// Replace the content of one line.
    mutating func setLine(_ i: Int, to s: String) {
        lines[i] = s
    }

    /// Split the line at position into two lines (insert-mode Enter).
    mutating func splitLine(at p: Position) {
        let chars = Array(lines[p.line])
        let col = min(p.col, chars.count)
        let head = String(chars[..<col])
        let tail = String(chars[col...])
        lines.replaceSubrange(p.line ... p.line, with: [head, tail])
    }
}
