// JuiceAudio.swift — the SFX side of the juice layer (plan U8).
//
// Hard requirement: the real sound set is generated separately (see
// assets/briefs/batch-02-audio.md) and may simply not be on disk yet — or ever,
// on a machine with no audio device. So every path here degrades:
//
//   file present        → play it, pitch-randomized ±3% (style guide)
//   file missing        → a tiny synthesized click/pop/chord (AVAudioEngine)
//   no device / failure → silence, recorded in `lastFailure`, never thrown
//
// Nothing in this file can crash, throw, or trap on a missing asset. That is
// the contract JuiceAudioTests pins down.
//
// Not thread-safe by design (same posture as ProgressStore) — own it from one
// thread; the app owns it from the main actor.

import AVFoundation
import Foundation

public final class JuiceAudio {
    public struct Configuration: Sendable {
        /// Where the generated SFX live. Nil = look only in the app bundle.
        public var assetDirectory: URL?
        /// Synthesize a fallback tick when a tier has no file.
        public var allowSynthesizedFallback: Bool
        /// Global scale on every playback (0 = silent but fully exercised).
        public var masterVolume: Double
        /// Playback-rate jitter, ±fraction. Style guide says ±3%.
        public var pitchJitter: Double

        public init(
            assetDirectory: URL? = JuiceAudio.defaultAssetDirectory,
            allowSynthesizedFallback: Bool = true,
            masterVolume: Double = 1.0,
            pitchJitter: Double = 0.03
        ) {
            self.assetDirectory = assetDirectory
            self.allowSynthesizedFallback = allowSynthesizedFallback
            self.masterVolume = min(max(masterVolume, 0), 1)
            self.pitchJitter = min(max(pitchJitter, 0), 0.5)
        }
    }

    /// What the last `play` actually did — surfaced so the degradation is
    /// observable (and testable) instead of a silent mystery.
    public enum Playback: Equatable, Sendable {
        case none
        case file
        case synthesized
        case silent
        case muted
    }

    public let configuration: Configuration
    /// Tiers that found a usable sound file.
    public private(set) var loadedTiers: Set<JuiceTier> = []
    public private(set) var lastPlayback: Playback = .none
    /// Non-nil when the most recent playback attempt failed (never thrown).
    public private(set) var lastFailure: String?
    /// Player-facing mute (settings, and "this week is for being human").
    public var isMuted = false

    private var players: [JuiceTier: AVAudioPlayer] = [:]
    private var engine: AVAudioEngine?
    private var synthNode: AVAudioPlayerNode?
    private var synthFormat: AVAudioFormat?
    private var synthUnavailable = false

