import Foundation
@testable import PeelCore
import Testing

struct ExtensionsLeftRunningTests {
    @Test func endsOnlyTheExtensionsStillRunningFromTheMovedApps() async throws {
        let directory = try TemporaryDirectory()
        let running = try directory.runningPrograms([
            "Applications/One.app/Contents/PlugIns/One.appex/Contents/MacOS/One",
            "Applications/Two.app/Contents/PlugIns/Two.appex/Contents/MacOS/Two",
            "Applications/One.app/Contents/Helpers/tool",
            "Other.app/Contents/PlugIns/Other.appex/Contents/MacOS/Other",
        ])
        defer { running.forEach { $0.terminate() } }
        let trash = try directory.directory("Trash")
        let moved = try ["One.app", "Two.app"].map { name in
            let destination = trash.appending(path: name)
            try FileManager.default.moveItem(at: directory.url.appending(path: "Applications/\(name)"), to: destination)
            return destination
        }

        let ended = await ExtensionsLeftRunning.end(runningFrom: moved, within: 60)

        #expect(Set(ended) == [running[0].processIdentifier, running[1].processIdentifier])
        #expect(!ended.contains(where: ProcessEnds.isRunning))
        #expect(kill(running[2].processIdentifier, 0) == 0)
        #expect(kill(running[3].processIdentifier, 0) == 0)
    }
}
