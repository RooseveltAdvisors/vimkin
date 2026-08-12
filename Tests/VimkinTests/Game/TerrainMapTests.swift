import Foundation
import Testing
@testable import Vimkin

/// The document IS the map, so the classification that turns buffer cells into
/// terrain is game content, not decoration. These tests pin the five kinds, the
/// two rules that make islands read as islands (past-the-end is sea, blank
/// lines are sea) and the island rim the renderer draws from.
@Suite("Game: terrain classification (the document as a tile world)")
struct TerrainMapTests {

    private let doc = [
        "# Heading",
        "ab cd",
        "",
        "  indented",
        "- listed",
    ]

    private var map: TerrainMap { TerrainMap(lines: doc) }

    // MARK: - The five kinds

    @Test("a non-space character is a letter tile")
    func lettersAreTiles() {
        #expect(map.kind(line: 1, col: 0) == .letter)
        #expect(map.kind(line: 1, col: 1) == .letter)
        #expect(map.kind(line: 1, col: 3) == .letter)
    }

    @Test("a space inside a prose line is bare parchment, not sea")
    func interiorSpacesAreGround() {
        #expect(map.kind(line: 1, col: 2) == .parchment)
    }

    @Test("everything past the end of a line is ink sea")
    func pastTheEndIsSea() {
        // "ab cd" is 5 long: col 5 and everything right of it is open water.
        #expect(map.kind(line: 1, col: 4) == .letter)
        #expect(map.kind(line: 1, col: 5) == .ink)
        #expect(map.kind(line: 1, col: 40) == .ink)
    }

    @Test("a blank line is entirely ink sea — that is what separates islands")
    func blankLinesAreSea() {
        for col in 0..<8 {
            #expect(map.kind(line: 2, col: col) == .ink, "col \(col)")
        }
    }

    @Test("a line of nothing but spaces is sea too")
    func whitespaceOnlyLinesAreSea() {
        let spaced = TerrainMap(lines: ["   ", "x"])
        #expect(spaced.lineStyles[0] == .blank)
        #expect(spaced.kind(line: 0, col: 1) == .ink)
    }

    @Test("trailing whitespace is sea, not an invisible parchment nub")
    func trailingWhitespaceIsSea() {
        let trailing = TerrainMap(lines: ["hi   "])
        #expect(trailing.contentLengths[0] == 2)
        #expect(trailing.kind(line: 0, col: 2) == .ink)
    }

    @Test("a heading line is one signpost banner, glyphs included")
    func headingsAreBanners() {
        #expect(map.lineStyles[0] == .heading)
        #expect(map.kind(line: 0, col: 0) == .headingBanner)  // the '#'
        #expect(map.kind(line: 0, col: 1) == .headingBanner)  // the space
        #expect(map.kind(line: 0, col: 5) == .headingBanner)  // a letter
    }

    @Test("an indented line carries a ruled path in its gaps")
    func indentedLinesArePaths() {
        #expect(map.lineStyles[3] == .path)
        #expect(map.kind(line: 3, col: 0) == .ruledPath)
        #expect(map.kind(line: 3, col: 2) == .letter)
    }

    @Test("a list line is a path too, and its marker is still a letter tile")
    func listLinesArePaths() {
        #expect(map.lineStyles[4] == .path)
        #expect(map.kind(line: 4, col: 0) == .letter)  // the '-'
        #expect(map.kind(line: 4, col: 1) == .ruledPath)  // the gap after it
    }

    @Test("prose that merely starts with a dash is not a list")
    func dashInProseIsNotAList() {
        let prose = TerrainMap(lines: ["-40 degrees outside"])
        #expect(prose.lineStyles[0] == .prose)
        #expect(prose.kind(line: 0, col: 3) == .parchment)
    }

    @Test("numbered list markers count")
    func numberedListsArePaths() {
        #expect(TerrainMap(lines: ["1. first"]).lineStyles[0] == .path)
        #expect(TerrainMap(lines: ["12) later"]).lineStyles[0] == .path)
        #expect(TerrainMap(lines: ["1985 was a year"]).lineStyles[0] == .prose)
    }

    // MARK: - Bounds

    @Test("out of bounds is sea in every direction, so probing is safe")
    func outOfBoundsIsSea() {
        #expect(map.kind(line: -1, col: 0) == .ink)
        #expect(map.kind(line: 99, col: 0) == .ink)
        #expect(map.kind(line: 1, col: -1) == .ink)
    }

