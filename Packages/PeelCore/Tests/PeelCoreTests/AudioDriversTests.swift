import Foundation
@testable import PeelCore
import Testing

struct AudioDriversTests {
    @Test func namesTheDriversARemovalTookFromTheFolderMacOSLoadsThemFrom() {
        let root = URL(filePath: "/private/tmp/org.example.root", directoryHint: .isDirectory)
        let moved = [
            "Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver",
            "Library/Audio/Plug-Ins/Components/Example.component",
            "Library/Audio/Plug-Ins/HAL/notes.txt",
            "Users/me/Library/Audio/Plug-Ins/HAL/Personal.driver",
        ].map { path in
            TrashedItem(originalURL: root.appending(path: path), trashedURL: root.appending(path: ".Trash/x"), date: .now)
        }

        #expect(AudioDrivers.awaitingARestart(after: TrashResult(trashed: moved), root: root) == ["BlackHole2ch"])
    }

    @Test func knowsADriverByTheFolderMacOSLoadsItFrom() {
        let root = URL(filePath: "/private/tmp/org.example.root", directoryHint: .isDirectory)
        let isOne = { (path: String) in AudioDrivers.isOne(root.appending(path: path), root: root) }

        #expect(isOne("Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"))
        #expect(!isOne("Library/Audio/Plug-Ins/HAL/notes.txt"))
        #expect(!isOne("Library/Audio/Plug-Ins/Components/Example.component"))
        #expect(!isOne("Users/me/Library/Audio/Plug-Ins/HAL/Personal.driver"))
    }
}
