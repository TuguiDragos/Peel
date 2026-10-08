public import Foundation

/// Where Peel keeps what it writes: History and its record of refusals, the exclusions, the apps and teams it
/// has seen, Saved Settings, and the file digests Duplicates remembers.
public enum PeelFolder {
    public static var url: URL {
        url(inHome: .homeDirectory)
    }

    static func url(inHome home: URL) -> URL {
        home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
    }
}
