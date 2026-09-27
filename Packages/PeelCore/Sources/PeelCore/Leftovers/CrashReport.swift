import Foundation

/// A report macOS writes in a `DiagnosticReports` folder when a process crashes, named for the process and the time.
/// Its first line is metadata whose `bundleID` is the bundle the report applies to (Apple's "Interpreting the JSON
/// format of a crash report"), which is what says whose it is.
enum CrashReport {
    /// A report can be megabytes, and only the metadata on its first line is read.
    private static let metadataLimit = 16 * 1_024

    /// True for an `.ips` file in a `DiagnosticReports` folder or in the `Retired` folder inside one.
    static func isOne(_ url: URL) -> Bool {
        guard url.pathExtension == "ips" else { return false }
        let folders = url.deletingLastPathComponent().pathComponents
        return folders.last == "DiagnosticReports" || folders.suffix(2) == ["DiagnosticReports", "Retired"]
    }

    static func bundleIdentifier(of url: URL) -> String? {
        guard isOne(url), let start = BoundedRead.prefix(of: url, count: metadataLimit) else { return nil }
        let line = start.prefix { $0 != UInt8(ascii: "\n") }
        let metadata = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        return metadata?["bundleID"] as? String
    }
}
