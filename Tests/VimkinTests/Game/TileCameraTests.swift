import Foundation
import Testing
@testable import Vimkin

/// The camera is the difference between "a page" and "a world you walk into".
/// These tests pin the two halves of its policy: a world bigger than the window
/// follows the player but never opens up the sea past its own edge, and a world
/// smaller than the window ignores the player and stays centred.
@Suite("Game: camera follow + clamp")
struct TileCameraTests {

    /// A world 2000x1200 sitting at (100, 50); a 800x600 window.
    private let world = LayoutRect(x: 100, y: 50, width: 2000, height: 1200)
    private let viewport = LayoutSize(width: 800, height: 600)

    private func camera(_ x: Double, _ y: Double, margin: Double = 0) -> LayoutPoint {
        TileCamera.clamp(
            target: LayoutPoint(x: x, y: y), world: world, viewport: viewport, margin: margin
        )
    }

    // MARK: - A world bigger than the window

    @Test("in open world the camera sits exactly on the player")
    func followsThePlayer() {
        #expect(camera(1000, 600) == LayoutPoint(x: 1000, y: 600))
    }

    @Test("the camera never scrolls past the left or bottom edge")
    func clampsAtTheNearEdges() {
        let point = camera(0, 0)
        #expect(point.x == 100 + 400, "half a viewport in from the world's left edge")
        #expect(point.y == 50 + 300)
    }

    @Test("the camera never scrolls past the right or top edge")
    func clampsAtTheFarEdges() {
        let point = camera(9_999, 9_999)
        #expect(point.x == 2100 - 400)
        #expect(point.y == 1250 - 300)
    }

    @Test("a clamped camera shows the world's edge and no more")
    func noSeaBeyondTheEdge() {
        let left = camera(-500, 600)
        #expect(left.x - viewport.width / 2 == world.x, "the world's edge is flush with the window")
        let right = camera(99_999, 600)
        #expect(right.x + viewport.width / 2 == world.maxX)
    }

    @Test("a margin lets exactly one tile of sea show past the edge")
    func marginAllowsOneTile() {
        let left = camera(-500, 600, margin: 28)
        #expect(left.x - viewport.width / 2 == world.x - 28)
    }

    @Test("the axes are independent — wide-and-short follows x, centres y")
    func axesAreIndependent() {
        let wideShort = LayoutRect(x: 0, y: 0, width: 4000, height: 200)
        let point = TileCamera.clamp(
            target: LayoutPoint(x: 2500, y: 180), world: wideShort, viewport: viewport
        )
        #expect(point.x == 2500, "follows horizontally: the world is wider than the window")
        #expect(point.y == 100, "stays centred vertically: the world is shorter than the window")
    }

    // MARK: - A world smaller than the window

    @Test("a world smaller than the viewport stays centred, wherever the player is")
    func smallWorldsStayCentred() {
        let small = LayoutRect(x: 200, y: 100, width: 300, height: 200)
        let atOneCorner = TileCamera.clamp(
            target: LayoutPoint(x: 200, y: 100), world: small, viewport: viewport
        )
        let atTheOther = TileCamera.clamp(
            target: LayoutPoint(x: 500, y: 300), world: small, viewport: viewport
        )
        #expect(atOneCorner == LayoutPoint(x: 350, y: 200))
        #expect(atOneCorner == atTheOther, "the camera must not drift with the player")
    }

    @Test("a world exactly the size of the viewport is centred, not clamped")
    func exactFitIsCentred() {
        let exact = LayoutRect(x: 0, y: 0, width: 800, height: 600)
        let point = TileCamera.clamp(
            target: LayoutPoint(x: 0, y: 0), world: exact, viewport: viewport
        )
        #expect(point == LayoutPoint(x: 400, y: 300))
    }

    // MARK: - The camera over a real level

    @Test("walking a real level never shows the sea past the world's edge")
    func realLevelsStayInBounds() throws {
        let tile = GameGeometry.worldTile
        for level in try world1().levels {
            let terrain = TerrainMap(document: level.document)
            let bounds = LayoutRect(
                x: 0, y: 0,
                width: Double(terrain.columnCount) * tile.width,
                height: Double(terrain.rowCount) * tile.height
            )
            let viewport = LayoutSize(width: 960, height: 600)
            for line in 0..<terrain.rowCount {
                for col in stride(from: 0, to: max(1, terrain.columnCount), by: 5) {
                    let point = TileCamera.clamp(
                        target: LayoutPoint(
                            x: Double(col) * tile.width, y: Double(line) * tile.height
                        ),
                        world: bounds, viewport: viewport, margin: tile.width
                    )
                    if bounds.width + tile.width * 2 > viewport.width {
                        #expect(point.x - viewport.width / 2 >= bounds.x - tile.width - 0.001,
                                "\(level.id) scrolled past the left edge")
                        #expect(point.x + viewport.width / 2 <= bounds.maxX + tile.width + 0.001,
                                "\(level.id) scrolled past the right edge")
                    }
                    #expect(point.y.isFinite && point.x.isFinite, "\(level.id)")
                }
            }
        }
    }
}
