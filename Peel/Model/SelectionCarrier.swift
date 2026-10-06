import Foundation
import Observation
import PeelCore

/// A storage tool whose selection travels: Move to Trash on any storage tool's page moves what is selected on this
/// tool's pages too, once each has been seen (`CarriedSelection`).
protocol CarriesSelection: AnyObject {
    /// What is selected on each of the tool's pages, a part for each page with something selected.
    var carriedParts: [CarriedSelection.Part] { get }
    /// The app to quit before `part` can move, or nil when none of its apps is open.
    func appToQuit(for part: CarriedSelection.Part) -> String?
    /// Moves what is still selected of `part`, by the tool's own routine and checks. Nil, moving nothing, when the
    /// tool keeps the whole part because one of its apps is open.
    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult?
    /// Brings the tool up to date once `parts` have moved, as after its own Move to Trash.
    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async
    func deselect(_ part: CarriedSelection.Part)
    /// Chooses the page in its tool, so the tool shows it when it is shown.
    func choose(_ page: CarriedSelection.Page)
}

extension CarriesSelection {
    func appToQuit(for part: CarriedSelection.Part) -> String? { nil }
    func choose(_ page: CarriedSelection.Page) {}
}

extension CarriesSelection where Self: RowSelection {
    func deselect(_ part: CarriedSelection.Part) {
        selectedURLs.subtract(part.sizes.keys)
    }
}

extension Tool {
    /// One of the tool's pages: `scope` names the page within the tool, and is empty for a tool that is one page.
    func page(_ scope: String = "") -> CarriedSelection.Page {
        CarriedSelection.Page(tool: rawValue, scope: scope)
    }
}

/// Carries what is selected on the storage tools' pages to Move to Trash on any of them, and moves it as one
/// removal: each part by its own tool, with that tool's checks, into one History entry.
@Observable
final class SelectionCarrier {
    private var carried = CarriedSelection()
    /// True while a Move to Trash moves the parts, one after another.
    private(set) var isMoving = false
    /// How many of `toMove` items have moved, brought up to date ten times a second while a move runs.
    private(set) var movedSoFar = 0
    private(set) var toMove = 0
    @ObservationIgnored private let tools: [Tool: any CarriesSelection]
    @ObservationIgnored private let apps: AppLibrary
    @ObservationIgnored private let history: RemovalHistoryStore
    @ObservationIgnored private let outcome: RemovalOutcome

    init(tools: [Tool: any CarriesSelection], apps: AppLibrary, history: RemovalHistoryStore, outcome: RemovalOutcome) {
        self.tools = tools
        self.apps = apps
        self.history = history
        self.outcome = outcome
    }

    func saw(_ page: CarriedSelection.Page) {
        carried.saw(page)
    }

    func hasSeen(_ page: CarriedSelection.Page) -> Bool {
        carried.hasSeen(page)
    }

    /// What Move to Trash moves from `page`: what is selected there and on every page seen before, in the
    /// sidebar's order.
    func parts(from page: CarriedSelection.Page) -> [CarriedSelection.Part] {
        var carried = carried
        carried.saw(page)
        let order = Tool.Group.allCases.flatMap(\.tools)
        return carried.parts(from: order.compactMap { tools[$0] }.flatMap(\.carriedParts), order: order.map(\.rawValue))
    }

    func appToQuit(among parts: [CarriedSelection.Part]) -> String? {
        parts.lazy.compactMap { part in self.tool(of: part)?.appToQuit(for: part) }.first
    }

    func deselect(_ part: CarriedSelection.Part) {
        tool(of: part)?.deselect(part)
    }

    func show(_ page: CarriedSelection.Page) {
        guard let tool = Tool(rawValue: page.tool) else { return }
        tools[tool]?.choose(page)
        Navigator.shared.requestedTool = tool
    }

    /// Moves `parts` as one removal. Each part is in History as soon as it moved, so nothing that moved is lost if
    /// Peel stops halfway, and a part whose tool kept it stays selected, with the app to quit named after.
    func move(_ parts: [CarriedSelection.Part]) async {
        isMoving = true
        movedSoFar = 0
        toMove = parts.reduce(0) { $0 + $1.count }
        let count = MoveCount()
        let watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.movedSoFar = count.value
            }
        }
        defer {
            watching.cancel()
            isMoving = false
        }
        var removal = RemovalInProgress()
        var appsToQuit: [String] = []
        let pass = await MoveCount.$current.withValue(count) {
            await QuitGuard.shared.run {
                await CarriedSelection.pass(parts) { part in
                    guard let tool = tool(of: part), let result = await tool.move(part, apps: apps) else {
                        appsToQuit.append(tool(of: part)?.appToQuit(for: part) ?? part.title)
                        return nil
                    }
                    await history.record(result, part: part.removalPart, sizes: part.measuredSizes, in: &removal)
                    return result
                }
            }
        }
        history.finish(removal)
        outcome.report(pass.result, appsToQuit: appsToQuit)
        for part in pass.refused {
            tool(of: part)?.deselect(part)
        }
        let moved = pass.moved.map(\.part)
        for name in moved.tools {
            guard let tool = Tool(rawValue: name) else { continue }
            await tools[tool]?.refresh(after: moved.filter { $0.page.tool == name }, apps: apps)
        }
    }

    private func tool(of part: CarriedSelection.Part) -> (any CarriesSelection)? {
        Tool(rawValue: part.page.tool).flatMap { tools[$0] }
    }
}
