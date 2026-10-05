import Foundation
import Observation
import PeelCore

@Observable
final class TerminalToolLibrary {
    struct State: Equatable {
        var prefix: URL?
        var installed: Set<TerminalTool>
    }

    struct Catalog {
        let known: Set<String>
        let packages: [HomebrewPackage]
    }

    private(set) var state: State?
    private(set) var catalog: Catalog?
    private var askingHomebrew: Task<Void, Never>?

    func refresh() async {
        let prefix = Homebrew.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
        let installed = prefix.map { prefix in TerminalTool.allCases.filter { $0.isInstalled(prefix: prefix) } } ?? []
        state = State(prefix: prefix, installed: Set(installed))
        guard prefix != nil, catalog == nil else { return }
        if askingHomebrew == nil {
            askingHomebrew = Task {
                catalog = await Self.askHomebrew()
                askingHomebrew = nil
            }
        }
        await askingHomebrew?.value
    }

    func availability(of tool: TerminalTool) -> TerminalTool.Availability {
        catalog.map { tool.availability(known: $0.known, packages: $0.packages) } ?? .available
    }

    private static func askHomebrew() async -> Catalog? {
        guard await Homebrew.hasLocalDefinitions() else { return nil }
        let names = await Homebrew.formulaNames()
        guard !names.isEmpty else { return nil }
        let packages = await Homebrew.formulae(
            named: Set(TerminalTool.allCases.flatMap(\.formulae)).filter(names.contains).sorted()
        )
        return Catalog(known: names, packages: packages)
    }
}
