// ArcadeTheme.swift — the arcade's slice of the palette (plan KTD 5).
//
// Same style-guide anchors as the dojo, deliberately turned UP. Where
// `DojoTheme` reads as calm parchment on ink, this reads as a lit cabinet:
// amber is the ambient colour rather than an accent, the clock is a real
// gauge, and coral is allowed to mean "hurry" — the one place in Vimkin it may.

import SwiftUI

enum ArcadeTheme {
    static let background = EditorTheme.background      // ink navy  #171A26
    static let plum = Color(hex: 0x2A1E3D)              // a hotter plum than the dojo's
    static let paper = EditorTheme.text                 // parchment #F2EBDD
    static let cyan = EditorTheme.cursor                // cursor    #7DE8D8
    static let amber = EditorTheme.amber                // vimkin    #FFC46B
    static let leaf = EditorTheme.leaf                  // success   #8BD97A
    static let coral = EditorTheme.coral                // urgency   #F2836B

    static let mono = Font.system(.body, design: .monospaced)

    /// The clock's colour as it drains: calm cyan → amber → coral. Continuous,
    /// so the gauge slides rather than snapping between "safe" and "panic".
    static func clockTint(remainingFraction: Double) -> Color {
        let fraction = min(1, max(0, remainingFraction))
        switch fraction {
        case 0.5...: return cyan
        case 0.2..<0.5: return amber
        default: return coral
        }
    }

    /// How loud the combo badge reads. Also feeds the juice intensity.
    static func comboHeat(_ combo: Int) -> Double {
        min(1, Double(max(0, combo)) / 8)
    }

    static func comboTint(_ combo: Int) -> Color {
        switch combo {
        case ..<2: return paper.opacity(0.45)
        case 2..<4: return cyan
        case 4..<7: return amber
        default: return leaf
        }
    }

    /// `03:00`-style clock text.
    static func clockText(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%01d:%02d", whole / 60, whole % 60)
    }

    /// Mastery-state colour, shared with the mastery map so the two surfaces
    /// can never disagree about what "rusty" looks like.
    static func stateTint(_ state: MasteryState) -> Color {
        switch state {
        case .unlearned: return paper.opacity(0.28)
        case .learning: return cyan
        case .mastered: return leaf
        // Rusty is the call to action, so it gets the one warm alarm colour.
        case .rusty: return coral
        }
    }

    static func stateLabel(_ state: MasteryState) -> String {
        switch state {
        case .unlearned: return "not started"
        case .learning: return "learning"
        case .mastered: return "mastered"
        case .rusty: return "going rusty"
        }
    }
}

/// Rounded panel used across the arcade + mastery surfaces.
struct ArcadePanel<Content: View>: View {
    var padding: CGFloat = 16
    var tint: Color = ArcadeTheme.plum
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ArcadeTheme.paper.opacity(0.08), lineWidth: 1)
            )
    }
}
