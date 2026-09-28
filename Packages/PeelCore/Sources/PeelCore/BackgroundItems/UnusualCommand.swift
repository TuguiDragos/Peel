import Foundation
internal import PeelPrivileged

/// What in a job's command is worth a second look, read from the command's shape and never from a name. It claims
/// nothing about the job: software installed on purpose can do any of these.
public enum UnusualCommand: String, Sendable, Hashable {
    /// The program sits in a temporary folder, which any process on the Mac can write to.
    case runsFromATemporaryFolder
    /// The command downloads, with `curl` or `wget`.
    case downloads
    /// The command decodes base64, a way to carry a script that can't be read at a glance.
    case decodesBase64
    /// A shell or an interpreter runs code written into the job's own file, after `-c` or `-e`.
    case runsCodeFromItsSettings

    private static let temporaryFolders = ["/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp"]
    private static let downloaders: Set = ["curl", "wget"]
    private static let interpreters: Set = [
        "sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish",
        "python", "python3", "perl", "ruby", "node", "php", "osascript",
    ]

    /// `arguments` are the program and its arguments, as launchd runs them.
    init?(arguments: [String]) {
        guard let program = arguments.first else { return nil }
        let name = (program as NSString).lastPathComponent
        if Self.temporaryFolders.contains(where: { PathComponents.isPath(program, inside: $0) }) {
            self = .runsFromATemporaryFolder
        } else if Self.downloaders.contains(name) {
            self = .downloads
        } else if arguments.contains(where: { $0.contains("base64") }) {
            self = .decodesBase64
        } else if Self.interpreters.contains(name), arguments.dropFirst().contains(where: ["-c", "-e"].contains) {
            self = .runsCodeFromItsSettings
        } else {
            return nil
        }
    }
}
