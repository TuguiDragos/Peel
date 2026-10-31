public import Foundation
import PeelPrivileged
import Synchronization

/// Where Peel keeps what it writes: History and its record of refusals, the exclusions, the apps and teams it
/// has seen, Saved Settings, and the file digests Duplicates remembers.
public enum PeelFolder {
    public static var url: URL {
        url(inHome: .homeDirectory)
    }

    static func url(inHome home: URL) -> URL {
        home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
    }

    /// The folders Remove Peel has taken. Holding this lock across each write lets a write under way finish first.
    private static let taken = Mutex<[String]>([])

    /// Says that Remove Peel takes `folder` now. Nothing is written in it after this, since a scan that ends later
    /// would otherwise bring the folder back.
    static func take(_ folder: URL) {
        taken.withLock { $0.append(PathPattern.comparablePath(of: folder)) }
    }

    /// Makes `folder` and runs `write`, which puts something in it. Nil, doing neither, once `folder` has been taken.
    static func whileOpen<Answer: Sendable>(making folder: URL, _ write: () throws -> Answer) rethrows -> Answer? {
        try taken.withLock { taken in
            guard !taken.contains(where: {
                PathComponents.isPath(PathPattern.comparablePath(of: folder), atOrInside: $0)
            }) else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try write()
        }
    }

    /// Writes one of Peel's files whole: it goes to a temporary file that is then renamed, so a crash leaves either
    /// the old file or the new one.
    static func write(_ data: Data, to file: URL) throws {
        let wrote: Void? = try whileOpen(making: file.deletingLastPathComponent()) {
            try data.write(to: file, options: .atomic)
        }
        guard wrote != nil else { throw CocoaError(.fileWriteNoPermission) }
    }
}
