// CommandEvent.swift — the structured event VimEngine emits per completed command.
// Downstream consumers: drills (did the player execute the target command?),
// game scoring, and the juice layer (category drives feedback tier).

/// A named motion, as reported in CommandEvents.
public enum Motion: Equatable, Hashable, Sendable {
    case left, down, up, right
    case wordForward       // w
    case wordBackward      // b
    case wordEnd           // e
    case lineStart         // 0
    case lineEnd           // $
    case firstNonBlank     // ^
    case fileStart         // gg
    case fileEnd           // G (with count: go to line)
    case find(Character)       // f{c}
    case till(Character)       // t{c}
    case findBack(Character)   // F{c}
    case tillBack(Character)   // T{c}
    case repeatFind        // ;
    case repeatFindReverse // ,
}

/// Text-object kinds in the v1 surface.
public enum TextObjectKind: String, Equatable, Sendable {
    case word          // iw / aw
    case quotedString  // i" / a"
    case parens        // i( / a(
    case paragraph     // ip / ap
}

public struct CommandEvent: Equatable, Sendable {
    /// What was done.
    public enum Verb: Equatable, Sendable {
        case move
        case delete        // d family, and visual d/x
        case change        // c family
        case yank          // y family
        case put           // p
        case putBefore     // P
        case deleteChar    // x
        case undo          // u
        case enterInsert   // i a o I A O (and the insert half of c)
        case leaveInsert   // Esc from insert
        case enterVisual   // v
        case leaveVisual   // Esc / v from visual
        case write         // :w
        case quit          // :q
        case writeQuit     // :wq
    }

    /// Text-object modifier: inside (i) or around (a).
    public enum Modifier: String, Equatable, Sendable {
        case inside
        case around
    }

    /// What the verb applied to.
    public enum Target: Equatable, Sendable {
        case motion(Motion)
        case textObject(TextObjectKind)
        case line       // dd / cc / yy linewise
        case selection  // visual-mode operand
    }

    /// Complexity classification — drives drill checking, game scoring, and juice tiers.
    public enum Category: String, Equatable, Sendable {
        case singleMotion    // bare motion (w, fx, gg, 3l)
        case operatorMotion  // operator + motion or linewise doubling (dw, 2dd, d$)
        case fullGrammar     // operator + modifier + text object (diw, ci", ya()
        case action          // x, p, P, u
        case mode            // mode transitions (i, v, Esc, o…)
        case commandLine     // :w / :q / :wq
    }

    public var verb: Verb
    public var modifier: Modifier?
    public var target: Target?
    public var count: Int
    public var category: Category

    public init(
        verb: Verb,
        modifier: Modifier? = nil,
        target: Target? = nil,
        count: Int = 1,
        category: Category
    ) {
        self.verb = verb
        self.modifier = modifier
        self.target = target
        self.count = count
        self.category = category
    }
}
