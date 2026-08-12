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
