import AppKit
import Observation

/// Tracks the bundle identifier of the app in front, from the workspace's notifications. Read from the
/// workspace on demand, it would give Observation nothing to track, and a page would not notice macOS
/// bringing its own dialog to the front.
@Observable
final class FrontmostApp {
    static let shared = FrontmostApp()

    private(set) var bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    /// True once System Settings has been in front since Peel started, however the person got there.
    private(set) var hasShownSystemSettings = false

    init(observing: Bool = true) {
        note(bundleIdentifier)
        guard observing else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let identifier = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated { self?.note(identifier) }
        }
    }

    func note(_ identifier: String?) {
        bundleIdentifier = identifier
        if identifier == "com.apple.systempreferences" {
            hasShownSystemSettings = true
        }
    }
}
