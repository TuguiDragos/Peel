import Foundation

/// Renames one of Peel's own files that cannot be read, so the next save does not overwrite it.
enum DamagedFile {
    static func setAside(_ url: URL) -> URL? {
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
