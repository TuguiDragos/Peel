import Foundation
@testable import PeelCore
import Testing

struct SystemFoldersTests {
    @Test func everyNameIsProvedByTheSealedSystem() {
        let lists = [
            SystemFolders.applicationSupport, SystemFolders.caches, SystemFolders.logs, SystemFolders.preferences,
            SystemFolders.webKit, SystemFolders.cookies, SystemFolders.library,
        ]
        for (name, proof) in lists.joined() {
            #expect(Self.holds(proof, for: name), "\(name): \(proof)")
        }
    }

    private static func holds(_ proof: SystemFolders.Proof, for name: String) -> Bool {
        switch proof {
        case .part(let path):
            let part = URL(filePath: path).deletingPathExtension().lastPathComponent
            let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
            return FileManager.default.fileExists(atPath: path) && (part == stem || part.hasSuffix("." + stem))
        case .file(let path, let text):
            let bytes = try? Data(contentsOf: URL(filePath: path), options: .alwaysMapped)
            return bytes?.range(of: Data(text.utf8)) != nil
        case .image(let path, let text):
            return (try? SharedCache.image(path, holds: text)) == true
        case .through(let version, let proof):
            return ProcessInfo.processInfo.operatingSystemVersion.majorVersion > version || holds(proof, for: name)
        }
    }

    @Test func knowsMacOSsOwnByTheirNameOrApplesWhateverTheirCase() {
        #expect(SpaceInventory.isMacOSsOwn("com.apple.Spotlight"))
        #expect(SpaceInventory.isMacOSsOwn("CloudKit"))
        #expect(SpaceInventory.isMacOSsOwn("cloudkit"))
        #expect(SpaceInventory.isMacOSsOwn("Assistant"))
        #expect(!SpaceInventory.isMacOSsOwn("pip"))
        #expect(!SpaceInventory.isMacOSsOwn("org.example.app"))
    }

    @Test func aProcessKeepsItsCachesHTTPStorageAndTemporaryItemsUnderOneName() {
        #expect(SystemFolders.keeps("familycircled", in: .caches))
        #expect(SystemFolders.keeps("familycircled", in: .httpStorages))
        #expect(SystemFolders.keeps("familycircled", in: .temporaryItems))
        #expect(!SystemFolders.keeps("familycircled", in: .library))
    }
}
