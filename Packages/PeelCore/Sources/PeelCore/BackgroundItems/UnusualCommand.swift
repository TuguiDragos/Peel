import Foundation
internal import PeelPrivileged

/// What in a job's command is worth a second look, read from the command's shape and never from a name. It claims
/// nothing about the job: software installed on purpose can do any of these.
public enum UnusualCommand: String, Sendable, Hashable {
    /// The program sits in a temporary folder: one any process on the Mac can write to, or an account's own.
    case runsFromATemporaryFolder
    /// The program sits in `/Users/Shared`, which every account on the Mac can write to.
    case runsFromTheSharedFolder
    /// The command downloads, with `curl` or `wget`.
    case downloads
    /// The command decodes base64, a way to carry a script that can't be read at a glance.
    case decodesBase64
    /// A shell or an interpreter runs code written into the job's own file, after `-c` or `-e`.
    case runsCodeFromItsSettings

    private static let temporaryFolders = ["/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp"]
    /// Where macOS keeps each account's folders, its temporary one being `<two names>/T` inside.
    private static let accountFolders = ["/var/folders", "/private/var/folders"]
    private static let decodingFlags: Set = ["-d", "-D", "--decode"]
    private static let downloaders: Set = ["curl", "wget"]
    private static let interpreters: Set = [
        "sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish",
        "python", "python3", "perl", "ruby", "node", "php", "osascript",
    ]

    /// `arguments` are the program and its arguments, as launchd runs them.
    init?(arguments: [String]) {
        guard let program = arguments.first else { return nil }
        let name = (program as NSString).lastPathComponent
        if Self.isTemporary(program) {
            self = .runsFromATemporaryFolder
        } else if PathComponents.isPath(program, inside: "/Users/Shared") {
            self = .runsFromTheSharedFolder
        } else if Self.downloaders.contains(name) {
            self = .downloads
        } else if Self.decodesBase64(arguments) {
            self = .decodesBase64
        } else if Self.interpreters.contains(name), arguments.dropFirst().contains(where: ["-c", "-e"].contains) {
            self = .runsCodeFromItsSettings
        } else {
            return nil
        }
    }

    private static func isTemporary(_ program: String) -> Bool {
        if temporaryFolders.contains(where: { PathComponents.isPath(program, inside: $0) }) { return true }
        return accountFolders.contains { folder in
            guard PathComponents.isPath(program, inside: folder) else { return false }
            let below = PathComponents.of(program).dropFirst(PathComponents.of(folder).count)
            return below.count > 3 && below.dropFirst(2).first == "T"
        }
    }

    /// Whether the command runs `base64` to decode: the program, as a word of any argument, and a decoding flag after
    /// it. A file or an option merely named so says nothing.
    private static func decodesBase64(_ arguments: [String]) -> Bool {
        let words = arguments.flatMap { $0.split { " \t\n|;&()".contains($0) }.map(String.init) }
        guard let index = words.firstIndex(where: { ($0 as NSString).lastPathComponent == "base64" }) else {
            return false
        }
        return words[(index + 1)...].contains(where: decodingFlags.contains)
    }
}
