import Darwin
public import Foundation
internal import PeelPrivileged

/// Why a folder someone chose can't be reached, read from what macOS answers for its path.
public enum FolderReach: Sendable, Hashable {
    /// The disk it is on, named as in `/Volumes`, isn't connected.
    case diskNotConnected(String)
    /// Nothing is at that path anymore.
    case gone
    /// Something other than a folder is there.
    case notAFolder
    /// Its permissions, or those of a folder on its way, keep this account out.
    case closed
    /// The disk didn't answer in time, as a network volume that stopped answering does.
    case didNotAnswer
    /// macOS answered with another error, which says why.
    case failed(SystemError)

    /// Why `folder` can't be reached, links followed, or nil when a folder is there.
    public static func problem(with folder: URL) -> FolderReach? {
        let path = PathPattern.comparablePath(of: folder)
        var info = stat()
        if stat(path, &info) == 0 {
            return info.st_mode & S_IFMT == S_IFDIR ? nil : .notAFolder
        }
        let code = errno
        switch code {
        case ENOENT, ENOTDIR:
            let names = PathComponents.of(path)
            if names.count > 1, names[0] == "Volumes", URL(filePath: "/Volumes/" + names[1]).isMissing {
                return .diskNotConnected(names[1])
            }
            return .gone
        case EACCES, EPERM: return .closed
        default: return .failed(SystemError(domain: NSPOSIXErrorDomain, code: Int(code)))
        }
    }
}
