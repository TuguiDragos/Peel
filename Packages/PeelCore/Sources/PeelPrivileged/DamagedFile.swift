public import Foundation

/// Renames one of Peel's own files that cannot be read, so the next save does not overwrite it.
public enum DamagedFile {
    public static func setAside(_ url: URL) -> URL? {
        let folder = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let stamp = Date.now.formatted(stamp)
        var destination = folder.appending(path: "\(name)-damaged-\(stamp).\(ext)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            destination = folder.appending(path: "\(name)-damaged-\(stamp)-\(attempt).\(ext)")
            attempt += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// The files `setAside` made of `url`, or nil when their folder can't be listed. Only regular files named exactly
    /// as it names them count, so nothing else in the folder is taken for one.
    public static func copies(of url: URL) -> [URL]? {
        let folder = url.deletingLastPathComponent()
        let path = folder.path(percentEncoded: false)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            var info = stat()
            return lstat(path, &info) != 0 && errno == ENOENT ? [] : nil
        }
        let prefix = "\(url.deletingPathExtension().lastPathComponent)-damaged-"
        let suffix = ".\(url.pathExtension)"
        return names.filter { name in
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
            let stamp = name.dropFirst(prefix.count).dropLast(suffix.count)
            var info = stat()
            return stamp.wholeMatch(of: /[0-9]{4,}-[0-9]{2}-[0-9]{2}-[0-9]{6}(-[0-9]+)?/) != nil
                && lstat(folder.appending(path: name).path(percentEncoded: false), &info) == 0
                && info.st_mode & S_IFMT == S_IFREG
        }.map { folder.appending(path: $0) }
    }

    private static let stamp = Date.VerbatimFormatStyle(
        format: """
            \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)
            """,
        timeZone: .current,
        // The user's own calendar would put a Buddhist or Japanese year in the name.
        calendar: Calendar(identifier: .gregorian)
    )
}
