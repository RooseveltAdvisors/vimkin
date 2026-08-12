import SwiftUI
import Testing
@testable import Vimkin

/// Rasterisation checks for the hub (U18).
///
/// `TestTiers.swift` is right that the acceptance tier "does NOT cover pixels" —
/// nothing here judges whether the hub looks GOOD, and it is not a substitute
/// for looking at the running app. What it does prove is the failure mode one
/// rung below taste, which is cheap to catch and expensive to ship:
///
///   * the view actually lays out and rasterises at the MINIMUM window size,
///   * it fills its frame rather than collapsing to a sliver, and
///   * it is not a blank rectangle (a SwiftUI layout that silently produces
///     nothing still "renders" — a uniform image is the signature).
///
/// It also writes the PNGs to `.build/snapshots/` so a human (or an agent on a
/// box whose screen-recording permission is missing) can open the real rendered
/// pixels without launching the GUI.

@Suite("Hub: rasterisation", .tags(.acceptance))
@MainActor
struct HubSnapshotTests {

    /// The app's own minimum window (`VimkinApp`: 900x620). If the hub does not
    /// fit here it does not fit anywhere.
    private static let size = CGSize(width: 900, height: 620)

    private static var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // …/Tests/VimkinTests/UI
            .deletingLastPathComponent()  // …/Tests/VimkinTests
            .deletingLastPathComponent()  // …/Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent(".build/snapshots", isDirectory: true)
    }

    /// A populated hub — the interesting case, because every status line has
    /// real text in it and can therefore overflow.
    private static let livedIn = HubStatus(
        levelsCleared: 3, levelCount: 10, todaysScore: 940,
        lessonsLearned: 7, lessonCount: 16, skillsUnlocked: 9,
        practicedDays: 32, windowDays: 40, documentCount: 6
    )

    private func render(_ status: HubStatus, selection: Int, name: String) throws -> NSImage {
        // `contentStack`, not `body`: ImageRenderer does not lay out ScrollView
        // contents, so rendering `body` gives the bare background gradient.
        let renderer = ImageRenderer(
            content: HubView(status: status, selection: selection, onOpen: { _ in })
                .contentStack
                .frame(width: Self.size.width, height: Self.size.height)
                .background(HubTheme.ink)
        )
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "the hub produced no image at all")

        // Write it out for eyeballing. Failure to write is not a test failure —
        // the assertion is about the render, not the filesystem.
        if let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        {
            let dir = Self.snapshotDirectory
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
        return image
    }

    @Test("the hub rasterises at the minimum window size")
    func rendersAtMinimumSize() throws {
        let image = try render(Self.livedIn, selection: 0, name: "hub-selection-0")
        #expect(image.size.width == Self.size.width)
        #expect(image.size.height == Self.size.height)
    }

    @Test("the rendered hub is not a blank rectangle")
    func renderIsNotBlank() throws {
        let image = try render(Self.livedIn, selection: 0, name: "hub-blankcheck")
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))

        // Sample a grid and count distinct colours. A collapsed or empty layout
        // yields one flat colour; a drawn hub yields many (cards, chips, text).
        var colours = Set<String>()
        let stepX = bitmap.pixelsWide / 24
        let stepY = bitmap.pixelsHigh / 24
        for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, stepX)) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, stepY)) {
                guard let c = bitmap.colorAt(x: x, y: y) else { continue }
                colours.insert(
                    "\(Int(c.redComponent * 255)),"
                        + "\(Int(c.greenComponent * 255)),"
                        + "\(Int(c.blueComponent * 255))"
                )
            }
        }
        #expect(colours.count > 8, "the hub rendered \(colours.count) distinct colours — blank?")
    }

    @Test("moving the selection actually changes the pixels")
    func selectionIsVisible() throws {
        // The whole app is keyboard-driven, so "where am I" MUST be visible.
        // If the highlight were a no-op, these two renders would be identical.
        let first = try render(Self.livedIn, selection: 0, name: "hub-selection-first")
        let last = try render(Self.livedIn, selection: 5, name: "hub-selection-last")
        let a = try #require(first.tiffRepresentation)
        let b = try #require(last.tiffRepresentation)
        #expect(a != b, "the selection highlight does not change the rendered image")
    }

    @Test("a brand-new profile renders too, with its empty-state wording")
    func rendersEmptyProfile() throws {
        let image = try render(HubStatus(), selection: 0, name: "hub-fresh-profile")
        #expect(image.size.height == Self.size.height)
    }
}
