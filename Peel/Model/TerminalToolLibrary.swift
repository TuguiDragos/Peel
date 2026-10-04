import Foundation
import Observation
import PeelCore

@Observable
final class TerminalToolLibrary {
    private(set) var prefix: URL?
    private(set) var hasLooked = false
    private(set) var installed: Set<TerminalTool> = []
    private(set) var known: Set<String>?
    private(set) var packages: [HomebrewPackage] = []

    func refresh() async {
        prefix = Homebrew.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
        hasLooked = true
        installed = prefix.map { prefix in Set(TerminalTool.allCases.filter { $0.isInstalled(prefix: prefix) }) } ?? []
        guard prefix != nil, known == nil, await Homebrew.hasLocalDefinitions() else { return }
        let names = await Homebrew.formulaNames()
        guard !names.isEmpty else { return }
        packages = await Homebrew.formulae(named: Set(TerminalTool.allCases.flatMap(\.formulae)).filter(names.contains).sorted())
        known = names
    }

    func availability(of tool: TerminalTool) -> TerminalTool.Availability {
        known.map { tool.availability(known: $0, packages: packages) } ?? .available
    }
}
