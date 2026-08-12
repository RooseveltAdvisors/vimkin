// GameTheme.swift — the cozy-arcade palette (assets/briefs/style-guide.md).
//
// One definition, consumed by both the SpriteKit scene (SKColor) and the
// SwiftUI chrome (Color), so the world and its HUD cannot drift apart.

import SwiftUI

public enum GameTheme {
    // Palette (style guide v1)
    public static let inkNavy = Color(red: 0.090, green: 0.102, blue: 0.149)   // #171A26
    public static let plumDark = Color(red: 0.129, green: 0.110, blue: 0.220)  // #211C38
    public static let parchment = Color(red: 0.949, green: 0.922, blue: 0.867) // #F2EBDD
    public static let cursorCyan = Color(red: 0.490, green: 0.910, blue: 0.847) // #7DE8D8
    public static let vimkinAmber = Color(red: 1.000, green: 0.769, blue: 0.420) // #FFC46B
    public static let leaf = Color(red: 0.545, green: 0.851, blue: 0.478)      // #8BD97A
    public static let coral = Color(red: 0.949, green: 0.514, blue: 0.420)     // #F2836B

    /// Terrain ink — readable but recessive, so the creatures pop.
    public static let terrain = parchment.opacity(0.62)
    /// Markdown/structure glyphs get a touch more presence (headers = gates).
    public static let terrainStructure = parchment.opacity(0.92)

    // MARK: - The tile world (U13)
    //
    // Islands of parchment in a sea of ink. Land is LIGHT and glyphs are DARK —
    // ink on paper — which is what makes the page read as terrain rather than
    // as a block of text on a dark background.

    /// Bare paper: a space inside a line. Walkable ground, quieter than a tile.
    public static let groundTile = Color(red: 0.741, green: 0.702, blue: 0.635)
    /// A letter tile: brighter paper, so words read as a raised path.
    public static let letterTile = Color(red: 0.949, green: 0.922, blue: 0.867)
    /// The lip under every raised tile — where the paper catches the lamp.
    public static let tileShadow = Color(red: 0.055, green: 0.063, blue: 0.098)
    /// Glyphs drawn ON the paper.
    public static let glyphInk = Color(red: 0.129, green: 0.141, blue: 0.204)
    /// A heading banner: warm, sign-painted paper, so a signpost never reads
    /// as just another word plank.
    public static let bannerTile = Color(red: 1.0, green: 0.910, blue: 0.769)
    /// The torn-paper rim where an island meets the sea.
    public static let tornEdge = Color(red: 1.0, green: 0.984, blue: 0.945)
    /// Ruled notebook lines running under indented and list rows.
    public static let ruleLine = Color(red: 0.404, green: 0.596, blue: 0.639)
    /// The red margin rule down the left of every notebook page.
    public static let marginRule = coral
    /// Graph-paper blocks standing in the margin — the world's walls.
    public static let marginWall = Color(red: 0.176, green: 0.161, blue: 0.278)
    /// Faint graticule drawn on the margin blocks.
    public static let marginGrid = Color(red: 0.318, green: 0.310, blue: 0.451)
    /// The sea's slow shimmer.
    public static let seaShimmer = Color(red: 0.239, green: 0.263, blue: 0.408)

    public static let background = LinearGradient(
        colors: [inkNavy, plumDark], startPoint: .top, endPoint: .bottom
    )

    public static let mono = Font.system(.body, design: .monospaced)

    // MARK: - SpriteKit bridge

    #if canImport(AppKit)
    public static func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }
    #endif
}