    @Test("the world's column count is the widest line's content")
    func columnCount() {
        #expect(map.columnCount == 10)  // "  indented"
        #expect(map.rowCount == 5)
    }

    // MARK: - The island rim

    @Test("land touching sea is an island edge; interior land is not")
    func islandEdges() {
        // "ab cd" is a one-line island: blank line below, heading above with a
        // shorter reach — so every cell of it touches sea somewhere.
        #expect(map.isIslandEdge(line: 1, col: 0))
        #expect(map.isIslandEdge(line: 1, col: 4))

        // A 3x3 block of land: only the middle cell is interior.
        let block = TerrainMap(lines: ["xxx", "xxx", "xxx"])
        #expect(block.isIslandEdge(line: 0, col: 1))
        #expect(block.isIslandEdge(line: 1, col: 0))
        #expect(!block.isIslandEdge(line: 1, col: 1), "the middle of a block is interior")
    }

    @Test("sea is never an island edge")
    func seaIsNotAnEdge() {
        #expect(!map.isIslandEdge(line: 2, col: 0))
        #expect(!map.isIslandEdge(line: 1, col: 20))
    }

    @Test("the rim is drawn only on the sides that actually face the sea")
    func rimSidesAreDirectional() {
        let block = TerrainMap(lines: ["xxx", "xxx", "xxx"])
        #expect(block.seaFacingSides(line: 0, col: 0) == [.top, .leading])
        #expect(block.seaFacingSides(line: 2, col: 2) == [.bottom, .trailing])
        #expect(block.seaFacingSides(line: 1, col: 1).isEmpty)
    }

    @Test("a ragged line end makes the rim ragged — the torn-paper edge")
    func raggedEndsMakeRaggedRims() {
        let ragged = TerrainMap(lines: ["xxxxx", "xx"])
        // Line 0's cols 2-4 hang over open water on their underside.
        #expect(ragged.seaFacingSides(line: 0, col: 3).contains(.bottom))
        #expect(!ragged.seaFacingSides(line: 0, col: 1).contains(.bottom))
    }

    // MARK: - Batching (the renderer must not walk the grid itself)

    @Test("contiguous same-kind cells collapse into runs, and sea is excluded")
    func runsBatchTheGrid() {
        let runs = TerrainMap(lines: ["ab cd"]).landRuns()
        #expect(runs.count == 3)
        #expect(runs[0].kind == .letter)
        #expect(runs[0].columns == 0..<2)
        #expect(runs[1].kind == .parchment)
        #expect(runs[1].columns == 2..<3)
        #expect(runs[2].columns == 3..<5)
        #expect(runs.allSatisfy { $0.kind != .ink }, "the sea is drawn by the background")
    }

    @Test("a blank line contributes no runs and no land span")
    func blankLinesContributeNothing() {
        #expect(map.landRuns().allSatisfy { $0.line != 2 })
        #expect(map.landSpan(line: 2) == nil)
        #expect(map.landSpan(line: 1) == 0..<5)
    }

    @Test("every land cell is covered by exactly one run")
    func runsCoverAllLand() throws {
        for level in try world1().levels {
            let terrain = TerrainMap(document: level.document)
            var covered: Set<[Int]> = []
            for run in terrain.landRuns() {
                for col in run.columns {
                    #expect(terrain.kind(line: run.line, col: col) == run.kind)
                    #expect(covered.insert([run.line, col]).inserted, "double-covered cell")
                }
            }
            for line in 0..<terrain.rowCount {
                for col in 0..<terrain.contentLengths[line]
                where terrain.kind(line: line, col: col).isLand {
                    #expect(covered.contains([line, col]), "\(level.id) missed (\(line),\(col))")
                }
            }
        }
    }

    @Test("every real level classifies without crashing and has land to stand on")
    func realLevelsHaveTerrain() throws {
        for level in try world1().levels {
            let terrain = TerrainMap(document: level.document)
            #expect(terrain.rowCount > 0, "\(level.id)")
            #expect(terrain.columnCount > 0, "\(level.id)")
            // Every Vimkin must be standing on land, never adrift in the sea.
            for vimkin in level.vimkins {
                let kind = terrain.kind(line: vimkin.position.line, col: vimkin.position.col)
                #expect(kind.isLand, "\(level.id)/\(vimkin.id) is floating in the ink")
            }
        }
    }
}
