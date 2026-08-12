// TerrainMap.swift — the document read as TERRAIN (plan U13).
//
// The level's text buffer IS the world map. That is deliberate and load-bearing:
// it is what makes the motions authentic Vim — `w` really jumps a word because
// the world really is words. This file is the only place that decides what a
// buffer cell LOOKS like; the scene draws whatever this says, and nothing else
// in the game is allowed to re-derive it.
//
// The paper world (assets/briefs/style-guide.md):
//
//   ink          — the sea. Blank lines, and everything past the end of a line.
//   parchment    — bare paper. A space inside a line: walkable ground.
//   letter       — a raised letter tile. A non-space character.
//   headingBanner— a signpost strip. Every cell of a `#`/`##` heading line.
//   ruledPath    — a ruled notebook line. The gaps on an indented or list line.
//
// Pure Swift + Foundation: no SpriteKit, no SwiftUI. Fully testable, and the
// renderer's batching (contiguous runs, island rim) is derived here too so the
// scene never walks the grid itself.

import Foundation

/// What kind of ground one buffer cell is.
public enum TerrainKind: String, Equatable, Hashable, Sendable, CaseIterable {
    /// The sea of ink the parchment islands float in.
    case ink
    /// Bare paper — a space inside a line.
    case parchment
    /// A letter tile: a raised parchment tile carrying one glyph.
    case letter
    /// A heading strip: the whole `#` line reads as one signpost banner.
    case headingBanner
    /// A ruled notebook line running under an indented or list line.
    case ruledPath

    /// True for everything that is part of an island (i.e. not the sea).
    public var isLand: Bool { self != .ink }

    /// The tile-art basename this kind loads from `Content/tiles/`, when the
    /// generated tileset is present in the bundle.
    public var textureName: String {
        switch self {
        case .ink: return "tile-ink"
        case .parchment: return "tile-parchment"
        case .letter: return "tile-letter"
        case .headingBanner: return "tile-margin-wall"
        case .ruledPath: return "tile-ruled-path"
        }
    }
}

/// A classified grid over a document — the world map the scene draws.
public struct TerrainMap: Equatable, Sendable {

    /// How a whole LINE reads, which decides the motif its cells wear.
    public enum LineStyle: String, Equatable, Sendable {
        /// Empty or all-whitespace: open sea.
        case blank
        /// A Markdown heading — a signpost banner.
        case heading
        /// Indented, or a list item — a ruled path runs under it.
        case path
        /// Ordinary prose.
        case prose
    }

    /// The document, exactly as the engine holds it.
    public let lines: [String]
    /// Per-line style (same count as `lines`).
    public let lineStyles: [LineStyle]
    /// Length of each line AFTER trailing whitespace is dropped — trailing
    /// spaces are indistinguishable from the sea, so they are the sea.
    public let contentLengths: [Int]

    public var rowCount: Int { lines.count }
    /// The widest line's content length: the world's column count.
    public var columnCount: Int { contentLengths.max() ?? 0 }

    // MARK: - Init

    public init(lines: [String]) {
        self.lines = lines
        self.contentLengths = lines.map(Self.contentLength)
        self.lineStyles = zip(lines, contentLengths).map { line, length in
            Self.style(of: line, contentLength: length)
        }
    }

    public init(document: String) {
        self.init(lines: TextBuffer(text: document).lines)
    }

    /// Characters up to the last non-whitespace one.
    static func contentLength(_ line: String) -> Int {
        var length = 0
        for (index, character) in line.enumerated() where !character.isWhitespace {
            length = index + 1
        }
        return length
    }

