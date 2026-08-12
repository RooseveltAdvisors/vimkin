import SwiftUI
import Testing
@testable import Vimkin

/// Rasterisation checks for the launcher (U20) — the same instrument
/// `HubSnapshotTests` uses, and for the same reason: the display box's
/// screen-recording permission is denied, so `ImageRenderer` is the only way to
/// look at real drawn pixels without a human at the machine.
///
/// HONEST LIMIT (as `TestTiers.swift` says of this tier): nothing here judges
/// whether the launcher looks GOOD, and `ImageRenderer` does not lay out
/// `ScrollView` contents, so the results LIST is not what is being proved. What
/// is proved is the rung below taste: the front door lays out at the panel's
/// real size, draws its which-key chips rather than collapsing, and the `?` map
/// fits inside the card it has to fit inside.
@Suite("Launcher: rasterisation of the front door", .tags(.acceptance))
@MainActor
struct LauncherRasterTests {

    /// `OverlayPanel.cardSize` — the panel the launcher actually lives in.
    private static let size = OverlayPanel.cardSize

    private static var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // …/Tests/VimkinTests/Overlay
            .deletingLastPathComponent()  // …/Tests/VimkinTests
            .deletingLastPathComponent()  // …/Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent(".build/snapshots", isDirectory: true)
    }

    private func write(_ image: NSImage, name: String) {
        guard let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        let dir = Self.snapshotDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String) throws -> NSImage {
        let renderer = ImageRenderer(
            content:
                view
                .frame(width: size.width, height: size.height)
                .background(OverlayStyle.background)
        )
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "\(name) produced no image at all")
        write(image, name: name)
        return image
    }

    private func launcher(query: String, showMap: Bool = false) -> OverlaySearchView {
        OverlaySearchView(
            database: (try? CommandDatabase.load()) ?? CommandDatabase(commands: []),
            onPractice: { _ in },
            onOpenSurface: { _ in },
            onDismiss: {},
            initialQuery: query,
            initialShowMap: showMap
        )
    }

    /// Count distinct sampled colours. A collapsed or empty layout yields one
    /// flat colour; a drawn card yields many (keycaps, chips, text).
    private func distinctColours(_ image: NSImage) throws -> Int {
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var colours = Set<String>()
        let stepX = max(1, bitmap.pixelsWide / 24)
        let stepY = max(1, bitmap.pixelsHigh / 24)
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
                guard let c = bitmap.colorAt(x: x, y: y) else { continue }
                colours.insert(
                    "\(Int(c.redComponent * 255)),"
                        + "\(Int(c.greenComponent * 255)),"
                        + "\(Int(c.blueComponent * 255))"
                )
            }
        }
        return colours.count
    }

    @Test("the front door rasterises at the panel's real size, and is not blank")
    func frontDoorRenders() throws {
        let image = try render(launcher(query: ""), size: Self.size, name: "launcher-front-door")
        #expect(image.size.width == Self.size.width)
        #expect(image.size.height == Self.size.height)
        #expect(try distinctColours(image) > 8, "the launcher rendered nearly flat — blank?")
    }

    /// The destinations dim while a query is running (they stay on screen, but
    /// the letters now type). If that state change were a no-op the two renders
    /// would be byte-identical.
    @Test("typing visibly changes the card")
    func typingChangesTheCard() throws {
        let empty = try render(launcher(query: ""), size: Self.size, name: "launcher-empty-query")
        let typed = try render(
            launcher(query: "delete inside quotes"), size: Self.size, name: "launcher-typing"
        )
        let a = try #require(empty.tiffRepresentation)
        let b = try #require(typed.tiffRepresentation)
        #expect(a != b, "the launcher looks identical whether or not you are typing")
    }

    /// The `?` map has to fit inside the 640x420 panel with its 16pt inset —
    /// a which-key popup that is taller than its window shows half a map.
    @Test("the ? map draws, and fits inside the launcher panel")
    func mapFitsThePanel() throws {
        let card = LauncherMapCard(map: SurfaceKeys.launcher)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "the ? map produced no image at all")
        write(image, name: "launcher-key-map")

        #expect(image.size.width == 520)
        #expect(
            image.size.height <= Self.size.height - 32,
            "the ? map is \(image.size.height)pt tall — it does not fit the panel"
        )
        #expect(try distinctColours(image) > 8, "the ? map rendered nearly flat — blank?")
    }
}
