import Foundation
@testable import PeelCore
import Testing

@Suite struct FormulaInUseTests {
    @Test func namesWhatRunsFromAFormulaAndTheJobThatStartsIt() throws {
        let directory = try TemporaryDirectory()
        let cellar = directory.url.appending(path: "Cellar", directoryHint: .isDirectory)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        func found(_ name: String, brew: String = "brew") -> FormulaInUse {
            FormulaInUse.of(formula: name, cellar: cellar, home: home, root: root, brew: brew)
        }

        #expect(found("tool@1").isEmpty)
        let process = try directory.runningProgram("Cellar/tool@1/1.0/bin/toold")
        defer { process.terminate() }
        #expect(found("tool@1").programs == ["toold"])
        #expect(found("tool@1").stopCommand == nil)
        #expect(found("other").isEmpty)

        try directory.file("root/Library/LaunchDaemons/homebrew.mxcl.tool@1.plist")
        #expect(found("tool@1").stopCommand == "sudo brew services stop tool@1")
        #expect(found("tool@1", brew: "/opt/brew/bin/brew").stopCommand == "sudo /opt/brew/bin/brew services stop tool@1")
        try directory.file("home/Library/LaunchAgents/homebrew.mxcl.tool@1.plist")
        #expect(found("tool@1").stopCommand == "brew services stop tool@1")
        #expect(found("other").isEmpty)
        try directory.file("home/Library/LaunchAgents/homebrew.mxcl.tool;id.plist")
        #expect(found("tool;id").stopCommand == "brew services stop 'tool;id'")
    }

    @Test func namesWhatAFormulaKeepsInVarAndEtcUnderItsName() throws {
        let directory = try TemporaryDirectory()
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)
        let data = try directory.file("prefix/var/tool@1/base/1/PG_VERSION").deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let settings = try directory.file("prefix/etc/tool@1/tool.conf").deletingLastPathComponent()
        try directory.file("prefix/var/tool/base/PG_VERSION")
        try directory.directory("prefix/Cellar")
        func found(_ name: String) -> FormulaInUse {
            FormulaInUse.of(
                formula: name, cellar: prefix.appending(path: "Cellar"), home: directory.url, root: directory.url,
                brew: "brew"
            )
        }

        #expect(found("tool@1").dataFolders.map(\.lastPathComponent) == ["tool@1", "tool@1"])
        #expect(found("tool@1").dataFolders.map { PathPattern.comparablePath(of: $0) }
            == [data, settings].map { PathPattern.comparablePath(of: $0) })
        #expect(found("other").dataFolders.isEmpty)
    }
}
