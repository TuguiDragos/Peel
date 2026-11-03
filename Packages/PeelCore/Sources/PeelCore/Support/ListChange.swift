/// What a change of one of Peel's own lists did. A list that is there and can't be read is never written over, since
/// that would lose what it holds.
public enum ListChange: Sendable, Equatable {
    case saved
    /// And why, when Peel knows.
    case notSaved(FileProblem?)
}
