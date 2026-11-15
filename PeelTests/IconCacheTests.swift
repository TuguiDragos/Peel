import AppKit
import Foundation
@testable import Peel
import Testing

@MainActor
struct IconCacheTests {
    @Test func everyIconAListAskedForIsThereWhenItsRowDraws() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let apps = try (0..<600).map { number in
            let app = folder.appending(path: "Icon \(number).app", directoryHint: .isDirectory)
            let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "org.example.icon.\(number)", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
            return app
        }
        defer { IconCache.forget(apps) }

        await IconCache.warm(apps)

        let rebuilt = apps.filter { IconCache.icon(for: $0) === IconCache.anyApp }
        #expect(rebuilt.isEmpty, "\(rebuilt.count) rows found their icon gone and had it built again")
    }
}
