// SpriteSceneView.swift — the SwiftUI host for the SpriteKit world (plan U7).
//
// This wraps `SKView` in an `NSViewRepresentable` rather than using SpriteKit's
// `SpriteView`. Reason, and it is load-bearing on this toolchain: `SpriteView`
// is vended by the SpriteKit↔SwiftUI CROSS-IMPORT OVERLAY, and `scripts/test.sh`
// builds with `-disable-cross-import-overlays` on a CommandLineTools-only Mac
// (no full Xcode). Depending on `SpriteView` would make the game surface
// compile in `swift build` and fail in the test build — an invisible trap for
// the next unit. Hosting `SKView` directly has no overlay dependency, works in
// both, and gives explicit control of presentation and resizing.

import SpriteKit
import SwiftUI

struct SpriteSceneView: NSViewRepresentable {
    let scene: SKScene

    func makeNSView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.allowsTransparency = true
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
        }
    }
}
