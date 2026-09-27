import Foundation
@testable import PeelCore
import Testing

struct DeclaredIdentifierTests {
    private func plist(_ values: [String: String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    @Test func aPlugInDeclaresTheIdentifierInItsBundle() throws {
        let directory = try TemporaryDirectory()
        let plugIn = try directory.directory("Massive.vst3")
        let info = try plist(["CFBundleIdentifier": "org.example.massive"])
        try directory.file("Massive.vst3/Contents/Info.plist", contents: info)

        #expect(DeclaredIdentifier.of(plugIn, kind: .plugIns) == "org.example.massive")
        #expect(DeclaredIdentifier.of(plugIn, kind: .caches) == nil)
        #expect(DeclaredIdentifier.of(try directory.directory("Empty.component"), kind: .plugIns) == nil)
    }

    @Test func aContainerNamedByAUUIDDeclaresItsOwner() throws {
        let directory = try TemporaryDirectory()
        let metadata = try plist(["MCMMetadataIdentifier": "org.example.notes"])
        let file = ".com.apple.containermanagerd.metadata.plist"
        let byUUID = try directory.directory("3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        try directory.file("3F2504E0-4F89-11D3-9A0C-0305E82C3301/\(file)", contents: metadata)
        let byName = try directory.directory("org.example.other")
        try directory.file("org.example.other/\(file)", contents: metadata)

        #expect(DeclaredIdentifier.of(byUUID, kind: .containers) == "org.example.notes")
        #expect(DeclaredIdentifier.of(byName, kind: .containers) == nil)
    }
}
