public import Foundation
internal import PeelPrivileged

/// The audio drivers a removal took from the folder macOS loads them from, a `.driver` bundle in
/// `/Library/Audio/Plug-Ins/HAL` (`AudioServerPlugIn.h`). The audio server keeps one it loaded until it starts again,
/// which a restart of the Mac does.
public enum AudioDrivers {
    public static func awaitingARestart(
        after result: TrashResult,
        root: URL = URL(filePath: "/", directoryHint: .isDirectory)
    ) -> [String] {
        let library = root.appending(path: "Library", directoryHint: .isDirectory)
        let folder = PathPattern.comparablePath(
            of: library.appending(path: LibraryFolder.audioDrivers.rawValue, directoryHint: .isDirectory)
        )
        return result.trashed.map(\.originalURL).filter { url in
            url.pathExtension.caseInsensitiveCompare("driver") == .orderedSame
                && PathPattern.comparablePath(of: url.deletingLastPathComponent()) == folder
        }.map { $0.deletingPathExtension().lastPathComponent }
    }
}
