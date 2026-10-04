import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct TerminalToolTests {
    static let prefix = URL(filePath: "/opt/homebrew", directoryHint: .isDirectory)

    @Test func aPrefixEndingInASlashGivesPathsWithOneSlashBetweenNames() {
        let prefix = URL(filePath: "/opt/homebrew/", directoryHint: .isDirectory)
        let lines = TerminalTool.allCases.flatMap { $0.setup(prefix: prefix) }.flatMap(\.lines)
        #expect(lines.contains { $0.contains("/opt/homebrew/share/zsh-completions") })
        for line in lines {
            #expect(!line.replacing("://", with: "").contains("//"), "\(line)")
        }
    }

    @Test func everyLineForZshrcIsZshThatParses() async throws {
        for tool in TerminalTool.allCases {
            for setup in tool.setup(prefix: Self.prefix) where setup.place != .terminal {
                let answer = await Subprocess.run(
                    "/bin/zsh",
                    ["-f", "-n", "-c", setup.lines.joined(separator: "\n")],
                    environment: [:],
                    timeout: 10
                )
                guard case .success(let output) = answer else { throw POSIXError(.EIO) }
                #expect(output.status == 0 && output.errorText.isEmpty, "\(tool): \(output.errorText)")
            }
        }
    }

    @Test func theShellsToolsAreListedInTheOrderTheirLinesLoad() throws {
        let shell = TerminalTool.allCases.filter { $0.group == .shell }
        let place = { (tool: TerminalTool) in try #require(shell.firstIndex(of: tool)) }
        #expect(try place(.zshCompletions) < place(.fzfTab))
        #expect(try place(.fzfTab) < place(.zshAutosuggestions))
        #expect(try place(.zoxide) > place(.zshCompletions))
        #expect(shell.last == .zshSyntaxHighlighting)
        let last = TerminalTool.allCases.filter {
            $0.setup(prefix: Self.prefix).contains { $0.place == .lastLineOfZshrc }
        }
        #expect(last == [.zshSyntaxHighlighting])
    }

    @Test func gitsOwnKeysInTheCommandsAreOnesTheGitOnThisMacKnows() async throws {
        let git = try #require(await GitConfig.find(home: FileManager.default.temporaryDirectory))
        let known = try #require(await git.knownKeys())
        let keys = TerminalTool.allCases.flatMap { $0.setup(prefix: Self.prefix) }.flatMap(\.lines)
            .filter { $0.hasPrefix("git config --global ") }
            .map { $0.split(separator: " ")[3].lowercased() }
            .filter { !$0.hasPrefix("delta.") }
        #expect(!keys.isEmpty)
        for key in keys {
            #expect(known.contains(key), "\(key)")
        }
    }

    @Test func eachInstallCommandNamesEveryFormulaTheToolNeeds() {
        #expect(TerminalTool.fzfTab.installCommand == "brew install fzf fzf-tab")
        #expect(TerminalTool.delta.installCommand == "brew install git-delta")
        for tool in TerminalTool.allCases {
            #expect(tool.formulae.contains(tool.formula), "\(tool)")
            #expect(tool.project.scheme == "https", "\(tool)")
        }
        #expect(Set(TerminalTool.allCases.map(\.formula)).count == TerminalTool.allCases.count)
    }

    @Test func homebrewSaysWhetherAToolIsStillOffered() {
        let names: Set<String> = ["fzf", "fzf-tab", "tlrc"]
        let retired = HomebrewRetirement(
            stage: .disabled,
            reason: .unmaintained,
            disableDate: nil,
            replacement: .formula("tlrc")
        )
        #expect(
            TerminalTool.tlrc.availability(known: names, packages: [HomebrewPackage(name: "tlrc", kind: .formula)])
                == .available
        )
        #expect(TerminalTool.fzfTab.availability(known: ["fzf-tab"], packages: []) == .unknownToHomebrew)
        #expect(
            TerminalTool.tlrc.availability(
                known: names,
                packages: [HomebrewPackage(name: "tlrc", kind: .formula, retirement: retired)]
            ) == .retired(retired)
        )
        #expect(
            TerminalTool.fzfTab.availability(
                known: names,
                packages: [HomebrewPackage(name: "fzf", kind: .formula, retirement: retired)]
            ) == .retired(retired)
        )
    }

    @Test func aToolIsInstalledOnlyWhenHomebrewLinkedEveryFormulaItNeeds() throws {
        let prefix = FileManager.default.temporaryDirectory.appending(path: "TerminalToolTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cellar = prefix.appending(path: "Cellar/fzf-tab/1.3.0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appending(path: "opt"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: prefix.appending(path: "opt/fzf-tab"), withDestinationURL: cellar)
        #expect(!TerminalTool.fzfTab.isInstalled(prefix: prefix))
        try FileManager.default.createDirectory(at: prefix.appending(path: "Cellar/fzf/0.74.4"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: prefix.appending(path: "opt/fzf"),
            withDestinationURL: prefix.appending(path: "Cellar/fzf/0.74.4")
        )
        #expect(TerminalTool.fzfTab.isInstalled(prefix: prefix))
    }
}
