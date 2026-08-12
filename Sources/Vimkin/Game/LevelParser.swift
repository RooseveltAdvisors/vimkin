// LevelParser.swift — the level-file reader (plan U7).
//
// Level files are `YAML front-matter + document body`. Rather than pull in a
// YAML dependency (the zero-third-party-deps stance), this parses a deliberately
// RESTRICTED, fully-specified subset — the only shapes the schema uses:
//
//   key: scalar                       (quotes optional; `#` is NOT a comment,
//                                      because documents are full of them)
//   key: [a, b, c]                    flow sequence of scalars
//   key:                              block sequence of flow mappings
//     - { k: v, k: v }
//
// Anything outside that subset is a hard parse error naming the offending line,
// so a malformed level fails loudly at load (and in the schema test) rather
// than silently losing a Vimkin.

import Foundation

public enum LevelError: Error, Equatable, CustomStringConvertible {
    case missingFrontMatter(file: String)
    case unterminatedFrontMatter(file: String)
    case malformedLine(file: String, line: String)
    case missingKey(file: String, key: String)
    case badInteger(file: String, key: String, value: String)
    case unknownRescue(file: String, value: String)
    case rescueNeedsText(file: String, value: String)
    case vimkinNeedsPosition(file: String, name: String)
    case duplicateVimkin(file: String, name: String)
    case emptyDocument(file: String)

    public var description: String {
        switch self {
        case .missingFrontMatter(let f): return "\(f): file does not start with `---` front-matter"
        case .unterminatedFrontMatter(let f): return "\(f): front-matter is never closed with `---`"
        case .malformedLine(let f, let l): return "\(f): cannot parse front-matter line `\(l)`"
        case .missingKey(let f, let k): return "\(f): missing required front-matter key `\(k)`"
        case .badInteger(let f, let k, let v): return "\(f): `\(k)` is not an integer: `\(v)`"
        case .unknownRescue(let f, let v): return "\(f): unknown rescue kind `\(v)`"
        case .rescueNeedsText(let f, let v): return "\(f): rescue `\(v)` requires a `text:` field"
        case .vimkinNeedsPosition(let f, let n): return "\(f): vimkin `\(n)` needs `line:` and `col:`"
        case .duplicateVimkin(let f, let n): return "\(f): duplicate vimkin name `\(n)`"
        case .emptyDocument(let f): return "\(f): level has no document body"
        }
    }
}

/// Parses one level file into a `Level`.
public enum LevelParser {

    public static func parse(_ text: String, fileName: String) throws -> Level {
        let (frontMatter, body) = try split(text, fileName: fileName)
        let fields = try parseFrontMatter(frontMatter, fileName: fileName)

        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LevelError.emptyDocument(file: fileName)
        }

        let vimkins = try (fields.blocks["vimkins"] ?? []).map { entry -> Vimkin in
            try vimkin(from: entry, fileName: fileName)
        }
        var seen = Set<String>()
        for v in vimkins where !seen.insert(v.id).inserted {
            throw LevelError.duplicateVimkin(file: fileName, name: v.id)
        }
        let goals = try (fields.blocks["goals"] ?? []).map { entry -> RescueCondition in
            try condition(from: entry, fileName: fileName, position: position(in: entry))
        }

