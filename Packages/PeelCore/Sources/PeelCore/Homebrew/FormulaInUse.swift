public import Foundation

/// What uses a formula about to be uninstalled. `brew uninstall` looks at neither (`uninstall.rb`): it deletes the
/// formula from under what runs from it, and leaves the job of `brew services` naming a program that is gone.
public struct FormulaInUse: Sendable, Hashable {
    /// The programs that run from the formula's folder or hold a file in it.
    public let programs: [String]
    /// What stops the job `brew services` keeps for the formula and takes its file away, to run in Terminal.
    public let stopCommand: String?
    /// What Homebrew keeps under the formula's name in its `var` and `etc`, which `brew uninstall` leaves: the data of
    /// a database, say, or a server's settings. Homebrew warns about its `etc` folder only once it is gone
    /// (`uninstall.rb`), and says nothing of `var`.
    public var dataFolders: [URL] = []

    public var isEmpty: Bool { programs.isEmpty && stopCommand == nil }

    @concurrent
    public static func of(formula name: String, cellar: URL) async -> FormulaInUse {
        of(
            formula: name, cellar: cellar, home: .homeDirectory, root: URL(filePath: "/", directoryHint: .isDirectory),
            brew: Homebrew.wordForTerminal
        )
    }

    static func of(formula name: String, cellar: URL, home: URL, root: URL, brew: String) -> FormulaInUse {
        func hasAJob(in library: URL, _ folder: String) -> Bool {
            !library.appending(path: "Library/\(folder)/homebrew.mxcl.\(name).plist").isMissing
        }
        // What `brew services start` writes, in the home's Library, or in the Mac's when it ran under `sudo`.
        let stop = "\(brew) services stop \(Homebrew.lastWord(naming: name))"
        let stopCommand =
            hasAJob(in: home, "LaunchAgents") ? stop : hasAJob(in: root, "LaunchDaemons") ? "sudo \(stop)" : nil
        let folder = cellar.appending(path: name, directoryHint: .isDirectory)
        let prefix = cellar.deletingLastPathComponent()
        return FormulaInUse(
            programs: OpenFiles().holders(of: folder),
            stopCommand: stopCommand,
            dataFolders: ["var", "etc"].map { prefix.appending(path: "\($0)/\(name)") }.filter { !$0.isMissing }
        )
    }
}
