// Register.swift — the single unnamed register, tracking linewise vs charwise kind.
// The kind determines paste behavior: linewise `p` opens new lines below; charwise
// `p` pastes inline after the cursor.

public enum RegisterKind: String, Equatable, Sendable {
    case charwise
    case linewise
}

public struct Register: Equatable, Hashable, Sendable {
    /// Charwise content (may contain newlines from multi-line charwise deletes).
    public var text: String
    /// Linewise content as whole lines (used when kind == .linewise).
    public var lines: [String]
    public var kind: RegisterKind

    public static func charwise(_ text: String) -> Register {
        Register(text: text, lines: [], kind: .charwise)
    }

    public static func linewise(_ lines: [String]) -> Register {
        Register(text: lines.joined(separator: "\n"), lines: lines, kind: .linewise)
    }
}
