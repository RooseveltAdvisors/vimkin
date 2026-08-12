// TutorialTheme.swift — the tutorial chrome palette, straight from
// assets/briefs/style-guide.md ("cozy arcade": soft darkness + phosphor glow).
// Colour anchors are shared with EditorTheme so the editor never looks bolted on.

import SwiftUI

enum TutorialTheme {
    static let background = EditorTheme.background      // ink navy  #171A26
    static let panel = Color(hex: 0x211C38)             // plum dark #211C38
    static let paper = EditorTheme.text                 // parchment #F2EBDD
    static let glow = EditorTheme.cursor                // cursor cyan #7DE8D8
    static let vimkin = EditorTheme.amber               // amber     #FFC46B
    static let success = EditorTheme.leaf               // leaf      #8BD97A
    /// Soft alarm — never a harsh red (style guide, and plan R7: no punishment).
    static let alarm = EditorTheme.coral                // coral     #F2836B

    static let dim = EditorTheme.text.opacity(0.55)
    static let faint = EditorTheme.text.opacity(0.30)
    static let hairline = EditorTheme.text.opacity(0.12)

    static let mono = Font.system(.body, design: .monospaced)

    static func tierLabel(_ tier: Int) -> String {
        switch tier {
        case 1: return "Stage 1 · Survive"
        case 2: return "Stage 2 · Navigate"
        case 3: return "Stage 3 · Edit verbs"
        case 4: return "Stage 4 · The grammar"
        default: return "Stage \(tier)"
        }
    }

    static func masteryLabel(_ state: MasteryState) -> String? {
        switch state {
        case .unlearned: return nil
        case .learning: return "learning"
        case .mastered: return "solid"
        case .rusty: return "rusty"
        }
    }

    static func masteryColor(_ state: MasteryState) -> Color {
        switch state {
        case .unlearned: return faint
        case .learning: return glow
        case .mastered: return success
        case .rusty: return vimkin
        }
    }
}

/// The inline keycap chip used throughout the tutorial copy.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(TutorialTheme.glow)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(TutorialTheme.glow.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(TutorialTheme.glow.opacity(0.30), lineWidth: 1)
            )
    }
}

/// Renders lesson copy, turning `backticked` fragments into keycaps.
struct LessonText: View {
    let text: String
    var font: Font = .system(.body)
    var color: Color = TutorialTheme.paper

    var body: some View {
        let parts = text.split(separator: "`", omittingEmptySubsequences: false)
        return parts.enumerated().reduce(Text("")) { acc, pair in
            let (index, part) = pair
            let fragment = String(part)
            if index.isMultiple(of: 2) {
                return acc + Text(fragment).font(font).foregroundColor(color)
            }
            return acc + Text(fragment)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(TutorialTheme.glow)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
