import AppKit
import Observation

/// Tracks the bundle identifier of the app in front, from the workspace's notifications. Read from the
/// workspace on demand, it would give Observation nothing to track, and a page would not notice macOS
/// bringing its own dialog to the front.
@Observable
final class FrontmostApp {
    static let shared = FrontmostApp()

    private(set) var bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let identifier = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated { FrontmostApp.shared.bundleIdentifier = identifier }
        }
    }
}
