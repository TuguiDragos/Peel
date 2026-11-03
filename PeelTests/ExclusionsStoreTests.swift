import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct ExclusionsStoreTests {
    @Test func startingOverAListItCanReadKeepsSayingWhatCouldNotBeSaved() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let path = folder.path(percentEncoded: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            try? FileManager.default.removeItem(at: folder)
        }
        let exclusions = ExclusionsStore(store: ExclusionStore(url: folder.appending(path: "exclusions.json")))
        await exclusions.add(paths: [URL(filePath: "/Users/x/Kept")])
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        await exclusions.add(paths: [URL(filePath: "/Users/x/Unsaved")])
        let refusedWrite = SystemError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(exclusions.couldNotSave && exclusions.whyNotSaved == .failed(refusedWrite))

        let answer = await exclusions.startOver()

        #expect(answer == .notNeeded)
        #expect(exclusions.couldNotSave, "a change still unsaved was no longer said")
        #expect(exclusions.whyNotSaved == .failed(refusedWrite))
        #expect(exclusions.exclusions.paths.count == 2)
    }
}
