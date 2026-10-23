import Foundation
@testable import PeelCore
import Testing

struct SystemFoldersTests {
    @Test func everyNameIsProvedByTheSealedSystem() throws {
        let lists = [
            SystemFolders.applicationSupport, SystemFolders.caches, SystemFolders.logs, SystemFolders.preferences,
        ]
        for (name, proof) in lists.joined() {
            switch proof {
            case .part(let path):
                let part = URL(filePath: path).deletingPathExtension().lastPathComponent
                let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
                #expect(FileManager.default.fileExists(atPath: path), "\(name): \(path)")
                #expect(part == stem || part.hasSuffix("." + stem), "\(name): \(path)")
            case .file(let path, let text):
                let bytes = try Data(contentsOf: URL(filePath: path), options: .alwaysMapped)
                #expect(bytes.range(of: Data(text.utf8)) != nil, "\(name): \(path)")
            case .image(let path, let text):
                #expect(try SharedCache.image(path, holds: text), "\(name): \(path)")
            }
        }
    }

    @Test func aProcessKeepsItsCachesHTTPStorageAndTemporaryItemsUnderOneName() {
        #expect(SystemFolders.keeps("familycircled", in: .caches))
        #expect(SystemFolders.keeps("familycircled", in: .httpStorages))
        #expect(SystemFolders.keeps("familycircled", in: .temporaryItems))
        #expect(!SystemFolders.keeps("familycircled", in: .library))
    }
}
