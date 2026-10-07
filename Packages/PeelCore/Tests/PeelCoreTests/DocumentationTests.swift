import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

struct DocumentationTests {
    static let documents = [
        "README.md", "SAFETY.md", "ARCHITECTURE.md", "CONTRIBUTING.md", "TERMINAL.md", "GUIDE.md", "PRIVACY.md",
        "SECURITY.md", "CHANGELOG.md",
    ]

    @Test func everyNameADocumentGivesIsInTheCode() throws {
        let words = try Self.words(in: Self.code())
        var missing: [String] = []
        for document in Self.documents {
            let text = try String(contentsOf: LineLengthTests.repository.appending(path: document), encoding: .utf8)
            for name in Self.names(in: text) where !words.contains(Substring(name)) && !Self.isInTheSDK(name) {
                missing.append("\(document): \(name)")
            }
        }
        #expect(missing.isEmpty, "\(missing.joined(separator: "\n"))")
    }

    @Test func everyNumberADocumentGivesIsTheCodes() throws {
        func text(_ document: String) throws -> String {
            try String(contentsOf: LineLengthTests.repository.appending(path: document), encoding: .utf8)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let quitting = LineLengthTests.repository.appending(path: "Peel/Model/QuitBeforeRemoving.swift")
        let patience = try #require(
            try String(contentsOf: quitting, encoding: .utf8).firstMatch(of: /patience: Duration = \.seconds\((\d+)\)/)
        ).output.1
        let themes = TerminalThemeCatalog.all.count
        let languages = try StringCatalogTests.declaredLanguages().count + 1
        let tweaks = TweakCatalog.all.filter { $0.group != .terminal }.count
        let records = RemovalLog.maximumRecords.formatted(.number.locale(Locale(identifier: "en_US")))
        let idle = Int(HelperLifetime.standardIdleTimeout)
        let said = [
            ("GUIDE.md", "comes with \(themes) dark themes"),
            ("TERMINAL.md", "\(themes) dark themes"),
            ("README.md", "Available in \(languages) languages"),
            ("GUIDE.md", "Tweaks gathers \(tweaks) settings"),
            ("README.md", "keeps the latest \(records) items"),
            ("SAFETY.md", "keeps the most recent \(records) items"),
            ("ARCHITECTURE.md", "keeps the most recent \(records) items"),
            ("SAFETY.md", "at most \(HelperRequest.maximumItems) items in one request"),
            ("SAFETY.md", "quits \(idle) seconds after its last request ends"),
            ("CONTRIBUTING.md", "still open \(patience) seconds after Peel asked it"),
            ("ARCHITECTURE.md", "still open \(patience) seconds after Peel asked it"),
            ("SAFETY.md", "still open after \(patience) seconds"),
        ]

        let wrong = try said.filter { try !text($0.0).contains($0.1) }
        #expect(wrong.isEmpty, "\(wrong)")
    }

    @Test func aFileNameInTheCodeCountsAsItsWords() {
        #expect(Self.words(in: #"let tag = "CACHEDIR.TAG" // BrowserWallets.swift"#).isSuperset(of: ["CACHEDIR", "BrowserWallets"]))
    }

    @Test func readsTheTypeAPathOrACallStartsWith() {
        let text = "`TrashService`, `RemovalLog.canBeRead`, `Homebrew.overrides()`, `peel`, `HOMEBREW_NO_AUTO_UPDATE`"
        #expect(Self.names(in: text) == ["TrashService", "RemovalLog", "Homebrew"])
    }

    static func names(in text: String) -> [String] {
        let name = try! Regex(#"`([A-Z][A-Za-z0-9]+)(?:\.[A-Za-z0-9_]+)*(?:\(\))?`"#, as: (Substring, Substring).self)
        return text.matches(of: name).map { String($0.output.1) }
    }

    static func code() throws -> String {
        var files = try LineLengthTests.swiftFiles()
        files.append(LineLengthTests.repository.appending(path: "Peel.xcodeproj/project.pbxproj"))
        let support = LineLengthTests.repository.appending(path: "Support", directoryHint: .isDirectory)
        files += try FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "plist" }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    static func words(in text: String) -> Set<Substring> {
        Set(text.split { !($0.isLetter || $0.isNumber || $0 == "_") })
    }

    static func isInTheSDK(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return false }
        let sdk = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        let grep = Process()
        grep.executableURL = URL(filePath: "/usr/bin/grep")
        grep.arguments = ["-rlqw", "--include=*.h", "--include=*.swiftinterface", name, "\(sdk)/System/Library/Frameworks"]
        grep.standardOutput = FileHandle.nullDevice
        grep.standardError = FileHandle.nullDevice
        guard (try? grep.run()) != nil else { return false }
        grep.waitUntilExit()
        return grep.terminationStatus == 0
    }
}
