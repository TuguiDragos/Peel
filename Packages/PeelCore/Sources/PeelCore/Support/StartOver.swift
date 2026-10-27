/// What starting over one of Peel's own files did.
public enum StartOver: Sendable, Equatable {
    /// The file that couldn't be read is kept beside a new one, under another name.
    case started
    /// The file can be read, or isn't there, so it stays as it is.
    case notNeeded
    /// The file couldn't be set aside, so nothing changed.
    case couldNotSetAside
}
