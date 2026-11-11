import AppKit
import Observation
import SwiftUI

/// Requests to show a tool, or an app, that come from outside the sidebar: Shortcuts and Spotlight, the
/// menu bar panel, or a button on another page. `ContentView` carries out each one and clears it. A request only
/// opens a page, where the user can look and decide; it never removes anything.
@Observable
final class Navigator {
    @MainActor static let shared = Navigator()

    var requestedTool: Tool?
    /// An app to open in Applications, as a Shortcut found it on disk, so an app of the same name is never the one
    /// opened, and one installed a moment ago opens before the list has it.
    var requestedApp: URL?
    /// Apps a `peel://open` link or Peel's Dock icon named, opened together in Applications once Peel could read them,
    /// as several apps dropped on the list are.
    private var openedApps: [URL] = []

    func open(_ app: URL) {
        openedApps.append(app)
    }

    func takeOpenedApps() -> [URL] {
        defer { openedApps = [] }
        return openedApps
    }
    /// What waits for an app to quit before moving it. A request from outside Peel waits for it too, since the page it
    /// would replace gives that move up when it goes.
    private(set) var waitingForAQuit: Set<ObjectIdentifier> = []

    func noteWaitingForAQuit(_ waiter: AnyObject, _ isWaiting: Bool) {
        if isWaiting {
            waitingForAQuit.insert(ObjectIdentifier(waiter))
        } else {
            waitingForAQuit.remove(ObjectIdentifier(waiter))
        }
    }

    /// Whether a request from outside Peel may change the page now: not under a sheet or a question, where the menus
    /// can't change it either, and not while something waits for an app to quit.
    func mayApplyRequests(windowHasASheet: Bool) -> Bool {
        !windowHasASheet && waitingForAQuit.isEmpty
    }
    /// The app's own action for opening a window, given at launch, which works whatever window is open or closed.
    @ObservationIgnored var openWindow: OpenWindowAction?

    private init() {}

    /// Shows `tool` in the main window and brings Peel forward. Bringing Peel forward alone does not open the
    /// window while another of its windows is open, such as Settings.
    func show(_ tool: Tool) {
        requestedTool = tool
        openWindow?(id: PeelApp.mainWindowID)
        NSApp.activate()
    }
}
