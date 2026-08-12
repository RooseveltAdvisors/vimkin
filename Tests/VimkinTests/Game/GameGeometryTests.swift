import Foundation
import Testing
@testable import Vimkin

/// The game world's geometry is BufferLayout's geometry — that is the whole
/// point of sharing it with the editor. These tests pin the adapter (y-axis
/// flip, inset, scroll) and, critically, that the grid math is DELEGATED and
/// not re-derived.
@Suite("Game: tile-world geometry (BufferLayout bridge)", .tags(.unit))
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
        // Viewport exactly as tall as the page + insets, so there is no slack
        // to centre and the raw flip math is visible.
        let g = geometry(viewport: LayoutSize(width: 400, height: 100))
        let top = g.scenePoint(line: 0, col: 0)
        let bottom = g.scenePoint(line: 3, col: 0)
        #expect(top.y > bottom.y, "line 0 must be above line 3 in SpriteKit space")
        // Top line's bottom edge = inset + (contentHeight - cellHeight).
        #expect(top.y == 10 + (80 - 20))
        #expect(bottom.y == 10)
    }

    @Test("a short page is centred in the leftover vertical room")
    func shortPageIsCentred() {
        // 4 lines x 20pt = 80pt of page inside a 300pt viewport with 10pt
        // insets: 200pt of slack, so the page sits 100pt higher than the
        // bottom inset would put it — equal air above and below.
        let g = geometry()
        let bottomLine = g.scenePoint(line: 3, col: 0)
        #expect(bottomLine.y == 10 + 100)

        let usableHeight = 300.0 - 10 * 2
        let above = usableHeight - (bottomLine.y - 10) - 80
        let below = bottomLine.y - 10
        #expect(abs(above - below) < 0.001, "page must be vertically centred")
    }

    @Test("a narrow page is centred horizontally too")
    func narrowPageIsCentredHorizontally() {
        // Widest line "gamma"/"delta" = 5 cells x 10pt = 50pt inside a 400pt
        // viewport with 20pt insets: 310pt of slack, so 155pt each side.
        let g = geometry()
        #expect(g.scenePoint(line: 0, col: 0).x == 20 + 155)
    }

    @Test("a page taller than the viewport is not centred — it scrolls")
    func tallPageKeepsPlainInset() {
        let tall = GameGeometry.make(
            lines: Array(repeating: "x", count: 40),
            cellSize: LayoutSize(width: 10, height: 20),
            viewportSize: LayoutSize(width: 400, height: 300),
            inset: LayoutSize(width: 20, height: 10)
        )
        #expect(tall.inset.height == 10, "no slack to distribute when content overflows")
    }

    @Test("the inset offsets the whole world, and columns run left to right")
    func insetAndColumns() {
        // Viewport sized so the page fills it exactly: no centring slack, so
        // the raw inset is visible.
        let g = geometry(viewport: LayoutSize(width: 90, height: 100))
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
}
