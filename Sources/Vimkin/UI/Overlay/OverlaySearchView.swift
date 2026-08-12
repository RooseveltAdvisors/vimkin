import SwiftUI
import AppKit

/// Vimkin palette tokens for the overlay (see assets/briefs/style-guide.md).
enum OverlayStyle {
    static let background = Color(red: 0x17 / 255, green: 0x1A / 255, blue: 0x26 / 255) // ink navy
    static let accent = Color(red: 0x7D / 255, green: 0xE8 / 255, blue: 0xD8 / 255)     // cursor cyan
    static let amber = Color(red: 0xFF / 255, green: 0xC4 / 255, blue: 0x6B / 255)      // vimkin amber
    static let paper = Color(red: 0xF2 / 255, green: 0xEB / 255, blue: 0xDD / 255)      // parchment
}

/// The launcher's `?` map: which-key, grouped, with a description per key.
///
/// A separate view for two reasons — the launcher panel is only 640x420, so
/// this has to lay its groups out in TWO columns to fit where the in-app help
/// overlay can afford one; and being a plain value it rasterises in a snapshot
/// test, which is the only pixel evidence available on a box whose
/// screen-recording permission is denied.
struct LauncherMapCard: View {
    let map: KeyMap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keys \u{00B7} \(map.title)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(OverlayStyle.paper)
                Spacer()
                HStack(spacing: 6) {
                    Keycap(label: "Esc")
                    Text("close")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OverlayStyle.paper.opacity(0.5))
                }
            }

            ForEach(map.groupedChips) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(OverlayStyle.accent.opacity(0.75))
                        .tracking(1.2)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 12, alignment: .leading),
                            count: 2
                        ),
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(group.chips) { chip in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                HStack(spacing: 4) {
                                    ForEach(
                                        Array(chip.keys.split(separator: " ").enumerated()),
                                        id: \.offset
                                    ) { _, cap in
                                        Keycap(label: String(cap)).fixedSize()
                                    }
                                }
                                Text(chip.label)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(OverlayStyle.paper.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Text("Type to search. Press : then a letter to open a surface.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(OverlayStyle.accent.opacity(0.7))
        }
        .padding(18)
        .frame(width: 520, alignment: .leading)
        .background(
            OverlayStyle.background.opacity(0.98), in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(OverlayStyle.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

/// The launcher card — Vimkin's front door (U20).
///
/// Two jobs, and the order between them is the whole design:
///
///   1. **Type** to search every Vim command in plain English. The moment
///      there is a query, every letter belongs to the field.
///   2. **On an empty query**, a single mnemonic key opens an app surface —
///      `a` Adventure, `d` Daily Run, `l` Lessons, `p` Practice, `g` Progress,
///      `y` Playground — exactly the letters the hub prints on its own cards.
///      This is tmux's `C-a`-then-one-key shape, with the launcher as the
///      prefix (`docs/keymap.md`).
///
/// The precedence rule lives in `LauncherKeys.route`, not here, so it is
/// provable without simulating focus. The destinations are on screen the whole
/// time (which-key, not memory), and `?` opens the full map.
///
/// Focus discipline: summoning and searching never activate the app (the panel
/// is `.nonactivatingPanel`) — only OPENING a surface brings Vimkin forward.
struct OverlaySearchView: View {
    let database: CommandDatabase
    let onPractice: (String) -> Void
    let onOpenSurface: (String) -> Void
    let onDismiss: () -> Void

    @State private var query: String
    @State private var results: [VimCommand]
    @State private var selectedID: String?
    @State private var showMap: Bool
    /// `:` was pressed on an empty field: the NEXT key addresses the program
    /// instead of typing. One key wide, exactly like Vim's command line — it
    /// disarms as soon as that key lands.
    @State private var commandArmed = false
    @FocusState private var searchFocused: Bool

    /// - Parameters:
    ///   - initialQuery: seeded state, so a snapshot test can rasterise the
    ///     "typing" appearance as well as the front door. Empty in the app.
    ///   - initialShowMap: likewise for the `?` map.
    init(
        database: CommandDatabase,
        onPractice: @escaping (String) -> Void,
        onOpenSurface: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void,
        initialQuery: String = "",
        initialShowMap: Bool = false
    ) {
        self.database = database
        self.onPractice = onPractice
        self.onOpenSurface = onOpenSurface
        self.onDismiss = onDismiss
        let seeded = initialQuery.isEmpty ? [] : database.search(initialQuery, limit: 12)
        _query = State(initialValue: initialQuery)
        _results = State(initialValue: seeded)
        _selectedID = State(initialValue: seeded.first?.id)
        _showMap = State(initialValue: initialShowMap)
    }

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
            destinationStrip
            hintBar
        }
        .background(OverlayStyle.background.opacity(0.82))
        .overlay {
            if showMap {
                launcherMap
            }
        }
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Every summon is a FRONT DOOR again. The panel is hidden, not
            // destroyed, so without this reset the last search is still in the
            // box on the next `⌘⇧Space` — and a non-empty box means the
            // mnemonics are stood down, so the front door silently stops
            // working (observed on the real app, agt-2, 2026-08-12).
            guard note.object is OverlayPanel else { return }
            query = ""
            commandArmed = false
            showMap = false
            searchFocused = true
        }
        .onChange(of: query) { _, newValue in
            results = database.search(newValue, limit: 12)
            selectedID = results.first?.id
            // Any typing ends command mode; the field owns the keys again.
            if !newValue.isEmpty { commandArmed = false }
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
                // ONE handler for every physical key. The app's own rule —
                // exactly one router per key — applies to the launcher too: a
                // second `.onKeyPress` here would make the order in which two
                // handlers see `Esc` a coin toss.
                .onKeyPress(phases: [.down, .repeat], action: handleKey)
            if !query.isEmpty {
                Text("\(results.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OverlayStyle.paper.opacity(0.35))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Key routing

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // The map is modal: it eats every key until it closes.
        if showMap {
            if press.key == .escape || press.characters == "?" || press.characters == "q" {
                showMap = false
            }
            return .handled
        }

        switch press.key {
        case .escape:
            onDismiss()
            return .handled
        case .return:
            guard let selectedID else { return .ignored }
            onPractice(selectedID)
            return .handled
        case .downArrow:
            moveSelection(by: 1)
            return .handled
        case .upArrow:
            moveSelection(by: -1)
            return .handled
        default:
            break
        }

        // ⌃N / ⌃P — the Vim-native twins of the arrows, for anyone who does not
        // want to leave the home row to pick a result.
        if press.modifiers.contains(.control) {
            switch press.characters {
            case "n": moveSelection(by: 1); return .handled
            case "p": moveSelection(by: -1); return .handled
            default: return .ignored
            }
        }

        // ⌘ / ⌥ combos belong to the menu bar and to text editing.
        guard press.modifiers.isDisjoint(with: [.command, .option]),
            let character = press.characters.first
        else { return .ignored }

        switch LauncherKeys.route(character: character, query: query, commandArmed: commandArmed) {
        case .open(let verb):
            commandArmed = false
            onOpenSurface(verb)
            return .handled
        case .help:
            commandArmed = false
            showMap = true
            return .handled
        case .startCommand:
            commandArmed = true
            return .handled
        case .dismiss:
            onDismiss()
            return .handled
        case .type:
            // Ordinary text — or a command key nobody claimed. Either way the
            // field gets it, untouched.
            commandArmed = false
            return .ignored
        }
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

    // MARK: Destinations (which-key, always on screen)

    /// The front door's other half: every surface, one key each, VISIBLE.
    ///
    /// It stays on screen while you type — dimmed, with the reason why —
    /// rather than disappearing, because a key map you have to remember is the
    /// thing this app exists not to be.
    private var destinationStrip: some View {
        let live = commandArmed

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(commandArmed ? "GO \u{2014} press a letter" : "GO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(OverlayStyle.accent.opacity(live ? 0.8 : 0.3))
                    .tracking(1.2)
                if !live {
                    Text("\u{2014} press : first")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OverlayStyle.paper.opacity(0.3))
                }
            }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 10, alignment: .leading), count: 3
                ),
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(LauncherKeys.destinations) { destination in
                    HStack(spacing: 7) {
                        Keycap(label: String(destination.key)).fixedSize()
                        Text(destination.title)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OverlayStyle.paper.opacity(live ? 0.8 : 0.32))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OverlayStyle.accent.opacity(live ? 0.06 : 0.02))
        .overlay(alignment: .top) {
            Rectangle().fill(OverlayStyle.accent.opacity(0.12)).frame(height: 1)
        }
        .opacity(live ? 1 : 0.75)
    }

    // MARK: Hint bar

    /// The launcher is summoned by a global hotkey, so it has to say what to
    /// do next without a mouse anywhere in sight.
    private var hintBar: some View {
        HStack(spacing: 14) {
            ForEach(SurfaceKeys.launcher.barChips) { chip in
                HStack(spacing: 5) {
                    ForEach(Array(chip.keys.split(separator: " ").enumerated()), id: \.offset) {
                        _, cap in
                        Keycap(label: String(cap))
                    }
                    Text(chip.barText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OverlayStyle.paper.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OverlayStyle.background.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(OverlayStyle.accent.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: The `?` map

    private var launcherMap: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            LauncherMapCard(map: SurfaceKeys.launcher)
                .padding(16)
        }
        .onTapGesture { showMap = false }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(emptyTitle)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(OverlayStyle.accent.opacity(0.6))
            Text(emptyHint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(OverlayStyle.paper.opacity(0.4))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "no matches" }
        return commandArmed ? "go where?" : "vimkin launcher"
    }

    private var emptyHint: String {
        if !query.isEmpty {
            return "Try different words \u{2014} \u{201C}delete\u{201D}, \u{201C}jump\u{201D}, \u{201C}quotes\u{201D}, \u{201C}line\u{201D}\u{2026}"
        }
        if commandArmed {
            return "Press a letter below to open it.\nEsc to go back to searching."
        }
        return "Type what you want to do in plain English \u{2014}\n\u{201C}go to end of line\u{201D}, \u{201C}change inside brackets\u{201D}\u{2026}\nOr press \u{201C}:\u{201D} to go somewhere in the app."
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
