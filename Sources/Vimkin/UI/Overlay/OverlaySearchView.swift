import SwiftUI
import AppKit

/// Vimkin palette tokens for the overlay (see assets/briefs/style-guide.md).
enum OverlayStyle {
    static let background = Color(red: 0x17 / 255, green: 0x1A / 255, blue: 0x26 / 255) // ink navy
    static let accent = Color(red: 0x7D / 255, green: 0xE8 / 255, blue: 0xD8 / 255)     // cursor cyan
    static let amber = Color(red: 0xFF / 255, green: 0xC4 / 255, blue: 0x6B / 255)      // vimkin amber
    static let paper = Color(red: 0xF2 / 255, green: 0xEB / 255, blue: 0xDD / 255)      // parchment
}

/// The lookup card content: a plain-English search field over the command
/// database + a results list. Selecting a row expands it with the full
/// description and a "Practice this →" affordance.
struct OverlaySearchView: View {
    let database: CommandDatabase
    let onPractice: (String) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var results: [VimCommand] = []
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
                .overlay(OverlayStyle.accent.opacity(0.15))
            if results.isEmpty {
                emptyState
            } else {
                resultsList
            }
            hintBar
        }
        .background(OverlayStyle.background.opacity(0.82))
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Re-focus the field every time the panel is summoned.
            if note.object is OverlayPanel {
                searchFocused = true
            }
        }
        .onChange(of: query) { _, newValue in
            results = database.search(newValue, limit: 12)
            selectedID = results.first?.id
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OverlayStyle.accent.opacity(0.7))
            TextField("What do you want to do? Try \u{201C}delete inside quotes\u{201D}", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17, design: .monospaced))
                .foregroundStyle(OverlayStyle.paper)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                // ⌃N / ⌃P — the Vim-native twins of the arrows, for anyone who
                // does not want to leave the home row to pick a result.
                .onKeyPress(phases: [.down, .repeat]) { press in
                    guard press.modifiers.contains(.control) else { return .ignored }
                    switch press.characters {
                    case "n": moveSelection(by: 1); return .handled
                    case "p": moveSelection(by: -1); return .handled
                    default: return .ignored
                    }
                }
                .onKeyPress(.escape) { onDismiss(); return .handled }
                .onKeyPress(.return) {
                    guard let selectedID else { return .ignored }
                    onPractice(selectedID)
                    return .handled
                }
            if !query.isEmpty {
                Text("\(results.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OverlayStyle.paper.opacity(0.35))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { command in
                        resultRow(command)
                            .id(command.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue)
                }
            }
        }
    }

    private func resultRow(_ command: VimCommand) -> some View {
        let isSelected = command.id == selectedID

        return Button {
            selectedID = isSelected ? nil : command.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(command.keys)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OverlayStyle.amber)
                    .frame(minWidth: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(command.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OverlayStyle.paper)
                    Text(command.description)
                        .font(.system(size: 12))
                        .foregroundStyle(OverlayStyle.paper.opacity(0.55))
                        .lineLimit(isSelected ? nil : 1)
                        .multilineTextAlignment(.leading)

                    if isSelected {
                        Button {
                            onPractice(command.id)
                        } label: {
                            Text("Practice this \u{2192}")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(OverlayStyle.background)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(OverlayStyle.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? OverlayStyle.accent.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Hint bar

    /// The lookup card is summoned by a global hotkey, so it has to say what to
    /// do next without a mouse anywhere in sight.
    private var hintBar: some View {
        HStack(spacing: 14) {
            ForEach(SurfaceKeys.lookup.chips) { chip in
                HStack(spacing: 5) {
                    ForEach(Array(chip.keys.split(separator: " ").enumerated()), id: \.offset) {
                        _, cap in
                        Keycap(label: String(cap))
                    }
                    Text(chip.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OverlayStyle.paper.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Keycap(label: "⌃N")
                Keycap(label: "⌃P")
                Text("move")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OverlayStyle.paper.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OverlayStyle.background.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(OverlayStyle.accent.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(query.isEmpty ? "vimkin lookup" : "no matches")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(OverlayStyle.accent.opacity(0.6))
            Text(
                query.isEmpty
                    ? "Type what you want to do in plain English \u{2014}\n\u{201C}delete inside quotes\u{201D}, \u{201C}go to end of line\u{201D}\u{2026}"
                    : "Try different words \u{2014} \u{201C}delete\u{201D}, \u{201C}jump\u{201D}, \u{201C}quotes\u{201D}, \u{201C}line\u{201D}\u{2026}"
            )
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(OverlayStyle.paper.opacity(0.4))
            .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Selection movement

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        guard let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = results.first?.id
            return
        }
        let next = min(max(index + delta, 0), results.count - 1)
        self.selectedID = results[next].id
    }
}
