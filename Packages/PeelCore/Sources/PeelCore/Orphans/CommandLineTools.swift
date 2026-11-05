public import Foundation
internal import PeelPrivileged

/// The commands in the folders tools are put in by hand or by a package manager other than Homebrew: the tool folders
/// Intel Software reads (`IntelInspector.toolDirectories`) but `libexec`, whose helpers nobody runs by name.
public struct CommandLineTools: Sendable {
    public struct Command: Sendable, Hashable, Identifiable {
        public let name: String
        public let url: URL

        public var id: URL { url }
    }

    /// Every command's name, which keeps a group given to one out of Orphaned Files.
    public let names: Set<String>
    /// The commands a person may name as an owner: not one leading into an app, whose owner is the app, nor into
    /// Homebrew's Cellar, whose owner is the formula. By name, then by place.
    public let offered: [Command]

    /// Nil when a tool folder is there and can't be listed: then what is installed isn't known.
    public static func read(environment: SearchEnvironment = .current, cellar: URL?) -> CommandLineTools? {
        var unreadable: [URL] = []
        let tools = IntelInspector.tools(in: IntelInspector.commandDirectories(environment), unreadable: &unreadable)
        guard unreadable.isEmpty else { return nil }
        let cellarPath = cellar.map { PathPattern.comparablePath(of: $0) }
        let offered = tools.filter { tool in
            let program = PathPattern.comparablePath(of: tool.program)
            return !tool.program.pathComponents.contains { $0.hasSuffix(".app") }
                && !(cellarPath.map { PathComponents.isPath(program, atOrInside: $0) } ?? false)
        }
        return CommandLineTools(
            names: Set(tools.map(\.name)),
            offered: offered.map { Command(name: $0.name, url: $0.command) }.sorted {
                let names = $0.name.localizedStandardCompare($1.name)
                return names == .orderedSame
                    ? $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
                    : names == .orderedAscending
            }
        )
    }
}
