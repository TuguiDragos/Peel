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
        result.trashed.map(\.originalURL).filter { isOne($0, root: root) }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    public static func isOne(_ url: URL, root: URL = URL(filePath: "/", directoryHint: .isDirectory)) -> Bool {
        guard url.pathExtension.caseInsensitiveCompare("driver") == .orderedSame else { return false }
        let library = root.appending(path: "Library", directoryHint: .isDirectory)
        let folder = library.appending(path: LibraryFolder.audioDrivers.rawValue, directoryHint: .isDirectory)
        return PathPattern.comparablePath(of: url.deletingLastPathComponent()) == PathPattern.comparablePath(of: folder)
    }
}
