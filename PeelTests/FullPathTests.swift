import Foundation
@testable import Peel
import Testing

struct FullPathTests {
    @Test func aFolderPathEndsWithoutASlashAsFinderCopiesIt() {
        #expect(URL(filePath: "/Users/me/Library/Caches/org.example/", directoryHint: .isDirectory).fullPath
            == "/Users/me/Library/Caches/org.example")
        #expect(URL(filePath: "/Users/me/a file.txt", directoryHint: .notDirectory).fullPath == "/Users/me/a file.txt")
        #expect(URL(filePath: "/", directoryHint: .isDirectory).fullPath == "/")
    }
}
