/// Tells when macOS is asking the user whether Peel may read another app's data. On macOS 26 the question comes
/// in a dialog shown by UserNotificationCenter, and the scan that caused it waits for the answer. With Full Disk
/// Access, macOS doesn't ask.
public enum AppDataQuestion {
    public static let asker = "com.apple.UserNotificationCenter"

    public static func isAsked(frontmost: String?, hasFullDiskAccess: Bool) -> Bool {
        frontmost == asker && !hasFullDiskAccess
    }
}
