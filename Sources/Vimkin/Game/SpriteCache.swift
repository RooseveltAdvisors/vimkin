// SpriteCache.swift — loads cut-out character art from the resource bundle.
//
// Art is optional by design: the game ships and plays with programmatic shapes
// when `Content/sprites/` is empty, so a build without generated assets is
// still a complete game rather than a broken one.

import Foundation
import SpriteKit

final class SpriteCache: @unchecked Sendable {
    private var textures: [String: SKTexture?] = [:]
    private let lock = NSLock()

    /// Returns the texture for a sprite name, or nil when that art is absent.
    /// Misses are cached too — a missing file is looked up once, not per frame.
    ///
    /// - Parameter subdirectory: where in `Content/` the art lives. Characters
    ///   are in `Content/sprites`; the terrain tileset is in `Content/tiles`.
    func texture(named name: String, in subdirectory: String = "Content/sprites") -> SKTexture? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(subdirectory)/\(name)"
        if let cached = textures[key] { return cached }

        let url = Bundle.vimkinResources.url(
            forResource: name, withExtension: "png", subdirectory: subdirectory
        )
        let texture = url
            .flatMap { NSImage(contentsOf: $0) }
            .map { SKTexture(image: $0) }
        textures[key] = texture
        return texture
    }
}
