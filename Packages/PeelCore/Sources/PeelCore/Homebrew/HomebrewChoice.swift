public import Darwin
public import Foundation
import PeelPrivileged

/// The `brew` the person chose in Settings, for a Homebrew in a prefix of its own such as `/opt/brew`, which
/// Homebrew supports while the prefix is no longer than its default one. It is kept in the Peel folder, so the app
/// and `peel` run the same Homebrew, and it is never read from the environment: whatever could set a variable
/// would then choose which program Peel runs.
public struct HomebrewChoice: Sendable {
    public enum Refusal: Sendable, Equatable {
        case notBrew
        case notAProgram
        /// Another account, `owner` by its short name when it has one, could change what it runs.
        case ownedByAnotherAccount(owner: String?)
        case writableByEveryone
        /// The file that says which `brew` was chosen is there and can't be read.
        case unreadable
    }

    public struct Unrunnable: Sendable, Equatable {
        /// Nil when the choice itself can't be read.
        public let brew: URL?
        public let refusal: Refusal
    }

    public enum Reading: Sendable, Equatable {
        case nothingChosen
        case chosen(URL)
        case unreadable
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

    /// What the file says was chosen. A choice that can't be read, like one that can no longer be run, stays the
    /// choice, so Peel runs no other `brew` in its place.
    public func reading() -> Reading {
        guard !url.isMissing else { return .nothingChosen }
        guard let data = BoundedRead.data(at: url) else { return .unreadable }
        do {
            let path = try JSONDecoder().decode(String?.self, from: data)
            return path.map { .chosen(URL(filePath: $0)) } ?? .nothingChosen
        } catch {
            return .unreadable
        }
    }

    /// The chosen `brew`, or nil when none was chosen or the choice can't be read.
    public func load() -> URL? {
        if case .chosen(let brew) = reading() { brew } else { nil }
    }

    public func unrunnable() -> Unrunnable? {
        switch reading() {
        case .nothingChosen: nil
        case .unreadable: Unrunnable(brew: nil, refusal: .unreadable)
        case .chosen(let brew): Self.refusal(of: brew).map { Unrunnable(brew: brew, refusal: $0) }
        }
    }

    /// Keeps `brew` as the one to run, or forgets the choice when it is nil, and answers why it couldn't be saved, or
    /// nil once it is.
    @discardableResult
    public func save(_ brew: URL?) -> FileProblem? {
        do {
            if reading() == .unreadable {
                try DamagedFile.settingAside(url)
            }
            try PeelFolder.write(try JSONEncoder().encode(brew?.path(percentEncoded: false)), to: url)
            return nil
        } catch {
            return FileProblem(error)
        }
    }

    /// Why `brew` cannot be the one Peel runs, or nil. A link is followed, since the file it leads to is what runs.
    public static func refusal(of brew: URL, user: uid_t = getuid()) -> Refusal? {
        guard brew.lastPathComponent == "brew" else { return .notBrew }
        let path = brew.path(percentEncoded: false)
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(path, X_OK) == 0 else {
            return .notAProgram
        }
        guard info.st_uid == user || info.st_uid == 0 else {
            return .ownedByAnotherAccount(owner: AccountRecord.field(of: info.st_uid) { $0.pw_name })
        }
        return info.st_mode & S_IWOTH == 0 ? nil : .writableByEveryone
    }
}
