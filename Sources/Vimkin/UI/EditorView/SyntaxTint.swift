// SyntaxTint.swift — light, line-based syntax tinting for md / json / yaml.
// Pure classification (no UI types) so it unit-tests as plain functions.
// Deliberately simple per plan U4: line-oriented regex, no dependency, no
// multi-line state (a JSON string spanning lines is out of scope).

import Foundation

public enum SyntaxTint {
    /// Tint classes the editor palette maps to colors.
    public enum Kind: String, Equatable, Sendable {
        case header   // md: # headings
        case key      // json/yaml keys, md list bullets
        case string   // quoted string values
        case comment  // yaml # comments
    }

    /// A tinted span of one line, in Character-index columns.
    public struct Span: Equatable, Sendable {
        public var range: Range<Int>
        public var kind: Kind

        public init(range: Range<Int>, kind: Kind) {
            self.range = range
            self.kind = kind
        }
    }

    public enum Language: Equatable, Sendable {
        case markdown
        case json
        case yaml
        case plain

        public init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "md", "markdown": self = .markdown
            case "json": self = .json
            case "yaml", "yml": self = .yaml
            default: self = .plain
            }
        }
    }

    /// Classify one line into tint spans. Untinted columns render as body text.
    public static func spans(for line: String, language: Language) -> [Span] {
        switch language {
        case .markdown: return markdownSpans(line)
        case .json: return jsonSpans(line)
        case .yaml: return yamlSpans(line)
        case .plain: return []
        }
    }

    // MARK: - Markdown

    private static func markdownSpans(_ line: String) -> [Span] {
        let chars = Array(line)
        // Heading: 1-6 leading #s followed by a space → tint the whole line.
        var i = 0
        while i < chars.count, chars[i] == "#" { i += 1 }
        if (1 ... 6).contains(i), i < chars.count, chars[i] == " " {
            return [Span(range: 0 ..< chars.count, kind: .header)]
        }
        // List bullet: optional indent + "- " / "* " → tint the bullet char.
        var j = 0
        while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
        if j < chars.count, chars[j] == "-" || chars[j] == "*",
           j + 1 < chars.count, chars[j + 1] == " " {
            return [Span(range: j ..< j + 1, kind: .key)]
        }
        return []
    }

    // MARK: - JSON

    private static func jsonSpans(_ line: String) -> [Span] {
        // Every double-quoted token; a token followed by ":" is a key, else a string.
        var spans: [Span] = []
        for (range, isKey) in quotedTokens(line) {
            spans.append(Span(range: range, kind: isKey ? .key : .string))
        }
        return spans
    }

    // MARK: - YAML

    private static func yamlSpans(_ line: String) -> [Span] {
        let chars = Array(line)
        // Full-line or trailing comment: from an unquoted # to end of line.
        // (Simple scan: a # not inside quotes.)
        var inQuote: Character? = nil
        var commentStart: Int? = nil
        for (idx, c) in chars.enumerated() {
            if let q = inQuote {
                if c == q { inQuote = nil }
            } else if c == "\"" || c == "'" {
                inQuote = c
            } else if c == "#" {
                commentStart = idx
                break
            }
        }
        var spans: [Span] = []
        let scanEnd = commentStart ?? chars.count

        // Key: optional indent, optional "- ", then bare-word up to ":".
        var i = 0
        while i < scanEnd, chars[i] == " " { i += 1 }
        if i + 1 < scanEnd, chars[i] == "-", chars[i + 1] == " " { i += 2 }
        let keyStart = i
        while i < scanEnd, chars[i] != ":", chars[i] != " ", chars[i] != "\"", chars[i] != "'" { i += 1 }
        if i > keyStart, i < scanEnd, chars[i] == ":" {
            spans.append(Span(range: keyStart ..< i, kind: .key))
        }

        // Quoted string values (before any comment).
        let head = String(chars[0 ..< scanEnd])
        for (range, _) in quotedTokens(head) {
            spans.append(Span(range: range, kind: .string))
        }

        if let cs = commentStart {
            spans.append(Span(range: cs ..< chars.count, kind: .comment))
        }
        return spans
    }

    // MARK: - Shared

    /// All double-quoted tokens in a line (quotes included in the range), each
    /// flagged as key when the next non-space character after it is ":".
    private static func quotedTokens(_ line: String) -> [(Range<Int>, isKey: Bool)] {
        let chars = Array(line)
        var result: [(Range<Int>, Bool)] = []
        var i = 0
        while i < chars.count {
            guard chars[i] == "\"" else { i += 1; continue }
            let start = i
            i += 1
            while i < chars.count {
                if chars[i] == "\\" { i += 2; continue }
                if chars[i] == "\"" { break }
                i += 1
            }
            guard i < chars.count else { break }  // unterminated — no tint
            let end = i + 1
            var j = end
            while j < chars.count, chars[j] == " " { j += 1 }
            let isKey = j < chars.count && chars[j] == ":"
            result.append((start ..< end, isKey))
            i = end
        }
        return result
    }
}
