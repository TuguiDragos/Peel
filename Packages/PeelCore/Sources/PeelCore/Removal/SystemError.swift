public import Foundation

/// An error macOS reported, kept by its domain and code rather than its words, which are in the language of the
/// process that met it: each reader words it again in its own.
public struct SystemError: Sendable, Hashable, Codable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    public init(_ error: any Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code)
    }

    /// What macOS says of this error for the item at `url`, in the language of the process asking.
    public func description(of url: URL) -> String {
        NSError(domain: domain, code: code, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
            .localizedDescription
    }
}
