import Foundation
@testable import PeelCore
import Testing

@Suite struct KeptVersionsTests {
    @Test func listsEachYearOfTeXLiveAndSaysWhichAreNotInUse() throws {
        let directory = try TemporaryDirectory()
        for folder in ["2024", "2025", "texmf-local"] {
            try directory.file("root/usr/local/texlive/\(folder)/README", bytes: 64)
        }
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let years = TeXLive.years(root: root)
        try #require(years.map(\.lastPathComponent) == ["2024", "2025"])
        #expect(TeXLive.notes(on: years).isEmpty)

        try directory.directory("root/Library/TeX")
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "Library/TeX/Root"), withDestinationURL: years[1]
        )
        #expect(TeXLive.notes(on: years) == [years[0]: .notTheTeXLiveInUse])
    }

    @Test func listsEachSDKAndSaysWhichHaveANewerOneBeside() throws {
        let directory = try TemporaryDirectory()
        for folder in ["8.0.403", "9.0.100-rc.1.24452.12", "9.0.100", "x64/sdk/8.0.100"] {
            let path = folder.contains("/") ? folder : "sdk/\(folder)"
            try directory.file("root/usr/local/share/dotnet/\(path)/dotnet.dll", bytes: 64)
        }
        try directory.file("home/.dotnet/sdk/10.0.100/dotnet.dll", bytes: 64)
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let versions = DotNetSDKs.versions(home: home, root: root)

        #expect(versions.map(\.lastPathComponent) == ["10.0.100", "8.0.403", "9.0.100", "9.0.100-rc.1.24452.12", "8.0.100"])
        #expect(Set(DotNetSDKs.notes(on: versions).keys.map(\.lastPathComponent)) == ["8.0.403", "9.0.100-rc.1.24452.12"])
        #expect(Set(DotNetSDKs.notes(on: versions).values) == [.aNewerSDKIsInstalled])
    }
}
