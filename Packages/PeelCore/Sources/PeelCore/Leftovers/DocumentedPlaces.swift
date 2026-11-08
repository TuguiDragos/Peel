import Foundation

/// Places in the home folder an app's maker documents as the app's, which the search can't tell are: one named for
/// neither the app nor its identifier, or one inside a folder every account starts with.
enum DocumentedPlaces {
    /// Each place for `app`, relative to the home folder, with a file inside that only that app writes, if any.
    static func of(_ app: InstalledApp) -> [(place: String, proof: String?)] {
        app.bundleIdentifier.flatMap { byApp[$0] } ?? []
    }

    private static let byApp: [String: [(place: String, proof: String?)]] = [
        // NoMachine's "How to move client connection files from one computer to another one": by default, the
        // connections and recordings go in Documents/NoMachine, and the favorites in .nx/config/player.cfg.
        "com.nomachine.nxdock": [(".nx", "config/player.cfg"), ("Documents/NoMachine", nil)],
    ]
}
