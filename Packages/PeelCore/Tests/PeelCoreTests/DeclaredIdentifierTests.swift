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

    @Test func aCrashReportDeclaresTheBundleOnItsFirstLineHoweverLongItIs() throws {
        let directory = try TemporaryDirectory()
        let metadata = #"{"bug_type":"309","bundleID":"org.example.notes","name":"Notes Example"}"#
        let body = String(repeating: "x", count: 2_000_000)
        let contents = Data("\(metadata)\n\(body)".utf8)
        let name = "Notes Example-2026-09-01-101010"
        let report = try directory.file("Logs/DiagnosticReports/\(name).ips", contents: contents)
        let loose = try directory.file("Logs/\(name).ips", contents: contents)
        let text = try directory.file("Logs/DiagnosticReports/\(name).diag", contents: contents)

        #expect(DeclaredIdentifier.of(report, kind: .logs) == "org.example.notes")
        #expect(DeclaredIdentifier.outranksTheName(of: report, kind: .logs))
        #expect(DeclaredIdentifier.of(loose, kind: .logs) == nil)
        #expect(DeclaredIdentifier.of(text, kind: .logs) == nil)
        #expect(!DeclaredIdentifier.outranksTheName(of: loose, kind: .logs))
    }
}
