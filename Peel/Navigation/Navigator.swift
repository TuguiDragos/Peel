import Foundation
import Observation

/// Requests to show a tool, or an app by name, that come from outside the sidebar: Shortcuts and Spotlight, the
/// menu bar panel, or a button on another page. `ContentView` carries out each one and clears it. A request only
/// opens a page, where the user can look and decide; it never removes anything.
@Observable
final class Navigator {
    @MainActor static let shared = Navigator()

    var requestedTool: Tool?
    /// The name of an app to open in Applications, as chosen in a Shortcut.
    var requestedAppName: String?

    private init() {}
}
