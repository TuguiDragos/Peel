import Foundation
@testable import PeelCore
import Testing

struct ObsidianLoaderTests {
    /// An archive laid out as `asar` writes one: the index's size, the index as JSON, then the files.
    static func archive(_ files: [String: Data]) throws -> Data {
        var entries: [String: Any] = [:]
        var contents = Data()
        for (name, data) in files.sorted(by: { $0.key < $1.key }) {
            entries[name] = ["size": data.count, "offset": String(contents.count)]
            contents.append(data)
        }
        let index = try JSONSerialization.data(withJSONObject: ["files": entries])
        let padding = (4 - index.count % 4) % 4
        func number(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let header = number(4 + index.count + padding) + number(index.count) + index + Data(count: padding)
        return number(4) + number(header.count) + header + contents
    }

    private func app(
        named name: String = "obsidian", version: String = "1.15.0", loads: Bool = true,
        in directory: borrowing TemporaryDirectory
    ) throws -> URL {
        let info: [String: String] = ["CFBundleIdentifier": "md.obsidian", "CFBundleShortVersionString": version]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: directory.file("Applications/Obsidian.app/Contents/Info.plist"))
        let package = try JSONSerialization.data(withJSONObject: ["name": name, "version": version])
        let loader = try Self.archive(["package.json": package, "main.js": Data("start()".utf8)])
        try loader.write(to: directory.file("Applications/Obsidian.app/Contents/Resources/app.asar"))
        if loads { try directory.file("Applications/Obsidian.app/Contents/Resources/obsidian.asar") }
        return directory.url.appending(path: "Applications/Obsidian.app", directoryHint: .isDirectory)
    }

    private func home(_ directory: borrowing TemporaryDirectory) -> URL {
        directory.url.appending(path: "home", directoryHint: .isDirectory)
    }

    @Test func readsTheVersionObsidianDownloadedForItself() throws {
        let directory = try TemporaryDirectory()
        let bundle = try app(in: directory)
        try directory.file("home/Library/Application Support/obsidian/obsidian-1.15.1.asar")

        let read = try #require(AppInspector.inspect(bundle, home: home(directory)))

        #expect(read.version == "1.15.0")
        #expect(read.runningVersion == "1.15.1")
        #expect(read.versionItRuns == "1.15.1")
    }

    @Test func picksTheNewestByItsNumbers() throws {
        let directory = try TemporaryDirectory()
        let bundle = try app(in: directory)
        for version in ["1.9.9", "1.16.0", "1.15.1"] {
            try directory.file("home/Library/Application Support/obsidian/obsidian-\(version).asar")
        }

        #expect(AppInspector.inspect(bundle, home: home(directory))?.runningVersion == "1.16.0")
    }

    @Test func runsTheAppsOwnVersionWhenNothingNewerIsThere() throws {
        for downloaded in ["obsidian-1.15.0.asar", "obsidian-1.14.9.asar", "obsidian-next.asar"] {
            let directory = try TemporaryDirectory()
            let bundle = try app(in: directory)
            try directory.file("home/Library/Application Support/obsidian/\(downloaded)")

            let read = try #require(AppInspector.inspect(bundle, home: home(directory)))
            #expect(read.runningVersion == nil, "\(downloaded)")
            #expect(read.versionItRuns == "1.15.0", "\(downloaded)")
        }
    }

    @Test func passesOverWhatTheLoaderWouldNotLoad() throws {
        let directory = try TemporaryDirectory()
        let bundle = try app(in: directory)
        let folder = try directory.directory("home/Library/Application Support/obsidian")
        try directory.directory("home/Library/Application Support/obsidian/obsidian-1.17.0.asar")
        let target = try directory.file("elsewhere/obsidian.asar")
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "obsidian-1.16.0.asar"), withDestinationURL: target
        )

        #expect(AppInspector.inspect(bundle, home: home(directory))?.runningVersion == nil)
    }

    @Test func readsNothingForAnotherElectronApp() throws {
        for (name, loads) in [("other", true), ("obsidian", false)] {
            let directory = try TemporaryDirectory()
            let bundle = try app(named: name, loads: loads, in: directory)
            try directory.file("home/Library/Application Support/obsidian/obsidian-1.15.1.asar")

            #expect(AppInspector.inspect(bundle, home: home(directory))?.runningVersion == nil, "\(name)")
        }
    }

    @Test func aNewVersionIsAnotherBuild() {
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Obsidian.app"), bundleIdentifier: "md.obsidian", name: "Obsidian",
            version: "1.15.0"
        )

        #expect(!app.withRunningVersion("1.15.1").isTheSameBuild(as: app))
        #expect(app.withRunningVersion("1.15.1").isTheSameBuild(as: app.withRunningVersion("1.15.1")))
    }
}
