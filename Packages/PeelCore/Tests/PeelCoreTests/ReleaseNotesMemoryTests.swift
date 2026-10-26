import Foundation
@testable import PeelCore
import Testing

struct ReleaseNotesMemoryTests {
    private let notes = ReleaseNotes("New search", format: .plainText)!

    @Test func asksOnceForTheNotesOfEachVersion() {
        var memory = ReleaseNotesMemory()
        #expect(memory.asks("org.example.editor", version: "2.0"))

        memory.record(.notGiven, of: "org.example.editor", version: "2.0")
        #expect(!memory.asks("org.example.editor", version: "2.0"))
        #expect(memory.notes(of: "org.example.editor", version: "2.0") == nil)

        memory.record(.found(notes), of: "org.example.editor", version: "3.0")
        #expect(!memory.asks("org.example.editor", version: "3.0"))
        #expect(memory.notes(of: "org.example.editor", version: "3.0") == notes)
        #expect(memory.notes(of: "org.example.editor", version: "2.0") == nil)
    }

    @Test func asksAServerThatDidNotAnswerAgainLaterAndLessOften() {
        let start = Date(timeIntervalSince1970: 1_792_315_250)
        let hour: TimeInterval = 60 * 60
        var memory = ReleaseNotesMemory()

        memory.record(.unanswered, of: "org.example.editor", version: "3.0", at: start)

        #expect(!memory.asks("org.example.editor", version: "3.0", at: start + hour))
        #expect(memory.asks("org.example.editor", version: "3.0", at: start + 6 * hour))
        memory.record(.unanswered, of: "org.example.editor", version: "3.0", at: start + 6 * hour)
        memory.record(.unanswered, of: "org.example.editor", version: "3.0", at: start + 10 * hour)
        #expect(!memory.asks("org.example.editor", version: "3.0", at: start + 17 * hour))
        #expect(memory.asks("org.example.editor", version: "3.0", at: start + 17 * hour, force: true))
        #expect(memory.asks("org.example.editor", version: "3.0", at: start + 18 * hour))
        #expect(memory.asks("org.example.editor", version: "3.1", at: start + hour), "another version is asked at once")

        memory.record(.offline, of: "org.example.viewer", version: "5.0", at: start)
        #expect(memory.asks("org.example.viewer", version: "5.0", at: start), "nothing is learned offline")

        memory.record(.found(notes), of: "org.example.editor", version: "3.0", at: start + 18 * hour)
        memory.record(.unanswered, of: "org.example.editor", version: "3.0", at: start + 70 * hour)
        #expect(memory.notes(of: "org.example.editor", version: "3.0") == notes)
        #expect(!memory.asks("org.example.editor", version: "3.0", at: start + 70 * hour, force: true))
    }

    @Test func forgetsTheNotesOfAnUpdateNoLongerWaiting() {
        var memory = ReleaseNotesMemory()
        memory.record(.found(notes), of: "org.example.editor", version: "2.0")
        memory.record(.found(notes), of: "org.example.viewer", version: "5.0")

        memory.keep(only: ["org.example.editor": "2.0", "org.example.viewer": "5.1"])

        #expect(memory.notes(of: "org.example.editor", version: "2.0") == notes)
        #expect(memory.asks("org.example.viewer", version: "5.0"))
    }

    @Test func asksOnlyAboutAnUpdateThatWaits() {
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "org.example.editor", name: "Editor"
        )
        let update = UpdateStatus.updateAvailable(version: "2.0")
        let memory = ReleaseNotesMemory()
        let skipped = UpdatePreferences(skippedVersions: ["org.example.editor": "2.0"])
        let skippedBefore = UpdatePreferences(skippedVersions: ["org.example.editor": "1.9"])
        let ignored = UpdatePreferences(ignoredApps: ["org.example.editor"])

        #expect(memory.asks(about: update, of: app, with: UpdatePreferences()))
        #expect(!memory.asks(about: update, of: app, with: skipped))
        #expect(memory.asks(about: update, of: app, with: skippedBefore))
        #expect(!memory.asks(about: update, of: app, with: ignored))
        #expect(!memory.asks(about: .upToDate, of: app, with: UpdatePreferences()))
    }

    @Test func keepsTheNotesAcrossLaunches() async throws {
        let directory = try TemporaryDirectory()
        let store = ReleaseNotesStore(url: directory.url.appending(path: "Peel/release-notes.json"))
        #expect(await store.load() == ReleaseNotesMemory())

        var memory = ReleaseNotesMemory()
        memory.record(.found(notes), of: "org.example.editor", version: "2.0")
        memory.record(.unanswered, of: "org.example.viewer", version: "5.0")
        await store.save(memory)
        #expect(await store.load() == memory)

        try Data(#"{"entries":{"org.example.editor":{"version":"2.0"}}}"#.utf8).write(to: store.url)
        #expect(await !store.load().asks("org.example.editor", version: "2.0"), "an earlier file still reads")

        try Data("not notes".utf8).write(to: store.url)
        #expect(await store.load() == ReleaseNotesMemory(), "notes can always be asked for again")
    }
}