    static func style(of line: String, contentLength: Int) -> LineStyle {
        guard contentLength > 0 else { return .blank }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return .heading }
        if line.first?.isWhitespace == true { return .path }
        if isListMarker(trimmed) { return .path }
        return .prose
    }

    /// `- item`, `* item`, `+ item`, `1. item`, `2) item`.
    static func isListMarker(_ trimmed: String) -> Bool {
        guard let first = trimmed.first else { return false }
        if first == "-" || first == "*" || first == "+" {
            // `- item` is a list; a bare `-` or a `---` rule counts as one too.
            // `-42 degrees` does not — the marker must be followed by a space.
            return trimmed.count == 1
                || trimmed.dropFirst().first == " "
                || trimmed.allSatisfy { $0 == first }
        }
        guard first.isNumber else { return false }
        let digits = trimmed.prefix { $0.isNumber }
        let rest = trimmed.dropFirst(digits.count)
        return rest.first == "." || rest.first == ")"
    }

    // MARK: - Classification

    /// The terrain kind of one cell. Out-of-bounds is sea, so callers may probe
    /// freely past the edges of the world.
    public func kind(line: Int, col: Int) -> TerrainKind {
        guard line >= 0, line < lines.count, col >= 0 else { return .ink }
        // Beyond the end of a line — and every cell of a blank line — is sea.
        guard col < contentLengths[line] else { return .ink }

        switch lineStyles[line] {
        case .blank:
            return .ink
        case .heading:
            // The whole strip is the signpost; its glyphs ride on top of it.
            return .headingBanner
        case .path, .prose:
            if character(line: line, col: col)?.isWhitespace == false { return .letter }
            return lineStyles[line] == .path ? .ruledPath : .parchment
        }
    }

    /// The character at a cell, or nil past the end of the line.
    public func character(line: Int, col: Int) -> Character? {
        guard line >= 0, line < lines.count, col >= 0 else { return nil }
        let text = lines[line]
        guard col < text.count else { return nil }
        return text[text.index(text.startIndex, offsetBy: col)]
    }

    /// True when a cell is land whose 4-neighbourhood touches the sea — the
    /// torn-paper rim of an island. This single treatment is what makes the
    /// page read as a MAP rather than as a block of text.
    public func isIslandEdge(line: Int, col: Int) -> Bool {
        guard kind(line: line, col: col).isLand else { return false }
        return !kind(line: line - 1, col: col).isLand
            || !kind(line: line + 1, col: col).isLand
            || !kind(line: line, col: col - 1).isLand
            || !kind(line: line, col: col + 1).isLand
    }

    /// Which of a land cell's four sides face the sea (renderer draws the rim
    /// along exactly these). Empty for an interior cell or for sea itself.
    public func seaFacingSides(line: Int, col: Int) -> Set<Side> {
        guard kind(line: line, col: col).isLand else { return [] }
        var sides: Set<Side> = []
        if !kind(line: line - 1, col: col).isLand { sides.insert(.top) }
        if !kind(line: line + 1, col: col).isLand { sides.insert(.bottom) }
        if !kind(line: line, col: col - 1).isLand { sides.insert(.leading) }
        if !kind(line: line, col: col + 1).isLand { sides.insert(.trailing) }
        return sides
    }

    public enum Side: String, Equatable, Hashable, Sendable, CaseIterable {
        case top, bottom, leading, trailing
    }

    // MARK: - Batching (so the scene builds few nodes, not one per cell)

    /// One horizontal run of identical terrain.
    public struct Run: Equatable, Sendable {
        public let line: Int
        public let kind: TerrainKind
        /// Half-open column range.
        public let columns: Range<Int>

        public init(line: Int, kind: TerrainKind, columns: Range<Int>) {
            self.line = line
            self.kind = kind
            self.columns = columns
        }
    }

    /// Contiguous same-kind runs across the whole world, sea excluded. The
    /// renderer turns each kind's runs into ONE batched node.
    public func landRuns() -> [Run] {
        var runs: [Run] = []
        for line in 0..<rowCount {
            var start = 0
            var current: TerrainKind?
            for col in 0...max(0, contentLengths[line]) {
                let kind = col < contentLengths[line] ? self.kind(line: line, col: col) : .ink
                if kind != current {
                    if let current, current.isLand {
                        runs.append(Run(line: line, kind: current, columns: start..<col))
                    }
                    current = kind
                    start = col
                }
            }
        }
        return runs
    }

    /// The full span of land on a line (col 0 up to its content length), used
    /// for the island's silhouette, its shadow, and the notebook margin rule.
    public func landSpan(line: Int) -> Range<Int>? {
        guard line >= 0, line < rowCount, contentLengths[line] > 0 else { return nil }
        return 0..<contentLengths[line]
    }

    /// Every land cell that touches the sea, with the sides that do.
    public func rimSegments() -> [(line: Int, col: Int, sides: Set<Side>)] {
        var out: [(line: Int, col: Int, sides: Set<Side>)] = []
        for line in 0..<rowCount {
            for col in 0..<contentLengths[line] {
                let sides = seaFacingSides(line: line, col: col)
                if !sides.isEmpty { out.append((line, col, sides)) }
            }
        }
        return out
    }
}