    /// `<bundle>/Contents/Resources/audio/sfx`, where the asset pipeline lands
    /// the generated SFX set.
    public static var defaultAssetDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("audio/sfx", isDirectory: true)
    }

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        loadAssets()
    }

    public convenience init(assetDirectory: URL?) {
        self.init(configuration: Configuration(assetDirectory: assetDirectory))
    }

    // MARK: - Asset loading (never throws, never traps)

    /// File stems tried per tier, in order.
    private static func fileStems(for tier: JuiceTier) -> [String] {
        switch tier {
        case .whisper: return ["juice-whisper", "whisper", "tick", "thock"]
        case .pop: return ["juice-pop", "pop", "marimba-pop"]
        case .burst: return ["juice-burst", "burst", "combo-chord", "chord"]
        }
    }

    private static let extensions = ["wav", "aiff", "aif", "caf", "m4a", "mp3"]

    private func loadAssets() {
        guard let directory = configuration.assetDirectory else { return }
        for tier in JuiceTier.allCases {
            guard let url = Self.locate(tier: tier, in: directory) else { continue }
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                // A file that exists but will not decode is simply not an asset.
                continue
            }
            player.enableRate = true
            player.prepareToPlay()
            players[tier] = player
            loadedTiers.insert(tier)
        }
    }

    private static func locate(tier: JuiceTier, in directory: URL) -> URL? {
        let fileManager = FileManager.default
        for stem in fileStems(for: tier) {
            for ext in extensions {
                let candidate = directory.appendingPathComponent("\(stem).\(ext)")
                if fileManager.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    public func hasAsset(for tier: JuiceTier) -> Bool {
        loadedTiers.contains(tier)
    }

    // MARK: - Playback

    public func play(_ event: JuiceEvent) {
        play(tier: event.tier, intensity: event.intensity)
    }

    public func play(tier: JuiceTier, intensity: Double = 1.0) {
        lastFailure = nil
        guard !isMuted else {
            lastPlayback = .muted
            return
        }
        let volume = Float(min(max(intensity, 0), 1) * configuration.masterVolume)

        if let player = players[tier] {
            player.stop()
            player.currentTime = 0
            player.rate = Float(jitteredRate())
            player.volume = volume
            if player.play() {
                lastPlayback = .file
                return
            }
            lastFailure = "AVAudioPlayer refused to start for \(tier.name)"
        }

        guard configuration.allowSynthesizedFallback else {
            lastPlayback = .silent
            return
        }
        playSynthesized(tier: tier, volume: volume)
    }

    /// Playback rate for one hit: 1.0 ± the configured jitter, so a long drill
    /// never turns into the same click 400 times (style guide: pitch-randomize).
    public func jitteredRate() -> Double {
        guard configuration.pitchJitter > 0 else { return 1 }
        return 1 + Double.random(in: -configuration.pitchJitter ... configuration.pitchJitter)
    }

    // MARK: - Synthesized fallback

    /// A tiny generated tick/pop/chord so there is SOME feedback with zero
    /// assets on disk. Every failure mode here ends in silence, not a throw.
    private func playSynthesized(tier: JuiceTier, volume: Float) {
        guard !synthUnavailable else {
            lastPlayback = .silent
            return
        }
        guard let (node, format) = ensureSynthEngine() else {
            lastPlayback = .silent
            return
        }
        guard let buffer = Self.makeBuffer(tier: tier, format: format, rate: jitteredRate()) else {
            lastPlayback = .silent
            return
        }
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [])
        if !node.isPlaying { node.play() }
        lastPlayback = .synthesized
    }

    private func ensureSynthEngine() -> (AVAudioPlayerNode, AVAudioFormat)? {
        if let engine, let synthNode, let synthFormat, engine.isRunning {
            return (synthNode, synthFormat)
        }

        let engine = self.engine ?? AVAudioEngine()
        let node = synthNode ?? AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            synthUnavailable = true
            return nil
        }

        if node.engine == nil { engine.attach(node) }
        // Connecting to the main mixer touches the output device; on a box with
        // no usable device this is where things go wrong, so it is guarded.
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            lastFailure = "audio engine unavailable: \(error.localizedDescription)"
            synthUnavailable = true
            return nil
        }

        self.engine = engine
        self.synthNode = node
        self.synthFormat = format
        return (node, format)
    }

    /// Voicing per tier, from the style guide: a soft keyboard-thock-ish tick, a
    /// pitched marimba pop, and a warm three-note chord under 600ms.
    private static func makeBuffer(
        tier: JuiceTier,
        format: AVAudioFormat,
        rate: Double
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let (partials, duration, decay): ([Double], Double, Double) = {
            switch tier {
            case .whisper: return ([1_180], 0.06, 60)
            case .pop: return ([784, 1_568], 0.14, 26)
            case .burst: return ([523.25, 659.25, 783.99], 0.45, 8)
            }
        }()

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount

        let amplitude = 0.22 / Double(partials.count)
        for frame in 0 ..< Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = exp(-decay * t)
            var sample = 0.0
            for partial in partials {
                sample += sin(2 * .pi * partial * rate * t)
            }
            channel[frame] = Float(sample * amplitude * envelope)
        }
        return buffer
    }

    /// Stops everything and releases the engine (surface teardown).
    public func stop() {
        for player in players.values { player.stop() }
        synthNode?.stop()
        engine?.stop()
    }
}
