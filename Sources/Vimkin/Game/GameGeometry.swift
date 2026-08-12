// GameGeometry.swift — the bridge from BufferLayout to SpriteKit space (plan U7).
//
// The tile world's cell/scroll math is NOT reimplemented here: `BufferLayout`
// (U2) owns it, and the editor renderer uses the same code, so the two
// renderers cannot drift. This file is only the coordinate-system adapter:
// BufferLayout is content space with y growing DOWNWARD (line 0 at the top),
// SpriteKit is a scene with y growing UPWARD.
//
// Pure math, no SpriteKit import — testable, and reusable by U8's effects.

import Foundation

public struct GameGeometry: Equatable, Sendable {
    /// The shared layout model — the single source of grid truth.
    public var layout: BufferLayout
    /// Total document height in content space, used to flip the y axis.
    public var contentHeight: Double
    /// Padding inside the scene, in points.
    public var inset: LayoutSize

    public init(layout: BufferLayout, contentHeight: Double, inset: LayoutSize) {
        self.layout = layout
        self.contentHeight = contentHeight
        self.inset = inset
    }

    /// Builds geometry for a document at a given cell size and viewport.
    public static func make(
        lines: [String],
        cellSize: LayoutSize,
        viewportSize: LayoutSize,
        inset: LayoutSize = LayoutSize(width: 28, height: 24)
    ) -> GameGeometry {
        let content = LayoutSize(
            width: viewportSize.width - inset.width * 2,
            height: viewportSize.height - inset.height * 2
        )
        let layout = BufferLayout(
            cellSize: cellSize,
            viewportSize: LayoutSize(
                width: max(cellSize.width, content.width),
                height: max(cellSize.height, content.height)
            )
        )
        // A short document in a tall scene would otherwise pile up against the
        // bottom edge (SpriteKit's origin), leaving dead space above it.
        // Centre the page in the leftover room; taller-than-viewport documents
        // keep the plain inset and scroll as before.
        let contentHeight = Double(lines.count) * cellSize.height
        let slack = max(0, content.height - contentHeight)
        return GameGeometry(
            layout: layout,
            contentHeight: contentHeight,
            inset: LayoutSize(width: inset.width, height: inset.height + slack / 2)
        )
    }

    /// Keeps the cursor's cell inside the viewport (delegates to BufferLayout).
    public mutating func reveal(_ cursor: Position) {
        layout.scrollToReveal(cursor)
    }

    // MARK: - Coordinate conversion

    /// Scene-space point of a cell's BOTTOM-LEFT corner (SpriteKit's origin
    /// convention), with scroll and inset applied and the y axis flipped.
    public func scenePoint(line: Int, col: Int) -> LayoutPoint {
        let rect = layout.cellRect(line: line, col: col)
        return LayoutPoint(
            x: inset.width + rect.x - layout.scroll.x,
            y: inset.height + (contentHeight - rect.maxY) + layout.scroll.y
        )
    }

    /// Scene-space point of a cell's CENTER — where sprites are anchored.
    public func sceneCenter(line: Int, col: Int) -> LayoutPoint {
        let origin = scenePoint(line: line, col: col)
        return LayoutPoint(
            x: origin.x + layout.cellSize.width / 2,
            y: origin.y + layout.cellSize.height / 2
        )
    }

    /// Scene-space origin of a whole line's text run (its baseline row's
    /// bottom-left), so a line renders as ONE label instead of N glyph nodes.
    public func sceneLineOrigin(line: Int) -> LayoutPoint {
        scenePoint(line: line, col: 0)
    }

    /// Lines currently worth drawing.
    public func visibleLines(count: Int) -> Range<Int> {
        layout.visibleLineRange(lineCount: count)
    }
}
