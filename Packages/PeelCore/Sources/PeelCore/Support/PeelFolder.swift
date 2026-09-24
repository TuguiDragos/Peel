public import Foundation

/// Where Peel keeps what it writes: History and its record of refusals, the exclusions, the apps and teams it
/// has seen, Saved Settings, and the file digests Duplicates remembers.
public enum PeelFolder {
    public static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return support.appending(path: "Peel", directoryHint: .isDirectory)
    }
}
