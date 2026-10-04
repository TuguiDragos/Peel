public import Foundation

/// Where `PEEL_MEASURE` sends its reports: a file name in Peel's own logs folder, never a path. Whoever launches
/// Peel chooses the name, and Peel may hold rights its launcher lacks, such as Full Disk Access.
public struct MeasureFile: Sendable {
    public let url: URL

    /// Nil for anything but a plain file name: a path, or a hidden name.
    public init?(named name: String, home: URL = .homeDirectory) {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        url = home.appending(path: "Library/Logs/Peel", directoryHint: .isDirectory).appending(path: name)
    }

    /// Appends `lines`, making the folder and the file when needed, and never through a link put at that name.
    public func append(_ lines: [String]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let data = Data(lines.map { $0 + "\n" }.joined().utf8)
        _ = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }
}
