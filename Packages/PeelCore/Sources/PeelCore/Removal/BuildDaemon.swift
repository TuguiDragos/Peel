import Foundation

/// A build tool's process that stays after a build to make the next one quicker and keeps the tool's caches open,
/// known by how the tool starts it, with the command the tool documents for stopping it.
public enum BuildDaemon: String, CaseIterable, Sendable {
    case gradle = "Gradle"
    case kotlin = "Kotlin"
    case bazel = "Bazel"
    case mavenDaemon = "mvnd"

    public var stop: String {
        switch self {
        // Gradle's "Gradle Daemon" page: `gradle --stop` stops the daemons of that version of Gradle.
        case .gradle: "gradle --stop"
        // Kotlin's "Compilation and caches in the Kotlin Gradle plugin": the daemon stops with Gradle's.
        case .kotlin: "gradle --stop"
        // Bazel's user manual, `shutdown`.
        case .bazel: "bazel shutdown"
        // mvnd's README, `--stop`.
        case .mavenDaemon: "mvnd --stop"
        }
    }

    /// The commands that stop the daemons of `tools`, each once.
    public static func stopCommands(for tools: [String]) -> [String] {
        var commands: [String] = []
        for command in tools.compactMap({ BuildDaemon(rawValue: $0)?.stop }) where !commands.contains(command) {
            commands.append(command)
        }
        return commands
    }

    /// The daemon a process started with `arguments` is: Gradle and Kotlin name their daemon's main class, mvnd gives
    /// each daemon an `mvnd.id`, and Bazel runs its server from `A-server.jar`.
    static func running(with arguments: [String]) -> BuildDaemon? {
        if arguments.contains("org.gradle.launcher.daemon.bootstrap.GradleDaemon") { return .gradle }
        if arguments.contains("org.jetbrains.kotlin.daemon.KotlinCompileDaemon") { return .kotlin }
        if arguments.contains(where: { $0.hasPrefix("-Dmvnd.id=") }) { return .mavenDaemon }
        let isBazelsServer = arguments.contains { argument in
            argument.split(separator: ":").first?.split(separator: "/").last == "A-server.jar"
        }
        return isBazelsServer ? .bazel : nil
    }
}
