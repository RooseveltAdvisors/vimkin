import AppKit
import Carbon.HIToolbox

// Harvested from vimhint's HotkeyManager.swift (MIT) and adapted for Vimkin:
// new storage key ("vimkin.summonShortcut"), new hotkey signature ("VMKN"),
// the Shortcut type hoisted to a top-level `HotkeyShortcut` (keeps it
// nonisolated + Sendable under Swift 6 while the manager is @MainActor),
// injectable-UserDefaults persistence helpers for testability, and a
// Cmd+Shift+Space default applied when nothing is stored (U20 — the launcher
// is Vimkin's front door, so its key is the one a Spotlight/Raycast user's
// hand already goes to). The old Cmd+Shift+V default is migrated forward.

/// A recorded global shortcut: a Carbon virtual key code + Carbon modifier mask.
/// Persisted to UserDefaults as JSON.
public struct HotkeyShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The default summon shortcut when none is stored: Cmd+Shift+Space.
    ///
    /// The launcher is the app's front door (see `docs/keymap.md` — "the
    /// launcher is the prefix", the way `C-a` is tmux's), so it gets the key a
    /// hand already reaches for.
    public static let defaultSummon = HotkeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// The default this app shipped with BEFORE U20: Cmd+Shift+V.
    ///
    /// Anyone who ran an earlier build has it persisted, so a plain
    /// "default when nothing is stored" would leave them on the old key
    /// forever. `resolveSummon` migrates it; a shortcut the player CHOSE is
    /// never touched.
    public static let legacyDefaultSummon = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// The shortcut to register at launch, migrating a stale stored default.
    ///
    /// - nothing stored → the current default,
    /// - the OLD default stored → the current default, rewritten to storage so
    ///   the migration happens once and the recorder shows the truth,
    /// - anything else → left exactly as the player set it.
    public static func resolveSummon(from defaults: UserDefaults, key: String) -> HotkeyShortcut {
        guard let stored = load(from: defaults, key: key) else { return .defaultSummon }
        guard stored == .legacyDefaultSummon else { return stored }
        save(.defaultSummon, to: defaults, key: key)
        return .defaultSummon
    }

    public var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Alt") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }

        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    /// Builds a shortcut from raw key data. Rejects modifier-only key codes and
    /// combinations with no modifier (a global hotkey must carry at least one).
    public static func make(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> HotkeyShortcut? {
        guard !modifierOnlyKeyCodes.contains(keyCode) else { return nil }

        let flags = modifierFlags.intersection([.command, .option, .shift, .control])
        var carbonModifiers: UInt32 = 0

        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        guard carbonModifiers != 0 else { return nil }

        return HotkeyShortcut(keyCode: keyCode, modifiers: carbonModifiers)
    }

    public static func from(event: NSEvent) -> HotkeyShortcut? {
        make(keyCode: UInt32(event.keyCode), modifierFlags: event.modifierFlags)
    }

    // MARK: - Persistence (injectable defaults for tests)

    public static func save(_ shortcut: HotkeyShortcut?, to defaults: UserDefaults, key: String) {
        guard let shortcut else {
            defaults.removeObject(forKey: key)
            return
        }

        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load(from defaults: UserDefaults, key: String) -> HotkeyShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyShortcut.self, from: data)
    }

    private static let modifierOnlyKeyCodes: Set<UInt32> = [
        UInt32(kVK_Shift),
        UInt32(kVK_RightShift),
        UInt32(kVK_Control),
        UInt32(kVK_RightControl),
        UInt32(kVK_Option),
        UInt32(kVK_RightOption),
        UInt32(kVK_Command),
        UInt32(kVK_RightCommand),
        UInt32(kVK_CapsLock),
        UInt32(kVK_Function),
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        if let ansi = ansiKeyNames[keyCode] {
            return ansi
        }

        switch keyCode {
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_ForwardDelete): return "ForwardDelete"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_Help): return "Help"
        case UInt32(kVK_Home): return "Home"
        case UInt32(kVK_End): return "End"
        case UInt32(kVK_PageUp): return "PageUp"
        case UInt32(kVK_PageDown): return "PageDown"
        case UInt32(kVK_LeftArrow): return "Left"
        case UInt32(kVK_RightArrow): return "Right"
        case UInt32(kVK_UpArrow): return "Up"
        case UInt32(kVK_DownArrow): return "Down"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        case UInt32(kVK_F13): return "F13"
        case UInt32(kVK_F14): return "F14"
        case UInt32(kVK_F15): return "F15"
        case UInt32(kVK_F16): return "F16"
        case UInt32(kVK_F17): return "F17"
        case UInt32(kVK_F18): return "F18"
        case UInt32(kVK_F19): return "F19"
        case UInt32(kVK_F20): return "F20"
        default:
            return "Key\(keyCode)"
        }
    }

    private static let ansiKeyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_KeypadDecimal): "Num.",
        UInt32(kVK_ANSI_KeypadMultiply): "Num*",
        UInt32(kVK_ANSI_KeypadPlus): "Num+",
        UInt32(kVK_ANSI_KeypadClear): "NumClear",
        UInt32(kVK_ANSI_KeypadDivide): "Num/",
        UInt32(kVK_ANSI_KeypadEnter): "NumEnter",
        UInt32(kVK_ANSI_KeypadMinus): "Num-",
        UInt32(kVK_ANSI_KeypadEquals): "Num=",
        UInt32(kVK_ANSI_Keypad0): "Num0",
        UInt32(kVK_ANSI_Keypad1): "Num1",
        UInt32(kVK_ANSI_Keypad2): "Num2",
        UInt32(kVK_ANSI_Keypad3): "Num3",
        UInt32(kVK_ANSI_Keypad4): "Num4",
        UInt32(kVK_ANSI_Keypad5): "Num5",
        UInt32(kVK_ANSI_Keypad6): "Num6",
        UInt32(kVK_ANSI_Keypad7): "Num7",
        UInt32(kVK_ANSI_Keypad8): "Num8",
        UInt32(kVK_ANSI_Keypad9): "Num9",
    ]
}

