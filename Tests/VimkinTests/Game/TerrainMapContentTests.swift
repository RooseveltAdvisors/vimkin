import Foundation
import Testing
@testable import Vimkin

/// The terrain classifier run over the REAL World 1 content: every authored
/// level must classify into a coherent tile world with land under every Vimkin.
/// (The classifier's own rules are pinned by `TerrainMapTests` — unit tier.)
@Suite("Game: real World 1 levels classify into a coherent tile world", .tags(.integration))
struct TerrainMapContentTests {

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
