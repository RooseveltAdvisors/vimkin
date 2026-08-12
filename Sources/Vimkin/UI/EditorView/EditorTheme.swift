// EditorTheme.swift — the dark cozy palette from assets/briefs/style-guide.md.

import SwiftUI

enum EditorTheme {
    // Style-guide anchors.
    static let background = Color(hex: 0x171A26)   // ink navy
    static let text = Color(hex: 0xF2EBDD)         // warm off-white parchment
    static let cursor = Color(hex: 0x7DE8D8)       // cursor cyan

    // Accents (style-guide palette).
    static let amber = Color(hex: 0xFFC46B)
    static let leaf = Color(hex: 0x8BD97A)
    static let coral = Color(hex: 0xF2836B)

    static let selection = cursor.opacity(0.22)
    static let commentText = text.opacity(0.45)

    static func tintColor(_ kind: SyntaxTint.Kind) -> Color {
        switch kind {
        case .header: return amber
        case .key: return amber
        case .string: return leaf
        case .comment: return commentText
        }
    }

    static func badgeColor(for mode: Mode) -> Color {
        Color(hex: badgeHex(for: mode))
    }

    /// Same palette as `badgeColor`, as raw hex — the animated cursor blends
    /// between two modes' colours mid-morph, which needs components, not a
    /// `Color`.
    static func badgeHex(for mode: Mode) -> UInt32 {
        switch mode {
        case .normal: return 0x7DE8D8       // cursor cyan
        case .insert: return 0x8BD97A       // leaf
        case .visual: return 0xFFC46B       // amber
        case .operatorPending: return 0xF2836B // coral
        case .commandLine: return 0xF2EBDD  // parchment
        }
    }

    /// Linear blend between two palette colours.
    static func mix(_ from: UInt32, _ to: UInt32, _ t: Double) -> Color {
        let f = min(max(t, 0), 1)
        func channel(_ shift: UInt32) -> Double {
            let a = Double((from >> shift) & 0xFF)
            let b = Double((to >> shift) & 0xFF)
            return (a + (b - a) * f) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    static func badgeLabel(for mode: Mode) -> String {
        switch mode {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .operatorPending: return "⋯"
        case .commandLine: return "COMMAND"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
