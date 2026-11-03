/// Why a file couldn't be read or written: what stands where it should be, or what macOS answered.
public enum FileProblem: Error, Sendable, Hashable {
    case notAFile
    /// It is larger than Peel reads a file of its kind.
    case tooLarge
    /// What it holds isn't in the form Peel writes, as after an edit by hand.
    case damaged
    case failed(SystemError)
}
