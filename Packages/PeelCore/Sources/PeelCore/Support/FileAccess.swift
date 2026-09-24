public import Foundation

public enum FileAccess {
    /// True when the current user can't move `url` to the Trash without administrator rights.
    public static func requiresPrivilegesToRemove(_ url: URL) -> Bool {
        ParentAccess(url.deletingLastPathComponent()).requiresPrivileges(toRemove: url)
    }
}
