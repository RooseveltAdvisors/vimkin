// TileCamera.swift — where the camera is allowed to be (plan U13).
//
// The world scrolls by MOVING A CAMERA over a world laid out once in fixed
// scene coordinates — not by re-laying-out the terrain every key. This file is
// the whole policy, and it is pure math so it can be tested without SpriteKit:
//
//  * a world BIGGER than the viewport follows the player, clamped so the sea
//    never opens up more than `margin` beyond the world's edge;
//  * a world SMALLER than the viewport ignores the player entirely and stays
//    centred (the behaviour `GameGeometry` already gives short pages — the
//    camera must not fight it by drifting off to one side).
//
// Each axis is decided independently: a wide, short page follows horizontally
// and stays centred vertically, which is exactly right for a document world.

import Foundation

public enum TileCamera {

    /// Where the camera should sit to look at `target`.
    ///
    /// - Parameters:
    ///   - target: the point the camera wants to centre on (the player).
    ///   - world: the bounds of the drawn world in scene space.
    ///   - viewport: the size of the visible area, in the same space.
    ///   - margin: how much sea may show past the world's edge — one tile.
    public static func clamp(
        target: LayoutPoint,
        world: LayoutRect,
        viewport: LayoutSize,
        margin: Double = 0
    ) -> LayoutPoint {
        LayoutPoint(
            x: clamp(
                target.x, low: world.x - margin, high: world.maxX + margin,
                extent: viewport.width
            ),
            y: clamp(
                target.y, low: world.y - margin, high: world.maxY + margin,
                extent: viewport.height
            )
        )
    }

    /// One axis. `low`/`high` already include the margin.
    static func clamp(_ target: Double, low: Double, high: Double, extent: Double) -> Double {
        let span = high - low
        let centre = (low + high) / 2
        // The world fits: there is nothing to scroll, so stay centred. Any
        // follow here would only slide the page around inside the window.
        guard span > extent else { return centre }
        return min(max(target, low + extent / 2), high - extent / 2)
    }
}