/// Registers the global summon hotkey via Carbon `RegisterEventHotKey` — zero
/// permissions, sandbox-safe (no Accessibility prompt, no event tap).
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    nonisolated static let shortcutDidChangeNotification = Notification.Name("VimkinHotkeyShortcutDidChange")
    nonisolated static let storageKey = "vimkin.summonShortcut"

    var shortcut: HotkeyShortcut? {
        didSet {
            HotkeyShortcut.save(shortcut, to: .standard, key: Self.storageKey)
            reRegisterHotKey()
            NotificationCenter.default.post(name: Self.shortcutDidChangeNotification, object: nil)
        }
    }

    private var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x564D_4B4E), id: 1) // "VMKN"
    private var isRecordingShortcut = false
    private var suppressTriggerUntil: CFAbsoluteTime = 0

    private init() {
        installEventHandlerIfNeeded()
        shortcut = HotkeyShortcut.resolveSummon(from: .standard, key: Self.storageKey)
        reRegisterHotKey()
    }

    func onTrigger(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func beginShortcutRecording() {
        isRecordingShortcut = true
        suppressTriggerUntil = CFAbsoluteTimeGetCurrent() + 0.8
    }

    func endShortcutRecording() {
        isRecordingShortcut = false
        suppressTriggerUntil = CFAbsoluteTimeGetCurrent() + 0.5
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    private func reRegisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        guard let shortcut else { return }

        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // Carbon delivers hotkey events on the main thread (application event
    // target), so hopping back onto the MainActor here is sound.
    private static let eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

        var incomingID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &incomingID
        )

        guard status == noErr else { return status }

        // Smuggle the pointer across the isolation boundary as a Sendable
        // integer — Carbon delivers this on the main thread, so the
        // assumeIsolated below is sound.
        let opaqueUserData = UInt(bitPattern: userData)
        return MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: opaqueUserData) else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue()
            guard incomingID.signature == manager.hotKeyID.signature, incomingID.id == manager.hotKeyID.id else {
                return OSStatus(eventNotHandledErr)
            }

            let now = CFAbsoluteTimeGetCurrent()
            guard !manager.isRecordingShortcut, now >= manager.suppressTriggerUntil else {
                return noErr
            }

            manager.handler?()
            return noErr
        }
    }
}
