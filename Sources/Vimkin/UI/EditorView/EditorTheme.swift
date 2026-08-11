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
        switch mode {
        case .normal: return cursor
        case .insert: return leaf
        case .visual: return amber
        case .operatorPending: return coral
        case .commandLine: return text
        }
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
