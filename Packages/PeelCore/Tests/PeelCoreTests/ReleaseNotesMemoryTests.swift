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

        memory.record(.unanswered, of: "org.example.editor", version: "3.0")
        #expect(memory.asks("org.example.editor", version: "3.0"), "a server that did not answer is asked again")

        memory.record(.found(notes), of: "org.example.editor", version: "3.0")
        #expect(!memory.asks("org.example.editor", version: "3.0"))
        #expect(memory.notes(of: "org.example.editor", version: "3.0") == notes)
        #expect(memory.notes(of: "org.example.editor", version: "2.0") == nil)
    }

    @Test func forgetsTheNotesOfAnUpdateNoLongerWaiting() {
        var memory = ReleaseNotesMemory()
        memory.record(.found(notes), of: "org.example.editor", version: "2.0")
        memory.record(.found(notes), of: "org.example.viewer", version: "5.0")

        memory.keep(only: ["org.example.editor": "2.0", "org.example.viewer": "5.1"])

        #expect(memory.notes(of: "org.example.editor", version: "2.0") == notes)
        #expect(memory.asks("org.example.viewer", version: "5.0"))
    }

    @Test func keepsTheNotesAcrossLaunches() async throws {
        let directory = try TemporaryDirectory()
        let store = ReleaseNotesStore(url: directory.url.appending(path: "Peel/release-notes.json"))
        #expect(await store.load() == ReleaseNotesMemory())

        var memory = ReleaseNotesMemory()
        memory.record(.found(notes), of: "org.example.editor", version: "2.0")
        await store.save(memory)
        #expect(await store.load() == memory)

        try Data("not notes".utf8).write(to: store.url)
        #expect(await store.load() == ReleaseNotesMemory(), "notes can always be asked for again")
    }
}
