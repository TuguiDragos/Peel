import Foundation
@testable import PeelCore
import Testing

struct OwnProgramTests {
    @Test func aProgramLeftAloneIsNotReplaced() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Peel.app/Contents/MacOS/Peel")
        #expect(!OwnProgram(path: program.path(percentEncoded: false)).isReplaced)
    }

    @Test func aFileWrittenAfterTheOldOneWentReplacesIt() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Peel.app/Contents/MacOS/Peel")
        let own = OwnProgram(path: program.path(percentEncoded: false))
        try FileManager.default.removeItem(at: program)
        _ = try directory.file("Peel.app/Contents/MacOS/Peel")
        #expect(own.isReplaced)
    }

    @Test func aFileRenamedOverItReplacesIt() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Peel.app/Contents/MacOS/Peel")
        let own = OwnProgram(path: program.path(percentEncoded: false))
        let next = try directory.file("next")
        #expect(rename(next.path(percentEncoded: false), program.path(percentEncoded: false)) == 0)
        #expect(own.isReplaced)
    }

    @Test func aProgramThatIsGoneIsReplaced() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Peel.app/Contents/MacOS/Peel")
        let own = OwnProgram(path: program.path(percentEncoded: false))
        try FileManager.default.removeItem(at: program)
        #expect(own.isReplaced)
    }

    @Test func noPathSaysNothingWasReplaced() {
        #expect(!OwnProgram(path: nil).isReplaced)
    }

    @Test func thisProcessIsNotReplaced() {
        #expect(!OwnProgram().isReplaced)
    }
}
