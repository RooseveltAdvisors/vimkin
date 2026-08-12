// HubView.swift — the home screen (U18).
//
// Replaces the old title screen: a wordmark, a tagline, and six 20pt buttons in
// a row on an empty gradient. Three things changed, in order of how much they
// mattered to the verdict that killed it:
//
//   1. GROUPED BY INTENT. Four bands — PLAY / TRAIN / YOU / SANDBOX — so the
//      modes stop reading as a loose pile of six.
//   2. LIVE STATUS on every card. The hub reports where your practice actually
//      stands; it is a dashboard you launch from, not a launcher.
//   3. WEIGHT. Full-width cards with a real key-cap chip, a title, a line of
//      what-this-is and a line of where-you-stand — not a 20pt `Button`.
//
// The content is `Hub.groups(_:)` and nothing else; this file only draws it.
// The selection highlight is the app-wide `navSelected` so "where am I" looks
// identical here, on the world map, and in the lesson path.

import SwiftUI

struct HubView: View {
    let status: HubStatus
    /// Index into `Hub.entries(status)` — the flattened, top-to-bottom order.
    let selection: Int
    let onOpen: (String) -> Void

    private var groups: [HubGroup] { Hub.groups(status) }
    private var entries: [HubEntry] { Hub.entries(status) }

    var body: some View {
        ZStack {
            background
            // The whole hub must FIT at the minimum window size — a home screen
            // you have to scroll is a home screen that hides a mode. The
            // ScrollView is the safety net for very short windows, not the
            // expected reading mode; the metrics below are tuned so all four
            // bands land above the fold at 900x620.
            ScrollView { contentStack }
        }
    }

    /// The hub's content, outside the scroll container.
    ///
    /// Split out for one concrete reason: `ImageRenderer` does not lay out
    /// `ScrollView` contents, so rendering `body` yields the bare gradient and
    /// nothing else. `HubSnapshotTests` renders THIS, which is the part with
    /// the cards in it. (Verified the hard way — the first snapshot run
    /// produced four identical empty gradients.)
    var contentStack: some View {
        VStack(alignment: .leading, spacing: 15) {
            masthead
            ForEach(groups) { group in
                groupBlock(group)
            }
        }
        .frame(maxWidth: 660, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Ground

    /// Ink navy into plum, with a soft cyan bloom behind the wordmark — the
    /// desk-lamp glow of the style guide, without texture noise behind text.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [HubTheme.ink, HubTheme.plum],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [HubTheme.glow.opacity(0.14), .clear],
                center: .init(x: 0.5, y: 0.06), startRadius: 10, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Masthead

    /// Wordmark plus the one instruction the footer bar does NOT already give:
    /// that the letter on each card is itself a key. The `j k / ⏎ / ? / q` row
    /// lives in the persistent hint bar at the bottom of every surface, so
    /// repeating it here was duplication that cost a whole band of height.
    private var masthead: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Vimkin")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(HubTheme.paper)
                .shadow(color: HubTheme.glow.opacity(0.35), radius: 16)
            Text("learn vim. rescue the vimkins.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(HubTheme.paper.opacity(0.42))
            Spacer(minLength: 8)
            Text("press a letter to jump straight there")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HubTheme.glow.opacity(0.6))
                .fixedSize()
        }
    }

    // MARK: - Groups

    private func groupBlock(_ group: HubGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(group.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(HubTheme.glow.opacity(0.75))
                    .tracking(2.2)
                Rectangle()
                    .fill(HubTheme.glow.opacity(0.16))
                    .frame(height: 1)
            }
            VStack(spacing: 7) {
                ForEach(group.entries) { entry in
                    card(entry)
                }
            }
        }
    }

    // MARK: - Card

    private func card(_ entry: HubEntry) -> some View {
        let selected = entries.indices.contains(selection)
            && entries[selection].id == entry.id

        return Button {
            onOpen(entry.verb)
        } label: {
            HStack(spacing: 16) {
                keyChip(entry.key, selected: selected)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HubTheme.paper.opacity(selected ? 1 : 0.86))
                    Text(entry.blurb)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(HubTheme.paper.opacity(selected ? 0.62 : 0.42))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(entry.status)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        selected ? HubTheme.amber : HubTheme.amber.opacity(0.62)
                    )
                    .lineLimit(1)
                    .fixedSize()

                // The affordance that says "this row is the one ⏎ opens".
                Text("⏎")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? HubTheme.glow : .clear)
                    .frame(width: 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                HubTheme.card.opacity(selected ? 0.95 : 0.55),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .navSelected(selected, radius: 12)
        }
        .buttonStyle(.plain)
    }

    /// The jump key, as a real key-cap. Filled when selected so the eye lands
    /// on the same element that the keyboard acts on.
    private func keyChip(_ key: Character, selected: Bool) -> some View {
        Text(String(key))
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? HubTheme.ink : HubTheme.glow)
            .frame(width: 36, height: 34)
            .background(
                selected ? HubTheme.glow : HubTheme.glow.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(HubTheme.glow.opacity(selected ? 0 : 0.34), lineWidth: 1)
            )
    }
}

// MARK: - Palette

/// The hub's slice of the style guide (`assets/briefs/style-guide.md`).
enum HubTheme {
    static let ink = Color(hex: 0x171A26)      // ink navy
    static let plum = Color(hex: 0x211C38)     // plum dark
    static let paper = Color(hex: 0xF2EBDD)    // parchment
    static let glow = Color(hex: 0x7DE8D8)     // cursor cyan
    static let amber = Color(hex: 0xFFC46B)    // vimkin amber
    static let leaf = Color(hex: 0x8BD97A)     // leaf

    /// Card ground — a lift off the gradient, never a flat grey.
    static let card = Color(hex: 0x1D2032)
}
