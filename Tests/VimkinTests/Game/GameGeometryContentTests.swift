import Foundation
import Testing
@testable import Vimkin

/// The tile-world geometry adapter measured against the REAL World 1 levels.
/// (The adapter's own math is pinned by `GameGeometryTests` — unit tier.)
@Suite("Game: real World 1 levels fit the tile grid", .tags(.integration))
struct GameGeometryContentTests {

    @Test("a real level's geometry covers every Vimkin's cell")
    func realLevelsFitTheGrid() throws {
        for level in try world1().levels {
            let lines = TextBuffer(text: level.document).lines
            let g = GameGeometry.make(
                lines: lines,
                cellSize: LayoutSize(width: 10.2, height: 24.65),
                viewportSize: LayoutSize(width: 960, height: 600)
            )
            for vimkin in level.vimkins {
                let point = g.sceneCenter(line: vimkin.position.line, col: vimkin.position.col)
                #expect(point.x.isFinite && point.y.isFinite, "\(level.id)/\(vimkin.id)")
                #expect(point.x >= 0, "\(level.id)/\(vimkin.id) is off the left edge")
            }
        }
    }
}
