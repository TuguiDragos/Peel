import Foundation
internal import PeelPrivileged

/// The years of TeX Live MacTeX installed, each whole in `/usr/local/texlive/<year>`, which installing a later year
/// leaves as they were. `/Library/TeX/Root` leads to the year in use (the TeX Users Group's MacTeX pages).
enum TeXLive {
    static func years(root: URL) -> [URL] {
        let folder = root.appending(path: "usr/local/texlive", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.count == 4 && $0.allSatisfy { $0.isASCII && $0.isNumber } }.sorted()
            .map { folder.appending(path: $0, directoryHint: .isDirectory) }.filter(\.isRealFolder)
    }

    /// The note on every year but the one `/Library/TeX/Root` leads to, and none while it leads to no year here.
    static func notes(on years: [URL]) -> [URL: SpaceItem.PlaceNote] {
        guard let first = years.first else { return [:] }
        let root = first.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let inUse = PathPattern.comparablePath(
            of: PathPattern.canonicalWithoutOpening(root.appending(path: "Library/TeX/Root"))
        )
        let real = years.map { PathPattern.comparablePath(of: PathPattern.canonicalWithoutOpening($0)) }
        guard real.contains(where: { PathComponents.isPath(inUse, atOrInside: $0) }) else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(years, real).filter {
            !PathComponents.isPath(inUse, atOrInside: $0.1)
        }.map { ($0.0, SpaceItem.PlaceNote.notTheTeXLiveInUse) })
    }
}

/// The versions of the .NET SDK installed side by side, each in a folder of its own, which Microsoft says can go once
/// a newer one is installed ("How to remove the .NET Runtime and SDK").
enum DotNetSDKs {
    /// Each version in the folders .NET installs SDKs in: the one for this Mac, the one for Intel on Apple silicon,
    /// and the one a manual install makes in the home folder.
    static func versions(home: URL, root: URL) -> [URL] {
        let dotnet = root.appending(path: "usr/local/share/dotnet", directoryHint: .isDirectory)
        let folders = [
            home.appending(path: ".dotnet/sdk", directoryHint: .isDirectory),
            dotnet.appending(path: "sdk", directoryHint: .isDirectory),
            dotnet.appending(path: "x64/sdk", directoryHint: .isDirectory),
        ]
        return folders.flatMap { folder in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            return names.filter(VersionComparison.isAVersion).sorted()
                .map { folder.appending(path: $0, directoryHint: .isDirectory) }.filter(\.isRealFolder)
        }
    }

    /// The note on every version with a newer one beside it in the same folder.
    static func notes(on versions: [URL]) -> [URL: SpaceItem.PlaceNote] {
        var notes: [URL: SpaceItem.PlaceNote] = [:]
        for folder in Dictionary(grouping: versions, by: { $0.deletingLastPathComponent() }).values {
            let names = folder.map(\.lastPathComponent)
            for version in folder where names.contains(where: {
                VersionComparison.isNewer($0, than: version.lastPathComponent)
            }) {
                notes[version] = .aNewerSDKIsInstalled
            }
        }
        return notes
    }
}
