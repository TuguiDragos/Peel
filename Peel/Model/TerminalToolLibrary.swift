import Foundation
import Observation
import PeelCore

@Observable
final class TerminalToolLibrary {
    struct State: Equatable {
        var prefix: URL?
        var installed: Set<TerminalTool>
        var unrunnable: HomebrewChoice.Unrunnable?
        var refused: HomebrewChoice.Unrunnable?
    }

    struct Catalog {
        let known: Set<String>
        let packages: [HomebrewPackage]
    }

    /// Whether Homebrew was asked which tools it still offers: not yet, while the question runs, and what it
    /// answered, nil when it could not be asked.
    enum Asked {
        case notAsked
        case asking
        case answered(Catalog?)
    }

    private(set) var state: State?
    private(set) var asked = Asked.notAsked
    private var askingHomebrew: Task<Void, Never>?

    func refresh() async {
        let prefix = Homebrew.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
        let unrunnable = HomebrewChoice().unrunnable()
        let refused = Homebrew.refusedInAUsualPlace()
        state = State(
            prefix: prefix, installed: Self.installed(prefix: prefix, refused: refused, unrunnable: unrunnable),
            unrunnable: unrunnable, refused: refused
        )
        guard let prefix else { return }
        if case .notAsked = asked {
            asked = .asking
            askingHomebrew = Task {
                asked = .answered(await Self.askHomebrew(prefix: prefix))
                askingHomebrew = nil
            }
        }
        await askingHomebrew?.value
    }

    /// What is on the disk under the `brew` Peel runs, or under one it won't run, which it never asks: that a tool is
    /// installed is only a look at a folder.
    static func installed(
        prefix: URL?, refused: HomebrewChoice.Unrunnable?, unrunnable: HomebrewChoice.Unrunnable?
    ) -> Set<TerminalTool> {
        let brew = (refused ?? unrunnable)?.brew
        guard let folder = prefix ?? brew?.deletingLastPathComponent().deletingLastPathComponent() else { return [] }
        return Set(TerminalTool.allCases.filter { $0.isInstalled(prefix: folder) })
    }

    func availability(of tool: TerminalTool) -> TerminalTool.Availability? {
        Self.availability(of: tool, in: asked)
    }

    /// What the page says of a tool: nothing while Homebrew is being asked, its answer once it has one, and
    /// available, with its commands, before Homebrew is asked or when it could not be.
    static func availability(of tool: TerminalTool, in asked: Asked) -> TerminalTool.Availability? {
        switch asked {
        case .notAsked: .available
        case .asking: nil
        case .answered(let catalog):
            catalog.map { tool.availability(known: $0.known, packages: $0.packages) } ?? .available
        }
    }

    /// Homebrew's answer from its local copy of the definitions, and nothing when it has none or when its own
    /// settings would make it update its lists over the network first, so the Terminal page goes nowhere.
    private static func askHomebrew(prefix: URL) async -> Catalog? {
        guard await Homebrew.hasLocalDefinitions(), !Homebrew.fetchesItsListsFirst(prefix: prefix),
              let overrides = await Homebrew.overrides(), !overrides.contains(.updatesItself)
        else { return nil }
        let names = await Homebrew.formulaNames()
        guard !names.isEmpty else { return nil }
        let packages = await Homebrew.formulae(
            named: Set(TerminalTool.allCases.flatMap(\.formulae)).filter(names.contains).sorted()
        )
        return Catalog(known: names, packages: packages)
    }
}
