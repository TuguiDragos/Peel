import Foundation

/// Places in the home folder an app's maker documents as the app's: ones the search can't tell are (named for neither
/// the app nor its identifier, or inside a folder every account starts with), and ones Orphaned Files lists once the
/// app has gone, where it looks for nothing by name.
enum DocumentedPlaces {
    struct Place: Sendable {
        /// Relative to the home folder.
        let place: String
        /// A file inside that only that app writes, if any.
        let proof: String?
        /// The command of the same tool that uses the place too, such as the `ollama` Homebrew installs.
        let command: String?
        /// A file inside that records another program of the maker using the place.
        let recordOfAnotherProgram: String?

        init(_ place: String, proof: String? = nil, command: String? = nil, recordOfAnotherProgram: String? = nil) {
            self.place = place
            self.proof = proof
            self.command = command
            self.recordOfAnotherProgram = recordOfAnotherProgram
        }

        /// Whether nothing else of the maker's uses the place in `home`: its command isn't installed, as far as `tools`
        /// knows, and no other program is recorded inside.
        func isLeftBehind(in home: URL, tools: InstalledTools) -> Bool {
            if let command {
                guard let formulae = tools.formulae, let commands = tools.commands,
                      !formulae.contains(command), !commands.contains(command)
                else { return false }
            }
            guard let recordOfAnotherProgram else { return true }
            return home.appending(path: place).appending(path: recordOfAnotherProgram).isMissing
        }
    }

    static func of(_ app: InstalledApp) -> [Place] {
        app.bundleIdentifier.map(of(identifier:)) ?? []
    }

    static func of(identifier: String) -> [Place] {
        byApp[identifier] ?? []
    }

    private static let byApp: [String: [Place]] = [
        // NoMachine's "How to move client connection files from one computer to another one": by default, the
        // connections and recordings go in Documents/NoMachine, and the favorites in .nx/config/player.cfg.
        "com.nomachine.nxdock": [Place(".nx", proof: "config/player.cfg"), Place("Documents/NoMachine")],
        // Ollama's `docs/macos.mdx`: `~/.ollama` holds the models and the settings, and uninstalling removes it.
        "com.electron.ollama": [Place(".ollama", command: "ollama")],
        // LM Studio's `findLMStudioHome`: its home is `~/.lmstudio`, where it records where its server without a
        // window is installed.
        "ai.elementlabs.lmstudio": [
            Place(".lmstudio", recordOfAnotherProgram: ".internal/llmster-install-location.json"),
        ],
        // Osaurus' `docs/STORAGE.md`: it keeps everything in `~/.osaurus`, and `DirectoryPickerService` its models
        // in `~/MLXModels`.
        "com.dinoki.osaurus": [Place(".osaurus"), Place("MLXModels")],
    ]
}
