// DojoTheme.swift — the dojo's slice of the cozy-arcade palette
// (assets/briefs/style-guide.md), built on the same anchors the editor uses so
// the two surfaces can never drift apart.

import SwiftUI

enum DojoTheme {
    static let background = EditorTheme.background      // ink navy  #171A26
    static let plum = Color(hex: 0x211C38)              // plum dark #211C38
    static let paper = EditorTheme.text                 // parchment #F2EBDD
    static let cyan = EditorTheme.cursor                // cursor    #7DE8D8
    static let amber = EditorTheme.amber                // vimkin    #FFC46B
    static let leaf = EditorTheme.leaf                  // success   #8BD97A
    /// Soft alarm — never a harsh red.
    static let coral = EditorTheme.coral

    static let mono = Font.system(.body, design: .monospaced)

    static func dotColor(_ state: DrillDotState) -> Color {
        switch state {
        case .upcoming: return paper.opacity(0.18)
        case .current: return cyan
        case .clean: return leaf
        case .struggled: return amber
        case .skipped: return paper.opacity(0.35)
        }
    }

    /// A calm, non-numeric reading of how long a set took.
    static func unhurriedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        switch minutes {
        case ..<1: return "a couple of minutes"
        case 1: return "about a minute"
        default: return "about \(minutes) minutes"
        }
    }
}

/// Rounded panel used across the dojo surfaces.
struct DojoPanel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(DojoTheme.plum.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(DojoTheme.paper.opacity(0.08), lineWidth: 1)
            )
    }
}
