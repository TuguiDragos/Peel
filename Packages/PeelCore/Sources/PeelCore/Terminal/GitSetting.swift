public import Foundation

public enum GitSetting: CaseIterable, Sendable {
    case rebaseOnPull
    case pushNewBranches
    case pruneOnFetch
    case stashBeforeRebase
    case histogramDiff
    case colorMovedLines
    case zdiff3Conflicts
    case reuseResolutions
    case mainBranch
    case branchesByDate
    case columns
    case signCommits

    public enum Group: CaseIterable, Sendable {
        case pullAndPush, diffsAndMerges, branches, signing
    }

    public struct Value: Equatable, Sendable {
        public let key: String
        public let value: String
    }

    public var group: Group {
        switch self {
        case .rebaseOnPull, .pushNewBranches, .pruneOnFetch, .stashBeforeRebase: .pullAndPush
        case .histogramDiff, .colorMovedLines, .zdiff3Conflicts, .reuseResolutions: .diffsAndMerges
        case .mainBranch, .branchesByDate, .columns: .branches
        case .signCommits: .signing
        }
    }

    /// The public key to sign commits with: the first default key `ssh-keygen` makes that is in `~/.ssh`.
    public static func signingKey(in home: URL) -> String? {
        ["id_ed25519.pub", "id_ecdsa.pub", "id_rsa.pub"]
            .map { home.appending(path: ".ssh/\($0)").path(percentEncoded: false) }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// What turning the setting on writes. Signing needs a public key, so without one it writes nothing.
    public func values(signingKey: String?) -> [Value] {
        switch self {
        case .rebaseOnPull: [Value(key: "pull.rebase", value: "true")]
        case .pushNewBranches: [Value(key: "push.autoSetupRemote", value: "true")]
        case .pruneOnFetch: [Value(key: "fetch.prune", value: "true")]
        case .stashBeforeRebase: [Value(key: "rebase.autoStash", value: "true")]
        case .histogramDiff: [Value(key: "diff.algorithm", value: "histogram")]
        case .colorMovedLines: [Value(key: "diff.colorMoved", value: "default")]
        case .zdiff3Conflicts: [Value(key: "merge.conflictStyle", value: "zdiff3")]
        case .reuseResolutions: [Value(key: "rerere.enabled", value: "true")]
        case .mainBranch: [Value(key: "init.defaultBranch", value: "main")]
        case .branchesByDate: [Value(key: "branch.sort", value: "-committerdate")]
        case .columns: [Value(key: "column.ui", value: "auto")]
        case .signCommits:
            signingKey.map {
                [
                    Value(key: "gpg.format", value: "ssh"),
                    Value(key: "user.signingKey", value: $0),
                    Value(key: "commit.gpgSign", value: "true"),
                ]
            } ?? []
        }
    }

    var keys: [String] {
        switch self {
        case .signCommits: ["gpg.format", "user.signingKey", "commit.gpgSign"]
        default: values(signingKey: nil).map(\.key)
        }
    }

    /// The keys that make the setting take effect, which turning it off removes when Peel did not write them.
    /// Signing keeps the format and the key the person chose for themselves, and stops only `commit.gpgSign`.
    var switchKeys: [String] {
        switch self {
        case .signCommits: ["commit.gpgSign"]
        default: values(signingKey: nil).map(\.key)
        }
    }

    public func isSetInIncludedFiles(_ includedKeys: Set<String>) -> Bool {
        keys.contains { includedKeys.contains($0.lowercased()) }
    }

    public func isKnown(by keys: Set<String>) -> Bool {
        self.keys.allSatisfy { keys.contains($0.lowercased()) }
    }

    /// Whether Git's global settings, keyed by their names in lowercase, have this setting in effect.
    public func isOn(in settings: [String: String?]) -> Bool {
        switch self {
        case .signCommits:
            Self.value(settings["gpg.format"]) == "ssh" && Self.isTrue(settings["commit.gpgsign"])
                && !(Self.value(settings["user.signingkey"]) ?? "").isEmpty
        default:
            values(signingKey: nil).allSatisfy { wanted in
                let found = settings[wanted.key.lowercased()]
                return wanted.value == "true"
                    ? Self.isTrue(found)
                    : Self.value(found)?.lowercased() == wanted.value.lowercased()
            }
        }
    }

    /// A key that is not there is nil, and a key written with no value is `.some(nil)`, which Git reads as true.
    private static func value(_ found: String??) -> String? {
        found.flatMap { $0 }
    }

    private static func isTrue(_ found: String??) -> Bool {
        switch found {
        case .none: false
        case .some(.none): true
        case .some(.some(let text)): ["true", "yes", "on", "1"].contains(text.lowercased())
        }
    }
}
