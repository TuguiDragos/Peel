import AppKit

/// Tells when macOS is asking the user whether Peel may read files it protects: another app's data, or a folder such
/// as Documents or a removable volume. On macOS 26 the question comes in a dialog shown by UserNotificationCenter,
/// and the scan that caused it waits for the answer. With Full Disk Access, macOS doesn't ask.
public enum AppDataQuestion {
    public static let asker = "com.apple.UserNotificationCenter"

    public static func isAsked(frontmost: String?, hasFullDiskAccess: Bool) -> Bool {
        frontmost == asker && !hasFullDiskAccess
    }

    /// The same, read now on any thread.
    static func isOnScreen() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmost == asker else { return false }
        return isAsked(frontmost: frontmost, hasFullDiskAccess: FullDiskAccess.currentState() == .granted)
    }
}
