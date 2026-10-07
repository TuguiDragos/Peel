import Foundation
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
