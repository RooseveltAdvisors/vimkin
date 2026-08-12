import Foundation
import Testing
@testable import Vimkin

/// The game world's geometry is BufferLayout's geometry — that is the whole
/// point of sharing it with the editor. These tests pin the adapter (y-axis
/// flip, inset, scroll) and, critically, that the grid math is DELEGATED and
/// not re-derived.
@Suite("Game: tile-world geometry (BufferLayout bridge)")
struct GameGeometryTests {

    private let lines = ["alpha", "beta", "gamma", "delta"]

    private func geometry(
        viewport: LayoutSize = LayoutSize(width: 400, height: 300)
    ) -> GameGeometry {
        GameGeometry.make(
            lines: lines,
            cellSize: LayoutSize(width: 10, height: 20),
            viewportSize: viewport,
            inset: LayoutSize(width: 20, height: 10)
        )
    }

    @Test("cell geometry comes from BufferLayout, not a private copy")
    func gridMathIsDelegated() {
        let g = geometry()
        #expect(g.layout.cellRect(line: 2, col: 3)
            == LayoutRect(x: 30, y: 40, width: 10, height: 20))
        #expect(g.contentHeight == 80)
    }

    @Test("the y axis flips: line 0 sits at the TOP of the scene")
    func yAxisFlips() {
        let g = geometry()
        let top = g.scenePoint(line: 0, col: 0)
        let bottom = g.scenePoint(line: 3, col: 0)
        #expect(top.y > bottom.y, "line 0 must be above line 3 in SpriteKit space")
        // Top line's bottom edge = inset + (contentHeight - cellHeight).
        #expect(top.y == 10 + (80 - 20))
        #expect(bottom.y == 10)
    }

    @Test("the inset offsets the whole world, and columns run left to right")
    func insetAndColumns() {
        let g = geometry()
        #expect(g.scenePoint(line: 0, col: 0).x == 20)
        #expect(g.scenePoint(line: 0, col: 4).x == 20 + 40)
    }

    @Test("cell centres sit half a cell in from the cell origin")
    func centresAreCentred() {
        let g = geometry()
        let origin = g.scenePoint(line: 1, col: 1)
        let centre = g.sceneCenter(line: 1, col: 1)
        #expect(centre.x == origin.x + 5)
        #expect(centre.y == origin.y + 10)
    }

    @Test("revealing the cursor scrolls through BufferLayout and shifts the world")
    func scrollFollowsTheCursor() {
        // A viewport only three cells tall forces a vertical scroll.
        var g = GameGeometry.make(
            lines: lines,
            cellSize: LayoutSize(width: 10, height: 20),
            viewportSize: LayoutSize(width: 400, height: 60),
            inset: LayoutSize(width: 0, height: 0)
        )
        let before = g.scenePoint(line: 3, col: 0)
        g.reveal(Position(line: 3, col: 0))
        #expect(g.layout.scroll.y > 0, "the layout should have scrolled to reveal the last line")
        #expect(g.scenePoint(line: 3, col: 0).y != before.y)
    }

    @Test("only on-screen lines are reported as visible")
    func visibleLinesAreClamped() {
        let g = GameGeometry.make(
            lines: lines,
            cellSize: LayoutSize(width: 10, height: 20),
            viewportSize: LayoutSize(width: 400, height: 60),
            inset: LayoutSize(width: 0, height: 0)
        )
        let visible = g.visibleLines(count: lines.count)
        #expect(visible.lowerBound == 0)
        #expect(visible.upperBound <= lines.count)
        #expect(visible.count < lines.count, "a 3-cell viewport cannot show 4 lines")
    }

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
