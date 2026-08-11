import AppKit
import SwiftUI

/// The summonable lookup card — a non-activating, center-screen floating panel
/// (Raycast-style), adapted from vimhint's SidebarWindow recipe (MIT):
/// `.nonactivatingPanel` + `.borderless` + `.fullSizeContentView`, floating
/// level, all-Spaces + full-screen-auxiliary, `orderFrontRegardless` (never
/// `makeKeyAndOrderFront`), NSVisualEffectView (.hudWindow) content. Geometry
/// and animation changed: a ~640x420 rounded card slightly above screen
/// center, fade + slight-scale in/out instead of a right-edge slide.
final class OverlayPanel: NSPanel {

    // MARK: Constants

    static let cardSize = NSSize(width: 640, height: 420)
    private static let cornerRadius: CGFloat = 16
    private static let animationDuration: TimeInterval = 0.16
    private static let hiddenScale: CGFloat = 0.96

    // MARK: State

    private(set) var isShown = false
    /// Invoked when the panel wants to close (Escape, or losing key status).
    var onDismiss: (() -> Void)?
    private weak var visualEffectView: NSVisualEffectView?

    // MARK: Init

    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.cardSize),
            styleMask: [
                .nonactivatingPanel,    // does not activate app when shown
                .borderless,            // no title bar chrome
                .fullSizeContentView,   // content fills the entire frame
            ],
            backing: .buffered,
            defer: false
        )

        configure()
        buildContentStack(content: content)
    }

    // MARK: Configuration

    private func configure() {
        // Appearance — dark cozy card regardless of system appearance.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)

        // Floating behavior
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,        // visible on every Space
            .stationary,              // doesn't move during Exposé/Mission Control
            .fullScreenAuxiliary,     // stays visible when another app goes full-screen
        ]

        // Focus behavior
        becomesKeyOnlyIfNeeded = true   // only takes key focus when asked explicitly
        hidesOnDeactivate = false       // stays visible when you switch to another app
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false    // we manage lifetime, not AppKit
    }

    private func buildContentStack<Content: View>(content: Content) {
        // 1. Visual effect view provides the frosted-glass background
        let visualEffect = NSVisualEffectView(frame: .zero)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .inactive
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Self.cornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor(
            calibratedRed: 0x7D / 255, green: 0xE8 / 255, blue: 0xD8 / 255, alpha: 0.22
        ).cgColor

        // 2. SwiftUI hosting view fills it
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        contentView = visualEffect
        visualEffectView = visualEffect

        reposition()
    }

    // MARK: Screen Geometry

    /// The on-screen frame: centered horizontally, slightly above vertical
    /// center (Spotlight/Raycast placement).
    private static func shownFrame(for screen: NSScreen?) -> NSRect {
        guard let screen else { return NSRect(origin: .zero, size: cardSize) }
        let visible = screen.visibleFrame

        return NSRect(
            x: visible.midX - cardSize.width / 2,
            y: visible.midY - cardSize.height / 2 + visible.height * 0.08,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    /// The shown frame shrunk around its own center — the fade-in start state.
    private static func scaledFrame(for screen: NSScreen?) -> NSRect {
        let frame = shownFrame(for: screen)
        let dw = frame.width * (1 - hiddenScale) / 2
        let dh = frame.height * (1 - hiddenScale) / 2
        return frame.insetBy(dx: dw, dy: dh)
    }

    /// Call when the screen configuration changes (display arrangement, resolution).
    func reposition() {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        setFrame(Self.shownFrame(for: targetScreen), display: false)
    }

    // MARK: Show / Hide / Toggle

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        visualEffectView?.state = .active
        let targetScreen = NSScreen.main ?? NSScreen.screens.first

        alphaValue = 0
        setFrame(Self.scaledFrame(for: targetScreen), display: false)
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 1
            animator().setFrame(Self.shownFrame(for: targetScreen), display: true)
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 0
            animator().setFrame(Self.scaledFrame(for: targetScreen), display: true)
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.visualEffectView?.state = .inactive
            self.orderOut(nil)
            self.alphaValue = 1
            self.reposition()
        })
    }

    // MARK: NSPanel overrides

    /// Key status allowed (so the search field can type) — but the panel never
    /// becomes main and never activates the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape anywhere in the panel dismisses it.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Clicking away (losing key status) dismisses, Spotlight-style.
    override func resignKey() {
        super.resignKey()
        if isShown {
            onDismiss?()
        }
    }
}
