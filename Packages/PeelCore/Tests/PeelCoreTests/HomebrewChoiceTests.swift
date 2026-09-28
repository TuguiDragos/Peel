import Darwin
import Foundation
@testable import PeelCore
import Testing

struct HomebrewChoiceTests {
    private func program(
        _ path: String, in directory: borrowing TemporaryDirectory, mode: mode_t = 0o755
    ) throws -> URL {
        let url = try directory.file(path)
        chmod(url.path(percentEncoded: false), mode)
        return url
    }

    @Test func takesOnlyARunnableBrewOfThisAccount() throws {
        let directory = try TemporaryDirectory()
        let brew = try program("opt/brew/bin/brew", in: directory)

        #expect(HomebrewChoice.refusal(of: brew) == nil)
        #expect(HomebrewChoice.refusal(of: try program("opt/brew/bin/python3", in: directory)) == .notBrew)
        #expect(HomebrewChoice.refusal(of: try program("plain/brew", in: directory, mode: 0o644)) == .notAProgram)
        #expect(HomebrewChoice.refusal(of: try directory.directory("folder/brew")) == .notAProgram)
        #expect(HomebrewChoice.refusal(of: try program("open/brew", in: directory, mode: 0o757)) == .writableByEveryone)
        #expect(HomebrewChoice.refusal(of: brew, user: getuid() + 1) == .ownedByAnotherAccount)
    }

    @Test func keepsTheChoiceUntilItIsForgotten() throws {
        let directory = try TemporaryDirectory()
        let brew = try program("opt/brew/bin/brew", in: directory)
        let choice = HomebrewChoice(url: directory.url.appending(path: "Peel/homebrew.json"))

        #expect(choice.load() == nil)
        #expect(choice.save(brew))
        #expect(choice.load()?.path(percentEncoded: false) == brew.path(percentEncoded: false))
        #expect(choice.save(nil))
        #expect(choice.load() == nil)
    }

    @Test func forgetsABrewThatCanNoLongerBeRun() throws {
        let directory = try TemporaryDirectory()
        let brew = try program("opt/brew/bin/brew", in: directory)
        let choice = HomebrewChoice(url: directory.url.appending(path: "homebrew.json"))
        #expect(choice.save(brew))

        chmod(brew.path(percentEncoded: false), 0o644)

        #expect(choice.load() == nil)
    }

    @Test func runsTheChosenBrewAndFindsItsOwnPrograms() throws {
        let directory = try TemporaryDirectory()
        let brew = try program("opt/brew/bin/brew", in: directory)
        let prefix = directory.url.appending(path: "opt/brew").path(percentEncoded: false)
        let standard = URL(filePath: "/opt/homebrew/bin/brew")

        #expect(Homebrew.executable(chosen: brew) == brew)
        let path = try #require(Homebrew.environment(autoUpdate: false, executable: brew)["PATH"])
        #expect(path.hasPrefix("\(prefix)/bin:\(prefix)/sbin:"))
        let usual = Homebrew.environment(autoUpdate: false)["PATH"]
        #expect(Homebrew.environment(autoUpdate: false, executable: standard)["PATH"] == usual)
    }
}
