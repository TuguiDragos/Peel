import Foundation
@testable import PeelCore
import Testing

struct CommandLineToolsTests {
    @Test func offersTheCommandsOfTheToolFoldersButAnAppsAndHomebrews() throws {
        let directory = try TemporaryDirectory()
        let script = Data("#!/bin/sh\n".utf8)
        for path in ["root/usr/local/bin/kav", "root/usr/local/sbin/served", "root/opt/local/bin/ported", "home/bin/mine",
                     "home/.local/bin/mytool", "root/usr/local/libexec/helper", "root/Applications/Dock.app/Contents/MacOS/dock",
                     "root/usr/local/Cellar/jq/1.7/bin/jq"] {
            try directory.setPermissions(0o755, of: try directory.file(path, contents: script))
        }
        try directory.file("root/usr/local/bin/notes.txt", contents: script)
        try directory.directory("root/usr/local/bin/.lock")
        let bin = directory.url.appending(path: "root/usr/local/bin", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(
            at: bin.appending(path: "dock"),
            withDestinationURL: directory.url.appending(path: "root/Applications/Dock.app/Contents/MacOS/dock")
        )
        try FileManager.default.createSymbolicLink(atPath: bin.appending(path: "jq").path(percentEncoded: false),
                                                   withDestinationPath: "../Cellar/jq/1.7/bin/jq")
        try FileManager.default.createSymbolicLink(atPath: bin.appending(path: "gone").path(percentEncoded: false),
                                                   withDestinationPath: "/nowhere/gone")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let cellar = directory.url.appending(path: "root/usr/local/Cellar", directoryHint: .isDirectory)

        let tools = try #require(CommandLineTools.read(environment: environment, cellar: cellar))
        #expect(tools.names == ["kav", "served", "ported", "mine", "mytool", "dock", "jq"])
        #expect(tools.offered.map(\.name) == ["kav", "mine", "mytool", "ported", "served"])
        #expect(tools.offered.first?.url == bin.appending(path: "kav"))

        let cellarNotKnown = try #require(CommandLineTools.read(environment: environment, cellar: nil))
        #expect(cellarNotKnown.offered.map(\.name) == ["jq", "kav", "mine", "mytool", "ported", "served"])
    }

    @Test(.permissionsHold) func isNotKnownWhenAToolFolderCannotBeListed() throws {
        let directory = try TemporaryDirectory()
        try directory.setPermissions(0o755, of: try directory.file("home/bin/mine", contents: Data("#!/bin/sh\n".utf8)))
        try directory.directory("home/.local/bin")
        try directory.setPermissions(0, of: "home/.local/bin")
        defer { try? directory.setPermissions(0o755, of: "home/.local/bin") }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        #expect(CommandLineTools.read(environment: environment, cellar: nil) == nil)
    }
}
