import Foundation
import Testing
@testable import Vimkin

// The first-run guide is only worth anything if it appears exactly once. These
// drive a REAL `FirstRunStore` against a real temp directory — the flag has to
// survive the store being rebuilt, which is what happens every time the view
// that owns it is re-created.

@Suite("First-run guides are shown once and remembered", .tags(.integration))
struct FirstRunStorePersistenceTests {

    @Test("a fresh install wants every guide")
    func freshInstallShowsEveryGuide() {
        let store = FirstRunStore(directory: temporaryDirectory())
        for mode in GuideMode.allCases {
            #expect(store.shouldShowGuide(for: mode), "\(mode) should be offered on a fresh install")
            #expect(!store.hasSeen(mode))
        }
    }

    @Test("marking a guide seen survives a rebuilt store")
    func seenSurvivesReload() throws {
        let directory = temporaryDirectory()
        let first = FirstRunStore(directory: directory)
        first.markSeen(.adventure)
        #expect(first.lastSaveError == nil)

        let reloaded = FirstRunStore(directory: directory)
        #expect(reloaded.hasSeen(.adventure))
        #expect(!reloaded.shouldShowGuide(for: .adventure))
    }

    @Test("one mode's guide does not dismiss another's")
    func modesAreIndependent() {
        let directory = temporaryDirectory()
        let store = FirstRunStore(directory: directory)
        store.markSeen(.practice)

        let reloaded = FirstRunStore(directory: directory)
        #expect(reloaded.hasSeen(.practice))
        #expect(reloaded.shouldShowGuide(for: .adventure))
        #expect(reloaded.shouldShowGuide(for: .lessons))
        #expect(reloaded.shouldShowGuide(for: .dailyRun))
    }

    @Test("marking the same guide twice is a no-op, not a second write")
    func markingIsIdempotent() {
        let store = FirstRunStore(directory: temporaryDirectory())
        store.markSeen(.lessons)
        store.markSeen(.lessons)
        #expect(store.state.seenGuides == [GuideMode.lessons.rawValue])
    }

    @Test("a corrupt store file degrades to 'not seen' instead of crashing")
    func corruptFileFallsBackToEmpty() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("this is not json".utf8)
            .write(to: directory.appendingPathComponent(FirstRunStore.fileName))

        let store = FirstRunStore(directory: directory)
        #expect(store.state == .empty)
        #expect(store.shouldShowGuide(for: .adventure))
    }

    @Test("the store writes beside the other stores, not inside them")
    func storeHasItsOwnFile() {
        let directory = temporaryDirectory()
        let store = FirstRunStore(directory: directory)
        #expect(store.fileURL.lastPathComponent == "first-run.json")
        #expect(store.fileURL.lastPathComponent != ProgressStore.fileName)
        #expect(store.fileURL.lastPathComponent != GameProgressStore.fileName)
    }
}
