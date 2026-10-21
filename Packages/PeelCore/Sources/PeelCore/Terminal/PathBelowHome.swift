import Foundation
import PeelPrivileged

extension URL {
    /// The path from `home` down to this item, or nil when the item is not inside `home`.
    func path(below home: URL) -> String? {
        let names = PathComponents.of(path(percentEncoded: false))
        let homeNames = PathComponents.of(home.path(percentEncoded: false))
        guard names.count > homeNames.count, names.starts(with: homeNames) else { return nil }
        return names.dropFirst(homeNames.count).joined(separator: "/")
    }

    /// The path as a command in Terminal takes it: from `~` when it is in the home folder and needs no quoting,
    /// and otherwise whole, in single quotes.
    func pathForTheShell(home: URL) -> String {
        let plain: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || "._/-".contains($0)) }
        if let below = path(below: home), below.allSatisfy(plain) {
            return "~/" + below
        }
        return path(percentEncoded: false).quotedForTheShell
    }
}

extension String {
    /// The text in single quotes, as the shell reads it back unchanged.
    var quotedForTheShell: String {
        "'" + replacing("'", with: "'\\''") + "'"
    }
}

enum ShellCommand {
    /// The command that adds `lines` at the end of `file`, each on a line of its own, and makes the file when it is
    /// not there. An empty line goes first: a file whose last line has no newline after it would otherwise run into
    /// the first of `lines`, and the shell would read the two as one.
    static func appending(_ lines: [String], to file: URL, home: URL) -> String {
        let arguments = ([""] + lines).map(\.quotedForTheShell).joined(separator: " ")
        return "printf '%s\\n' \(arguments) >> \(file.pathForTheShell(home: home))"
    }
}
