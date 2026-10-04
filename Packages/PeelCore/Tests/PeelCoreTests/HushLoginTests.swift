import Foundation
@testable import PeelCore
import Testing

struct HushLoginTests {
    private func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "HushLoginTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func isOnExactlyWhenLoginFindsTheFile() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = HushLogin.url(in: home)
        #expect(!HushLogin.isOn(in: home))

        try Data().write(to: file)
        #expect(HushLogin.isOn(in: home))

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(HushLogin.isOn(in: home))

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: home.appending(path: "nowhere"))
        #expect(!HushLogin.isOn(in: home))

        try Data().write(to: home.appending(path: "somewhere"))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: home.appending(path: "somewhere"))
        #expect(HushLogin.isOn(in: home))
    }

    @Test func turningOnLeavesAnEmptyFileOnlyTheAccountWrites() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(HushLogin.turnOn(in: home))
        let attributes = try FileManager.default.attributesOfItem(atPath: HushLogin.url(in: home).path(percentEncoded: false))
        #expect(attributes[.type] as? FileAttributeType == .typeRegular)
        #expect(attributes[.size] as? Int == 0)
        let permissions = try #require(attributes[.posixPermissions] as? Int)
        #expect(permissions & 0o600 == 0o600)
        #expect(permissions & 0o022 == 0)
    }

    @Test func turningOnKeepsTheFileThatIsThere() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = HushLogin.url(in: home)
        try Data("kept".utf8).write(to: file)
        let before = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.systemFileNumber] as? Int

        #expect(HushLogin.turnOn(in: home))
        #expect(try Data(contentsOf: file) == Data("kept".utf8))
        #expect(try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.systemFileNumber] as? Int == before)
    }

    @Test func turningOnNeverWritesThroughALink() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appending(path: "elsewhere")
        try FileManager.default.createSymbolicLink(at: HushLogin.url(in: home), withDestinationURL: target)

        #expect(!HushLogin.turnOn(in: home))
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
    }
}
