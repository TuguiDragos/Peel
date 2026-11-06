public import Foundation

/// Where `PEEL_MEASURE` sends its reports: a file name in Peel's own logs folder, never a path. Whoever launches
/// Peel chooses the name, and Peel may hold rights its launcher lacks, such as Full Disk Access.
public struct MeasureFile: Sendable {
    public let url: URL
    private let home: URL
    private let name: String
    private static let folders = ["Library", "Logs", "Peel"]

    /// Nil for anything but a plain file name: a path, or a hidden name.
    public init?(named name: String, home: URL = .homeDirectory) {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        self.home = home
        self.name = name
        url = home.appending(path: Self.folders.joined(separator: "/"), directoryHint: .isDirectory)
            .appending(path: name)
    }

    /// Appends `lines`, making the folders and the file when needed, through descriptors from the home down, so
    /// nothing is made or written through a link put at any name on the way.
    public func append(_ lines: [String]) {
        var directory = open(home.path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { return }
        for folder in Self.folders {
            if mkdirat(directory, folder, 0o700) != 0, errno != EEXIST {
                close(directory)
                return
            }
            let next = openat(directory, folder, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(directory)
            guard next >= 0 else { return }
            directory = next
        }
        defer { close(directory) }
        let descriptor = openat(directory, name, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let data = Data(lines.map { $0 + "\n" }.joined().utf8)
        _ = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }
}