        return Level(
            id: try fields.requireScalar("id", fileName),
            title: try fields.requireScalar("title", fileName),
            order: try fields.requireInt("order", fileName),
            intro: fields.scalars["intro"] ?? "",
            teaches: fields.scalars["teaches"] ?? "",
            allowedCommandIDs: fields.lists["allowed"] ?? [],
            par: try fields.requireInt("par", fileName),
            solution: try fields.requireScalar("solution", fileName),
            vimkins: vimkins,
            extraGoals: goals,
            document: body
        )
    }

    // MARK: - Front-matter / body split

    private static func split(_ text: String, fileName: String) throws -> (front: [String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw LevelError.missingFrontMatter(file: fileName)
        }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            throw LevelError.unterminatedFrontMatter(file: fileName)
        }
        let front = Array(lines[1..<closing])
        var bodyLines = Array(lines[(closing + 1)...])
        // Drop exactly one blank separator line after the fence, and any
        // trailing blank lines (a stray final newline is not terrain).
        if bodyLines.first?.isEmpty == true { bodyLines.removeFirst() }
        while bodyLines.last?.isEmpty == true { bodyLines.removeLast() }
        return (front, bodyLines.joined(separator: "\n"))
    }

    // MARK: - Front-matter fields

    private struct Fields {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var blocks: [String: [[String: String]]] = [:]

        func requireScalar(_ key: String, _ file: String) throws -> String {
            guard let value = scalars[key], !value.isEmpty else {
                throw LevelError.missingKey(file: file, key: key)
            }
            return value
        }

        func requireInt(_ key: String, _ file: String) throws -> Int {
            let raw = try requireScalar(key, file)
            guard let value = Int(raw) else {
                throw LevelError.badInteger(file: file, key: key, value: raw)
            }
            return value
        }
    }

    private static func parseFrontMatter(_ lines: [String], fileName: String) throws -> Fields {
        var fields = Fields()
        var currentBlockKey: String?

        for raw in lines {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let isIndented = raw.first == " " || raw.first == "\t"
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if isIndented || trimmed.hasPrefix("- ") {
                guard let key = currentBlockKey, trimmed.hasPrefix("- ") else {
                    throw LevelError.malformedLine(file: fileName, line: raw)
                }
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard item.hasPrefix("{"), item.hasSuffix("}") else {
                    throw LevelError.malformedLine(file: fileName, line: raw)
                }
                fields.blocks[key, default: []].append(
                    try flowMapping(String(item.dropFirst().dropLast()), fileName: fileName, line: raw)
                )
                continue
            }

            guard let colon = trimmed.firstIndex(of: ":") else {
                throw LevelError.malformedLine(file: fileName, line: raw)
            }
            let key = String(trimmed[trimmed.startIndex..<colon])
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0 == "_" }) else {
                throw LevelError.malformedLine(file: fileName, line: raw)
            }

            if value.isEmpty {
                currentBlockKey = key
                fields.blocks[key] = fields.blocks[key] ?? []
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                currentBlockKey = nil
                let inner = String(value.dropFirst().dropLast())
                fields.lists[key] = splitTopLevel(inner, separator: ",")
                    .map(unquote)
                    .filter { !$0.isEmpty }
            } else {
                currentBlockKey = nil
                fields.scalars[key] = unquote(value)
            }
        }
        return fields
    }

    /// `k: v, k: "v, with comma"` → dictionary.
    private static func flowMapping(
        _ body: String, fileName: String, line: String
    ) throws -> [String: String] {
        var mapping: [String: String] = [:]
        for pair in splitTopLevel(body, separator: ",") where !pair.isEmpty {
            guard let colon = pair.firstIndex(of: ":") else {
                throw LevelError.malformedLine(file: fileName, line: line)
            }
            let key = String(pair[pair.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw LevelError.malformedLine(file: fileName, line: line) }
            mapping[key] = unquote(value)
        }
        return mapping
    }

    // MARK: - Conditions

    /// `line:` + `col:` from a flow mapping, when both are present.
    private static func position(in entry: [String: String]) -> Position? {
        guard let lineText = entry["line"], let colText = entry["col"],
              let line = Int(lineText), let col = Int(colText)
        else { return nil }
        return Position(line: line, col: col)
    }

    private static func vimkin(from entry: [String: String], fileName: String) throws -> Vimkin {
        let name = entry["name"] ?? entry["id"] ?? ""
        guard !name.isEmpty else {
            throw LevelError.missingKey(file: fileName, key: "name")
        }
        guard let position = position(in: entry) else {
            throw LevelError.vimkinNeedsPosition(file: fileName, name: name)
        }
        return Vimkin(
            id: name,
            position: position,
            condition: try condition(from: entry, fileName: fileName, position: position),
            cheer: entry["cheer"]
        )
    }

    private static func condition(
        from entry: [String: String], fileName: String, position: Position?
    ) throws -> RescueCondition {
        let kind = entry["rescue"] ?? "reach"
        func requireText() throws -> String {
            guard let text = entry["text"], !text.isEmpty else {
                throw LevelError.rescueNeedsText(file: fileName, value: kind)
            }
            return text
        }
        switch kind {
        case "reach":
            guard let position else {
                throw LevelError.vimkinNeedsPosition(file: fileName, name: entry["name"] ?? "goal")
            }
            return .cursorReaches(position)
        case "removed": return .textRemoved(try requireText())
        case "written": return .textPresent(try requireText())
        case "yanked": return .registerContains(try requireText())
        default: throw LevelError.unknownRescue(file: fileName, value: kind)
        }
    }

    // MARK: - Scalar helpers

    /// Split on a separator that is not inside double quotes.
    static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for c in text {
            if c == "\"" { inQuotes.toggle(); current.append(c); continue }
            if c == separator && !inQuotes {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    /// Strip surrounding double quotes and decode the escapes the schema needs:
    /// `\e` (Escape — solutions need it), `\n`, `\"`, `\\`. Everything else is
    /// literal. An UNQUOTED value is taken verbatim, so a document-flavored
    /// scalar full of backslashes is never mangled.
    static func unquote(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        text = String(text.dropFirst().dropLast())
        var out = ""
        var escaping = false
        for c in text {
            if escaping {
                switch c {
                case "n": out.append("\n")
                case "e": out.append("\u{1B}")
                case "t": out.append("\t")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }
}
