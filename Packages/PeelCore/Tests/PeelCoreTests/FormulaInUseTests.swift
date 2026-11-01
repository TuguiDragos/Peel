import Foundation
@testable import PeelCore
import Testing

@Suite struct FormulaInUseTests {
    @Test func namesWhatRunsFromAFormulaAndTheJobThatStartsIt() throws {
        let directory = try TemporaryDirectory()
        let cellar = directory.url.appending(path: "Cellar", directoryHint: .isDirectory)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        func found(_ name: String) -> FormulaInUse {
            FormulaInUse.of(formula: name, cellar: cellar, home: home, root: root)
        }

        #expect(found("tool@1").isEmpty)
        let process = try directory.runningProgram("Cellar/tool@1/1.0/bin/toold")
        defer { process.terminate() }
        #expect(found("tool@1").programs == ["toold"])
        #expect(found("tool@1").stopCommand == nil)
        #expect(found("other").isEmpty)

        try directory.file("root/Library/LaunchDaemons/homebrew.mxcl.tool@1.plist")
        #expect(found("tool@1").stopCommand == "sudo brew services stop tool@1")
        try directory.file("home/Library/LaunchAgents/homebrew.mxcl.tool@1.plist")
        #expect(found("tool@1").stopCommand == "brew services stop tool@1")
        #expect(found("other").isEmpty)
    }
}
