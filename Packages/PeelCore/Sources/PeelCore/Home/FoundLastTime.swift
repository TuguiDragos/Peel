public import Foundation

/// What each tool found the last time it looked, kept so the menu bar panel can say it after Peel is opened again.
/// The app names the tools.
public struct FoundLastTime: Sendable, Equatable {
    public struct Finding: Sendable, Equatable {
        public let count: Int
        /// Nil for what has no size, such as updates.
        public let size: SizeTotal?
        public let date: Date

        public init(count: Int, size: SizeTotal?, date: Date) {
            self.count = count
            self.size = size
            self.date = date
        }
    }

    public private(set) var findings: [String: Finding] = [:]

    public init() {}

    /// Reads what `data` holds, leaving out an entry that makes no sense: any process can write an app's preferences.
    public init(data: Data?) {
        guard let data, let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        for (tool, entry) in entries {
            guard let stored = entry.stored, stored.count > 0, (stored.bytes ?? 0) >= 0 else { continue }
            let size = stored.bytes.map { SizeTotal(known: $0, isComplete: stored.complete ?? true) }
            findings[tool] = Finding(count: stored.count, size: size, date: stored.date)
        }
    }

    public var data: Data {
        let entries = findings.mapValues {
            Stored(count: $0.count, bytes: $0.size?.known, complete: $0.size?.isComplete, date: $0.date)
        }
        return (try? JSONEncoder().encode(entries)) ?? Data()
    }

    /// Records what `tool` found when it looked at `date`, and answers whether that changed anything: the panel says
    /// when in minutes, so the same finding within a minute is no change. Nothing found takes the tool off the list.
    @discardableResult
    public mutating func record(count: Int, size: SizeTotal?, for tool: String, at date: Date = .now) -> Bool {
        guard count > 0 else { return findings.removeValue(forKey: tool) != nil }
        if let last = findings[tool], last.count == count, last.size == size,
           abs(date.timeIntervalSince(last.date)) < 60 {
            return false
        }
        findings[tool] = Finding(count: count, size: size, date: date)
        return true
    }

    private struct Stored: Codable {
        let count: Int
        let bytes: Int64?
        let complete: Bool?
        let date: Date
    }

    /// One entry, read on its own, so one that cannot be read costs that entry only.
    private struct Entry: Decodable {
        let stored: Stored?

        init(from decoder: any Decoder) throws {
            stored = try? Stored(from: decoder)
        }
    }
}
