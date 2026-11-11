import Foundation
import Testing

struct MotionKindTests {
    /// Changes that add or remove a view that takes room, so the views around it move: Reduce Motion stops them,
    /// which only `.movement` asks.
    static let takingRoom = [
        ("Peel/Views/Home/HomePermissionsView.swift", "home.states"),
        ("Peel/Views/Home/HomePermissionsView.swift", "helper.changing"),
        ("Peel/Views/BackgroundItems/BackgroundItemDetailView.swift", "item.state"),
        ("Peel/Views/BackgroundItems/BackgroundItemDetailView.swift", "item.isDisabled"),
        ("Peel/Views/Tweaks/TweakDetailView.swift", "tweaks.isChangedByPeel(tweak)"),
        ("Peel/Views/Terminal/TerminalPage.swift", "terminal.canPutBack"),
        ("Peel/Views/ResetSheet.swift", "plan.didReset"),
        ("Peel/Views/RemovalBar.swift", "isShowingMove"),
        ("Peel/Views/RemovalBar.swift", "isShowingWait"),
        ("Peel/Views/RemovalBar.swift", "isShowingScan"),
        ("Peel/Views/RemovalBar.swift", "isShowingWork"),
        ("Peel/Views/RemovalBar.swift", "reading.total"),
        ("Peel/Views/RemovalBar.swift", "reading.pages"),
        ("Peel/Views/RemovalBar.swift", "moved"),
        ("Peel/Views/RemovalBar.swift", "notice"),
        ("Peel/Views/AppHeader.swift", "hasWaitingUpdate"),
        ("Peel/Navigation/ToolSidebar.swift", "updater.newerVersion"),
        ("Peel/Views/Homebrew/HomebrewList.swift", "homebrew.commandHomebrewRuns == .upgradeAll"),
        ("Peel/Views/Homebrew/HomebrewList.swift", "homebrew.casksBeingForgotten.isEmpty"),
        ("Peel/Views/Homebrew/HomebrewList.swift", "homebrew.commandHomebrewRuns == command"),
    ]

    @Test func aChangeThatTakesRoomStopsUnderReduceMotion() throws {
        var fades: [String] = []
        for (file, value) in Self.takingRoom {
            let text = try String(contentsOf: LineLengthTests.repository.appending(path: file), encoding: .utf8)
            if !text.contains(".movement, value: \(value))") { fades.append("\(file): \(value)") }
        }
        #expect(fades.isEmpty, "These move the views around them as a fade: \(fades)")
    }

    @Test func aSymbolThatChangesAsksReduceMotionFirst() throws {
        let file = LineLengthTests.repository.appending(path: "Peel/Views/CopyButton.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains(".contentTransition(.symbolEffect(.replace))"))
        #expect(text.contains("reduceMotion ? .opacity : .symbolEffect(.replace)"))
    }
}
