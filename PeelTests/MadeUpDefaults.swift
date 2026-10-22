import Foundation
import Testing

/// A preference domain kept at a path of the test's own, so cfprefsd writes nothing in the real Preferences folder,
/// where a domain named like an app's would get a file that cfprefsd writes again after the test has let it go.
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
