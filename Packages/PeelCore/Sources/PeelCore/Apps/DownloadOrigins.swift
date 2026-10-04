public import Foundation
import SQLite3

/// Where an app was downloaded from, as macOS recorded it: the address a browser writes on the file itself
/// (`com.apple.metadata:kMDItemWhereFroms`), or else the download that the app's quarantine record points to in
/// Launch Services' quarantine database. An app copied out of a downloaded disk image carries such a record. The
/// database belongs to the user, is outside TCC, and is opened read-only. Only a web address is kept, and only up
/// to its path: a signed download link carries a token after it, and an inventory is meant to be read elsewhere.
public struct DownloadOrigins: Sendable {
    public static var onThisMac: DownloadOrigins {
        DownloadOrigins(events: URL.homeDirectory.appending(path: "Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"))
    }

    let events: URL

    init(events: URL) {
        self.events = events
    }

    /// A reader for one list of apps, which opens the quarantine database once for all of them.
    func reader() -> Reader {
        Reader(events: QuarantineEvents(at: events))
    }

    final class Reader {
        private let events: QuarantineEvents

        fileprivate init(events: QuarantineEvents) {
            self.events = events
        }

        func address(of bundle: URL) -> URL? {
            whereFrom(bundle) ?? quarantinedDownload(of: bundle)
        }

        /// The attribute is a binary property list of addresses: the file's own address, then the page it was on.
        private func whereFrom(_ bundle: URL) -> URL? {
            guard let data = DownloadOrigins.attribute("com.apple.metadata:kMDItemWhereFroms", of: bundle),
                  let addresses = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
            else { return nil }
            return addresses.lazy.compactMap(DownloadOrigins.shareable).first
        }

        /// The quarantine attribute reads `flags;time;agent;identifier`, and the identifier names the download's row.
        private func quarantinedDownload(of bundle: URL) -> URL? {
            guard let data = DownloadOrigins.attribute("com.apple.quarantine", of: bundle) else { return nil }
            let fields = String(decoding: data, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count >= 4, let identifier = UUID(uuidString: String(fields[3]))?.uuidString else {
                return nil
            }
            return events.addresses(of: identifier).lazy.compactMap(DownloadOrigins.shareable).first
        }
    }

    private static func shareable(_ address: String) -> URL? {
        guard var components = URLComponents(string: address), ["http", "https"].contains(components.scheme?.lowercased()),
              components.host?.isEmpty == false else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    private static func attribute(_ name: String, of url: URL) -> Data? {
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size <= 64 * 1_024 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read == size ? data : nil
    }
}

/// Launch Services' list of downloads, opened read-only at the first record looked up, and closed with this.
private final class QuarantineEvents {
    private let url: URL
    private var database: OpaquePointer?
    private var statement: OpaquePointer?
    private var hasOpened = false

    init(at url: URL) {
        self.url = url
    }

    deinit {
        sqlite3_finalize(statement)
        sqlite3_close(database)
    }

    /// The download's own address and the page it was on, as recorded for the event `identifier`.
    func addresses(of identifier: String) -> [String] {
        guard let statement = prepared() else { return [] }
        defer { sqlite3_reset(statement) }
        guard
            sqlite3_bind_text(statement, 1, identifier, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return [] }
        return [Int32(0), 1].compactMap { sqlite3_column_text(statement, $0).map { String(cString: $0) } }
    }

    private func prepared() -> OpaquePointer? {
        guard !hasOpened else { return statement }
        hasOpened = true
        let query = "SELECT LSQuarantineDataURLString, LSQuarantineOriginURLString FROM LSQuarantineEvent WHERE LSQuarantineEventIdentifier = ?"
        guard sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }
}
