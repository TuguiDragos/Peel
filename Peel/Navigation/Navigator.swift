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

    /// Opens About, where a newer Peel is told with how to get it, and brings Peel forward.
    func showAbout() {
        openWindow?(id: AboutView.windowID)
        NSApp.activate()
    }
}
