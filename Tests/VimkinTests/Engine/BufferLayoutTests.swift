import Testing
@testable import Vimkin

// Batch 5b — BufferLayout: buffer+cursor → cell-grid geometry.
// No-wrap policy with horizontal scroll; visible-rect / scroll-to-cursor math.
// Consumed by both the editor renderer (U4) and the game world renderer (U7).

@Suite struct BufferLayoutTests {
    private var layout: BufferLayout {
        BufferLayout(
            cellSize: LayoutSize(width: 10, height: 20),
            viewportSize: LayoutSize(width: 100, height: 80)
        )
    }

    @Test func cellRectMapsLineColToGeometry() {
        let l = layout
        let r = l.cellRect(line: 2, col: 3)
        #expect(r == LayoutRect(x: 30, y: 40, width: 10, height: 20))
    }

    @Test func contentSizeCoversLongestLine() {
        let buffer = TextBuffer(text: "short\na much longer line\nmid")
        let size = layout.contentSize(for: buffer)
        #expect(size == LayoutSize(width: 180, height: 60))  // 18 cols × 10, 3 lines × 20
    }

    @Test func contentSizeOfEmptyBufferIsOneLine() {
        let buffer = TextBuffer(text: "")
        let size = layout.contentSize(for: buffer)
        #expect(size.height == 20)
        #expect(size.width == 0)
    }

    @Test func scrollToRevealCursorRightOfViewport() {
        var l = layout   // viewport 10 cols × 4 lines
        l.scrollToReveal(Position(line: 0, col: 15))
        // cell at col 15 spans x 150-160; viewport must include it: scrollX >= 60.
        #expect(l.scroll.x == 60)
        #expect(l.scroll.y == 0)
        #expect(l.isCellVisible(line: 0, col: 15))
    }

    @Test func scrollToRevealCursorBelowViewport() {
        var l = layout
        l.scrollToReveal(Position(line: 9, col: 0))
        // line 9 spans y 180-200; viewport height 80 → scrollY = 120.
        #expect(l.scroll.y == 120)
        #expect(l.isCellVisible(line: 9, col: 0))
    }

    @Test func scrollToRevealBackLeftAndUp() {
        var l = layout
        l.scrollToReveal(Position(line: 9, col: 15))
        l.scrollToReveal(Position(line: 0, col: 0))
        #expect(l.scroll == LayoutPoint(x: 0, y: 0))
    }

    @Test func scrollUnchangedWhenCursorAlreadyVisible() {
        var l = layout
        l.scrollToReveal(Position(line: 2, col: 4))
        #expect(l.scroll == LayoutPoint(x: 0, y: 0))
    }

    @Test func scrollNeverNegative() {
        var l = layout
        l.scrollToReveal(Position(line: 0, col: 0))
        #expect(l.scroll.x >= 0)
        #expect(l.scroll.y >= 0)
    }

    @Test func visibleLineRangeTracksScroll() {
        var l = layout
        #expect(l.visibleLineRange(lineCount: 100) == 0 ..< 4)
        l.scrollToReveal(Position(line: 9, col: 0))
        // scrollY 120 → lines 6-9 visible
        #expect(l.visibleLineRange(lineCount: 100) == 6 ..< 10)
    }

    @Test func visibleLineRangeClampsToBuffer() {
        let l = layout
        #expect(l.visibleLineRange(lineCount: 2) == 0 ..< 2)
    }

    @Test func visibleColRangeTracksScroll() {
        var l = layout
        l.scrollToReveal(Position(line: 0, col: 15))  // scrollX 60
        #expect(l.visibleColRange(maxLineLength: 100) == 6 ..< 16)
    }

    @Test func positionHitTestMapsPointToClampedPosition() {
        let l = layout
        let buffer = TextBuffer(text: "hello\nhi")
        #expect(l.position(at: LayoutPoint(x: 25, y: 30), in: buffer) == Position(line: 1, col: 1))
        // beyond line end clamps to last char
        #expect(l.position(at: LayoutPoint(x: 95, y: 30), in: buffer) == Position(line: 1, col: 1))
        // below buffer clamps to last line
        #expect(l.position(at: LayoutPoint(x: 0, y: 500), in: buffer) == Position(line: 1, col: 0))
    }

    @Test func partiallyVisibleCellCountsAsNotFullyVisible() {
        var l = layout
        l.scroll = LayoutPoint(x: 5, y: 0)  // col 0 half-hidden
        #expect(!l.isCellVisible(line: 0, col: 0))
        #expect(l.isCellVisible(line: 0, col: 1))
    }

    @Test func wrappingPolicyDefaultsToNone() {
        #expect(layout.wrapping == .none)
    }
}
