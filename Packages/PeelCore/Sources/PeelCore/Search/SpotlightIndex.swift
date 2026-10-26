import Foundation
internal import PeelPrivileged

/// Whether Spotlight indexes a disk: File Search finds only what Spotlight has indexed.
enum SpotlightIndex {
    /// A disk a search reads: the volume `mdutil` is asked about, and the name Finder shows for it.
    struct Disk: Sendable, Hashable {
        let volume: URL
        let name: String
    }

    /// What `mdutil -s` printed about a volume: indexed or not, or nil when it couldn't say.
    static func isIndexing(mdutil output: String) -> Bool? {
        if output.contains("Indexing enabled.") { return true }
        if output.contains("Indexing disabled.") || output.contains("Indexing and searching disabled") { return false }
        return nil
    }

    /// Asks `mdutil -s` whether Spotlight indexes the volume mounted at `volume`.
    @concurrent
    static func isIndexing(_ volume: URL) async -> Bool? {
        guard case .success(let output) = await Subprocess.run(
            "/usr/bin/mdutil", ["-s", volume.path(percentEncoded: false)], timeout: 5
        ) else { return nil }
        return isIndexing(mdutil: output.text)
    }

    /// The disks a search in `scope` reads: the one holding `home` and, for This Mac, every other local disk mounted.
    /// The startup disk is asked about through the volume that holds the person's files.
    static func disks(in scope: FileSearchCriteria.Scope, home: URL) -> [Disk] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeLocalizedNameKey]
        let homeVolume = (try? home.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? URL(filePath: "/")
        let others = scope == .home ? [] : (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []).filter { (try? $0.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == true }
        var seen = Set<String>()
        return ([homeVolume] + others).compactMap { volume in
            let isStartup = PathPattern.comparablePath(of: volume) == "/"
            let asked = isStartup ? URL(filePath: "/System/Volumes/Data", directoryHint: .isDirectory) : volume
            guard seen.insert(PathPattern.comparablePath(of: asked)).inserted else { return nil }
            let name = (try? volume.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
            return Disk(volume: asked, name: name ?? volume.lastPathComponent)
        }
    }
}
