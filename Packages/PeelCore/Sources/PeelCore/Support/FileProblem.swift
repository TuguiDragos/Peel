/// Why a file couldn't be read or written: what stands where it should be, or what macOS answered.
public enum FileProblem: Error, Sendable, Hashable {
    case notAFile
    /// It is larger than Peel reads a file of its kind.
    case tooLarge
    case failed(SystemError)
}
