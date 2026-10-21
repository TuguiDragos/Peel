import Foundation
import Testing

/// A preference domain of a test's own, kept in a folder of its own: a suite named by a path lives at that path,
/// so cfprefsd writes nothing for it in the real Preferences folder, and forgetting it removes the folder. A domain
/// named like an app's would get a file there, which cfprefsd writes again on its own time once the test has let
/// the domain go.
struct MadeUpDefaults {
    private let folder: URL
    let defaults: UserDefaults

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "MadeUpDefaults-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = folder.appending(path: "org.example.peel-tests.plist").path(percentEncoded: false)
        defaults = try #require(UserDefaults(suiteName: name))
    }

    func forget() {
        try? FileManager.default.removeItem(at: folder)
    }
}
