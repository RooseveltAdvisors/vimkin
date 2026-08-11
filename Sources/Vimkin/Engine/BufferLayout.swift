// BufferLayout.swift — buffer + cursor → cell-grid geometry, shared by the editor
// renderer (U4) and the game world renderer (U7). Pure geometry: no rendering, no
// AppKit/SwiftUI/CoreGraphics types — lightweight layout structs instead.
//
// v1 policy: no wrapping + horizontal scroll (WrappingPolicy.none).

public struct LayoutPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct LayoutSize: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct LayoutRect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public enum WrappingPolicy: String, Equatable, Sendable {
    /// v1: lines never wrap; long lines scroll horizontally.
    case none
}

/// Maps buffer coordinates (line, col) to cell-grid geometry in content space,
/// and owns the scroll state needed to keep the cursor visible in a viewport.
/// Content space: (0,0) is the top-left of the document; the viewport shows the
/// axis-aligned rect at `scroll` with size `viewportSize`.
public struct BufferLayout: Equatable, Sendable {
    public var cellSize: LayoutSize
    public var viewportSize: LayoutSize
    public var scroll: LayoutPoint
    public var wrapping: WrappingPolicy

    public init(
        cellSize: LayoutSize,
        viewportSize: LayoutSize,
        scroll: LayoutPoint = LayoutPoint(x: 0, y: 0),
        wrapping: WrappingPolicy = .none
    ) {
        self.cellSize = cellSize
        self.viewportSize = viewportSize
        self.scroll = scroll
        self.wrapping = wrapping
    }

    // MARK: - Cell geometry (content space)

    public func cellOrigin(line: Int, col: Int) -> LayoutPoint {
        LayoutPoint(x: Double(col) * cellSize.width, y: Double(line) * cellSize.height)
    }

    public func cellRect(line: Int, col: Int) -> LayoutRect {
        let origin = cellOrigin(line: line, col: col)
        return LayoutRect(x: origin.x, y: origin.y, width: cellSize.width, height: cellSize.height)
    }

    /// Total content size of a buffer (longest line × line count).
    public func contentSize(for buffer: TextBuffer) -> LayoutSize {
        let maxLen = buffer.lines.map(\.count).max() ?? 0
        return LayoutSize(
            width: Double(maxLen) * cellSize.width,
            height: Double(buffer.lineCount) * cellSize.height
        )
    }

    // MARK: - Visibility

    /// A cell is visible only when its rect lies fully inside the viewport.
    public func isCellVisible(line: Int, col: Int) -> Bool {
        let r = cellRect(line: line, col: col)
        return r.x >= scroll.x
            && r.maxX <= scroll.x + viewportSize.width
            && r.y >= scroll.y
            && r.maxY <= scroll.y + viewportSize.height
    }

    /// The half-open range of lines at least partially visible, clamped to the buffer.
    public func visibleLineRange(lineCount: Int) -> Range<Int> {
        guard cellSize.height > 0, lineCount > 0 else { return 0 ..< 0 }
        let first = max(0, Int(scroll.y / cellSize.height))
        let last = Int(((scroll.y + viewportSize.height).rounded(.up) - 1) / cellSize.height)
        return min(first, lineCount) ..< min(last + 1, lineCount)
    }

    /// The half-open range of columns at least partially visible, clamped to maxLineLength.
    public func visibleColRange(maxLineLength: Int) -> Range<Int> {
        guard cellSize.width > 0, maxLineLength > 0 else { return 0 ..< 0 }
        let first = max(0, Int(scroll.x / cellSize.width))
        let last = Int(((scroll.x + viewportSize.width).rounded(.up) - 1) / cellSize.width)
        return min(first, maxLineLength) ..< min(last + 1, maxLineLength)
    }

    // MARK: - Scroll-to-cursor

    /// Adjust scroll minimally so the cursor's cell is fully visible. Never negative.
    public mutating func scrollToReveal(_ cursor: Position) {
        let r = cellRect(line: cursor.line, col: cursor.col)
        if r.x < scroll.x {
            scroll.x = r.x
        } else if r.maxX > scroll.x + viewportSize.width {
            scroll.x = r.maxX - viewportSize.width
        }
        if r.y < scroll.y {
            scroll.y = r.y
        } else if r.maxY > scroll.y + viewportSize.height {
            scroll.y = r.maxY - viewportSize.height
        }
        scroll.x = max(0, scroll.x)
        scroll.y = max(0, scroll.y)
    }

    // MARK: - Hit testing

    /// Map a content-space point to the nearest valid normal-mode buffer position.
    public func position(at point: LayoutPoint, in buffer: TextBuffer) -> Position {
        guard cellSize.width > 0, cellSize.height > 0 else { return Position(line: 0, col: 0) }
        let rawLine = Int((point.y / cellSize.height).rounded(.down))
        let line = max(0, min(buffer.lineCount - 1, rawLine))
        let rawCol = Int((point.x / cellSize.width).rounded(.down))
        let col = buffer.clampColForNormal(rawCol, line: line)
        return Position(line: line, col: col)
    }
}
