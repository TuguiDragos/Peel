public import Darwin
public import Foundation

/// The `brew` the person chose in Settings, for a Homebrew in a prefix of its own such as `/opt/brew`, which
/// Homebrew supports while the prefix is no longer than its default one. It is kept in the Peel folder, so the app
/// and `peel` run the same Homebrew, and it is never read from the environment: whatever could set a variable
/// would then choose which program Peel runs.
public struct HomebrewChoice: Sendable {
    public enum Refusal: Sendable, Equatable {
        case notBrew
        case notAProgram
        /// Another account could change what it runs.
        case ownedByAnotherAccount
        case writableByEveryone
    }

    public struct Unrunnable: Sendable, Equatable {
        public let brew: URL
        public let refusal: Refusal
    }

    public let url: URL

    public init(url: URL = HomebrewChoice.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        url(inHome: .homeDirectory)
    }

    static func url(inHome home: URL) -> URL {
        PeelFolder.url(inHome: home).appending(path: "homebrew.json")
    }

    /// The chosen `brew`, or nil when none was chosen. It stays chosen when it can no longer be run, so Peel runs
    /// no other one in its place.
    public func load() -> URL? {
        guard let data = BoundedRead.data(at: url), let path = try? JSONDecoder().decode(String?.self, from: data)
        else { return nil }
        return URL(filePath: path)
    }

    public func unrunnable() -> Unrunnable? {
        guard let brew = load(), let refusal = Self.refusal(of: brew) else { return nil }
        return Unrunnable(brew: brew, refusal: refusal)
    }

    /// Keeps `brew` as the one to run, or forgets the choice when it is nil. False when it could not be saved.
    @discardableResult
    public func save(_ brew: URL?) -> Bool {
        guard let data = try? JSONEncoder().encode(brew?.path(percentEncoded: false)) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Why `brew` cannot be the one Peel runs, or nil. A link is followed, since the file it leads to is what runs.
    public static func refusal(of brew: URL, user: uid_t = getuid()) -> Refusal? {
        guard brew.lastPathComponent == "brew" else { return .notBrew }
        let path = brew.path(percentEncoded: false)
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(path, X_OK) == 0 else {
            return .notAProgram
        }
        guard info.st_uid == user || info.st_uid == 0 else { return .ownedByAnotherAccount }
        return info.st_mode & S_IWOTH == 0 ? nil : .writableByEveryone
    }
}
