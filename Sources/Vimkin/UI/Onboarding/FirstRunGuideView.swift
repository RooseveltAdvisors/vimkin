// FirstRunGuideView.swift — the one screen a mode shows the first time you
// walk into it, and never again.
//
// Every mode in the app already had good atmosphere and no instructions. This
// is the instructions: three named beats — what you're doing, what you press,
// how you know it worked — over the mode's own palette (all four surfaces share
// `EditorTheme`, so one view fits them all).
//
// Keyboard: the overlay owns NO bindings of its own. Each host intercepts its
// existing nav actions while the guide is up and dismisses on any of them, so
// `⏎`, `Esc`, `q` and the arrow keys all mean "got it" without a second router
// entering the picture. That keeps this additive to the keyboard surface rather
// than another thing competing for keys.

import SwiftUI

struct FirstRunGuideView: View {
    let guide: ModeGuide
    var onDismiss: () -> Void = {}

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text(guide.title)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(EditorTheme.text)

                LessonText(
                    text: guide.blurb,
                    font: .system(size: 15),
                    color: EditorTheme.text.opacity(0.85)
                )
                .lineSpacing(4)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(guide.beats) { beat in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(beat.label.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.1)
                                .foregroundStyle(EditorTheme.amber.opacity(0.9))
                            LessonText(
                                text: beat.text,
                                font: .system(size: 14),
                                color: EditorTheme.text.opacity(0.8)
                            )
                            .lineSpacing(3)
                        }
                    }
                }
                .padding(.leading, 2)

                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Text("Got it")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            Keycap(label: "⏎")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EditorTheme.cursor)
                    Text("shown once — any key closes it")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EditorTheme.text.opacity(0.4))
                }
                .padding(.top, 2)
            }
            .padding(32)
            .frame(maxWidth: 620, alignment: .leading)
            .background(
                Color(hex: 0x211C38).opacity(0.97),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(EditorTheme.cursor.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
        }
        .transition(.opacity)
    }
}
