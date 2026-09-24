public import Foundation

/// Whether a file still carries the quarantine mark macOS puts on anything downloaded.
///
/// It matters for one thing here: from macOS 27, launchd does not run a job whose property list carries it.
/// Peel says so instead of starting a job that will never run. It never removes the mark from another app's
/// file, since that is the user's decision.
public enum Quarantine {
    public static func marks(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey])
        return values?.quarantineProperties != nil
    }

    /// True when the mark stops launchd from running the job, which it does from macOS 27.
    public static func stopsLaunchd(_ url: URL) -> Bool {
        guard #available(macOS 27, *) else { return false }
        return marks(url)
    }
}
