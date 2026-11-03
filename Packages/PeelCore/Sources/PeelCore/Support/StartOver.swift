import Foundation
internal import PeelPrivileged

/// What starting over one of Peel's own files did.
public enum StartOver: Sendable, Equatable {
    /// The file that couldn't be read is kept beside a new one, under another name.
    case started
    /// The file can be read, or isn't there, so it stays as it is.
    case notNeeded
    /// The file couldn't be set aside, so nothing changed.
    case couldNotSetAside(FileProblem)

    /// Sets the file at `url` aside under another name, and answers what came of it.
    static func settingAside(_ url: URL) -> StartOver {
        do {
            try DamagedFile.settingAside(url)
            return .started
        } catch {
            return .couldNotSetAside(.failed(SystemError(error)))
        }
    }
}
