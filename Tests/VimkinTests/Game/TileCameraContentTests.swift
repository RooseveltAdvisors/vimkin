import Foundation
import Testing
@testable import Vimkin

/// The camera clamp walked over the REAL World 1 levels — no authored level can
/// be walked in a way that opens the sea past the world's edge. (The clamp
/// policy itself is pinned by `TileCameraTests` — unit tier.)
@Suite("Game: the camera holds on every real World 1 level", .tags(.integration))
struct TileCameraContentTests {

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
