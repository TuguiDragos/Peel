import Foundation
@testable import PeelCore
import Testing

struct SystemSupportFoldersTests {
    @Test func everyNameIsCarriedByAPartOfTheSealedSystem() {
        for (name, source) in SystemSupportFolders.named {
            #expect(FileManager.default.fileExists(atPath: source), "\(name): \(source)")
            #expect(URL(filePath: source).deletingPathExtension().lastPathComponent == name, "\(name): \(source)")
        }
    }
}
