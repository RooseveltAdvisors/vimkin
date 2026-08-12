// JuiceAudioTests — the "degrades silently" contract.
//
// Real SFX land through the asset pipeline (assets/briefs/batch-02-audio.md) on
// their own schedule, so the audio layer must be completely safe with ZERO
// files on disk: no crash, no throw, no unhandled error — at worst a tiny
// synthesized click, at least silence.
//
// These tests run at masterVolume 0 so a test run never makes noise while still
// exercising the whole path (engine start, buffer synthesis, scheduling).

import Foundation
import Testing
@testable import Vimkin

@Suite("Juice: audio degrades safely without assets", .tags(.integration))
struct JuiceAudioTests {
    private var nowhere: URL {
        URL(fileURLWithPath: "/var/empty/vimkin-no-such-audio-dir-\(UUID().uuidString)")
    }

    private func silent(
        directory: URL?,
        fallback: Bool
    ) -> JuiceAudio.Configuration {
        JuiceAudio.Configuration(
            assetDirectory: directory,
            allowSynthesizedFallback: fallback,
            masterVolume: 0
        )
    }

    @Test("constructing against a nonexistent asset directory loads nothing and does not crash")
    func missingDirectoryLoadsNothing() {
        let audio = JuiceAudio(configuration: silent(directory: nowhere, fallback: false))
        #expect(audio.loadedTiers.isEmpty)
        for tier in JuiceTier.allCases {
            #expect(audio.hasAsset(for: tier) == false)
        }
    }

    @Test("a nil asset directory is fine too")
    func nilDirectoryIsFine() {
        let audio = JuiceAudio(configuration: silent(directory: nil, fallback: false))
        #expect(audio.loadedTiers.isEmpty)
        audio.play(tier: .burst)
    }

    @Test("play is a safe no-op with no assets and no fallback")
    func playIsANoOpWithoutAssetsOrFallback() {
        let audio = JuiceAudio(configuration: silent(directory: nowhere, fallback: false))
        for tier in JuiceTier.allCases {
            audio.play(tier: tier)
            audio.play(JuiceEvent(tier: tier, intensity: 1))
        }
        #expect(audio.lastPlayback == .silent)
    }

    @Test("the synthesized fallback carries the feedback when no file exists — and never throws")
    func synthesizedFallbackIsSafe() {
        let audio = JuiceAudio(configuration: silent(directory: nowhere, fallback: true))
        for tier in JuiceTier.allCases {
            audio.play(tier: tier)
        }
        // On a box with no usable output device the engine simply refuses to
        // start and we fall back to silence — both outcomes are acceptable,
        // a crash or an escaped error is not.
        #expect(audio.lastPlayback == .synthesized || audio.lastPlayback == .silent)
        #expect(audio.lastFailure == nil || audio.lastPlayback == .silent)
    }

    @Test("hammering every tier repeatedly stays safe")
    func repeatedPlaybackIsSafe() {
        let audio = JuiceAudio(configuration: silent(directory: nowhere, fallback: true))
        for _ in 0 ..< 40 {
            for tier in JuiceTier.allCases {
                audio.play(JuiceEvent(tier: tier, intensity: Double.random(in: 0 ... 1)))
            }
        }
    }

    @Test("muting silences everything, including the fallback")
    func muteSilencesEverything() {
        let audio = JuiceAudio(configuration: silent(directory: nowhere, fallback: true))
        audio.isMuted = true
        audio.play(tier: .burst)
        #expect(audio.lastPlayback == .muted)
    }

    @Test("a directory that exists but holds no audio still loads nothing")
    func emptyDirectoryLoadsNothing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vimkin-juice-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A decoy that is NOT audio: must be ignored, not fed to the player.
        try Data("not audio".utf8).write(to: directory.appendingPathComponent("whisper.txt"))

        let audio = JuiceAudio(configuration: silent(directory: directory, fallback: false))
        #expect(audio.loadedTiers.isEmpty)
        audio.play(tier: .whisper)
    }

    @Test("a corrupt file with a real audio extension is refused, not crashed on")
    func corruptAssetIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vimkin-juice-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0x41, count: 512).write(to: directory.appendingPathComponent("burst.wav"))

        let audio = JuiceAudio(configuration: silent(directory: directory, fallback: false))
        #expect(audio.hasAsset(for: .burst) == false)
        audio.play(tier: .burst)
        #expect(audio.lastPlayback == .silent)
    }

    @Test("pitch jitter stays inside the style guide's ±3% band")
    func pitchJitterMatchesTheStyleGuide() {
        let audio = JuiceAudio(configuration: silent(directory: nowhere, fallback: false))
        for _ in 0 ..< 200 {
            let rate = audio.jitteredRate()
            #expect(rate >= 1 - JuiceAudio.Configuration().pitchJitter - 1e-9)
            #expect(rate <= 1 + JuiceAudio.Configuration().pitchJitter + 1e-9)
        }
    }
}
