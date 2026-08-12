// IdleHintBar.swift — the gentle "here's the key" line that appears after a
// quiet spell on a practice surface.
//
// Copy rules, so this never reads as a scold: it opens with "no rush", it names
// the key rather than nagging you to find it, and it leaves the instant you
// press anything. It is an offer, not a timer.

import SwiftUI

struct IdleHintBar: View {
    /// Already-composed sentence, backticks around any keys.
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "hand.wave")
                .foregroundStyle(EditorTheme.amber.opacity(0.85))
            LessonText(
                text: text,
                font: .system(size: 13),
                color: EditorTheme.text.opacity(0.85)
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(EditorTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(EditorTheme.amber.opacity(0.22), lineWidth: 1)
        )
        .transition(.opacity)
    }

    // MARK: - Phrasing
    //
    // `nonisolated` because a `View` is implicitly `@MainActor` and these are
    // pure string functions — the point is that they are unit-testable off the
    // main actor, with no view anywhere near them.

    /// "no rush — the key here is `i`."
    nonisolated static func forKeys(_ keys: String) -> String {
        let display = keys.isEmpty ? "" : keys
        guard !display.isEmpty else { return "no rush — take the time you need." }
        return "no rush — the keys here are `\(display)`."
    }

    /// The Adventure form: a level has a whole toolkit, not one answer, so it
    /// re-states the objective and points at the bar.
    nonisolated static func forLevel(keys: [String], objective: String) -> String {
        guard !keys.isEmpty else { return "no rush — \(lowercasedFirst(objective))" }
        let caps = keys.map { "`\($0)`" }.joined(separator: " ")
        return "no rush — \(lowercasedFirst(objective)) the keys this page gives you: \(caps)"
    }

    nonisolated private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
