public import Foundation
internal import PeelPrivileged

/// What uninstalls left for an administrator: items only an administrator can move, from places the helper may not
/// move them from. Once their app is gone nothing else names them, so they are kept here for Orphaned Files.
public struct LeftForAnAdministrator: Sendable {
    /// One item an uninstall left, with the apps it was found for and the claim that found it.
    public struct Record: Sendable, Hashable, Codable {
        public struct App: Sendable, Hashable, Codable {
            /// The app's `InstalledApp.reference`.
            public let reference: String
            public let name: String
        }

        public let path: String
        public let kind: SearchLocation.Kind
        public let apps: [App]
        public let reason: MatchReason
        public let confidence: MatchConfidence

        /// The record of one item with a later one: the surer claim, or the later claim with both records' apps
        /// when they are as sure.
        func followed(by later: Record) -> Record {
            guard later.confidence == confidence else { return later.confidence > confidence ? later : self }
            let apps = apps + later.apps.filter { app in
                !apps.contains { $0.reference.lowercased() == app.reference.lowercased() }
            }
            return Record(path: later.path, kind: later.kind, apps: apps, reason: later.reason, confidence: confidence)
        }

        /// One record per item however its path is spelled, each from all of its records in their order.
        static func merged(_ records: [Record]) -> [ItemKey: Record] {
            Dictionary(records.map { (ItemKey(URL(filePath: $0.path)), $0) }, uniquingKeysWith: { $0.followed(by: $1) })
        }
    }

    public let url: URL

    public init(url: URL = LeftForAnAdministrator.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL { url(inHome: .homeDirectory) }

    static func url(inHome home: URL) -> URL {
        PeelFolder.url(inHome: home).appending(path: "left-for-an-administrator.json")
    }

    @concurrent
    public func load() async -> [Record] {
        // Taking the lock makes its file and folder, and a read must leave a home as it found it.
        guard !url.isMissing else { return [] }
        return FileLock.whileHeld(beside: url) { read() } ?? []
    }

    /// Adds `records`, each joined with the older ones of its item however its path is spelled, and forgets those
    /// whose item is gone. A file that can't be read is never written over.
    @concurrent
    public func record(_ records: [Record]) async {
        guard !records.isEmpty else { return }
        FileLock.whileHeld(beside: url) {
            guard let known = read() else { return }
            let all = known + records
            let merged = Record.merged(all)
            var written: Set<ItemKey> = []
            write(all.compactMap { record in
                let item = ItemKey(URL(filePath: record.path))
                guard written.insert(item).inserted, let record = merged[item] else { return nil }
                return URL(filePath: record.path).isMissing ? nil : record
            })
        }
    }

    /// Returns nil when the file can't be read or reached. A damaged file is first kept under another name, and only
    /// the records that can be read are kept, or nil when it can't be set aside.
    private func read() -> [Record]? {
        guard !url.isMissing else { return [] }
        guard let data = BoundedRead.data(at: url) else { return nil }
        let decoder = JSONDecoder()
        if let records = try? decoder.decode([Record].self, from: data) { return records }
        let readable = (try? decoder.decode([Row].self, from: data))?.compactMap(\.record) ?? []
        guard DamagedFile.setAside(url) != nil else { return nil }
        write(readable)
        return readable
    }

    /// One record of the file, decoded on its own. `record` is nil when the row is not a valid record.
    private struct Row: Decodable {
        let record: Record?

        init(from decoder: any Decoder) {
            record = try? Record(from: decoder)
        }
    }

    private func write(_ records: [Record]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

extension SearchLocation.Kind: Codable {}
extension MatchReason: Codable {}
extension MatchConfidence: Codable {}
