import Foundation
@testable import Peel
import Testing

@MainActor
struct DuplicateLibraryTests {
    @Test func keepsItsFoldersInTheDefaultsItIsGiven() throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let folder = URL(filePath: "/Users/me/Pictures", directoryHint: .isDirectory)

        DuplicateLibrary(defaults: made.defaults).folders = [folder]

        #expect(made.defaults.stringArray(forKey: "duplicateFolders") == ["/Users/me/Pictures/"])
        #expect(DuplicateLibrary(defaults: made.defaults).folders == [folder])
    }
}
