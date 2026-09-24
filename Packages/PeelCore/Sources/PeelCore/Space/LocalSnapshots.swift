public import Foundation
internal import PeelPrivileged

/// A local snapshot: a copy of the whole disk as it was at one moment, kept on the disk itself. Time Machine
/// makes them, and macOS makes one before it updates. They are most of what macOS counts as purgeable space:
/// macOS deletes them by itself when it needs the room.
///
/// Deleting one is permanent, so Peel only explains them.
public struct LocalSnapshot: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case timeMachine
        case systemUpdate
        case other
    }

    public let name: String
    public let kind: Kind
    public let date: Date?
    /// False when macOS says it cannot reclaim this one, usually because it limits the minimum size of the
    /// disk's container. Nil when `diskutil` does not say.
    public let isPurgeable: Bool?

    public var id: String { name }
}

public enum LocalSnapshots {
    /// The start of a Time Machine snapshot's name, as in `com.apple.TimeMachine.2026-09-17-120000.local`.
    static let timeMachinePrefix = "com.apple.TimeMachine."
    static let systemUpdatePrefix = "com.apple.os.update-"

    /// The data volume, which is the one Time Machine snapshots. `/` is the sealed system volume: listing it
    /// finds only macOS's own update snapshot, not the user's, and `tmutil deletelocalsnapshots` cannot delete it.
    public static let volume = "/System/Volumes/Data"

    public static let deleteCommand = "tmutil deletelocalsnapshots \(volume)"

    @concurrent
    public static func list(volume: String = LocalSnapshots.volume) async -> [LocalSnapshot] {
        guard let output = await run(["apfs", "listSnapshots", volume]) else { return [] }
        return parse(output)
    }

    static func parse(_ output: String) -> [LocalSnapshot] {
        var snapshots: [LocalSnapshot] = []
        var name: String?
        var isPurgeable: Bool?

        func finish() {
            guard let name else { return }
            snapshots.append(LocalSnapshot(name: name, kind: kind(of: name), date: date(in: name), isPurgeable: isPurgeable))
        }

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("+--") {
                finish()
                name = nil
                isPurgeable = nil
            } else if let value = value(after: "Name:", in: trimmed) {
                name = value
            } else if let value = value(after: "Purgeable:", in: trimmed) {
                isPurgeable = value.lowercased() == "yes"
            }
        }
        finish()
        return snapshots
    }

    static func kind(of name: String) -> LocalSnapshot.Kind {
        if name.hasPrefix(timeMachinePrefix) { return .timeMachine }
        if name.hasPrefix(systemUpdatePrefix) { return .systemUpdate }
        return .other
    }

    /// The moment a Time Machine snapshot was taken, read from its name, such as
    /// `com.apple.TimeMachine.2026-09-17-120000.local`. Nil for a name in any other form.
    static func date(in name: String) -> Date? {
        guard name.hasPrefix(timeMachinePrefix) else { return nil }
        let stamp = name.dropFirst(timeMachinePrefix.count).prefix { $0 != "." }
        let parts = stamp.split(separator: "-")
        guard parts.count == 4, parts[3].count == 6,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let hour = Int(parts[3].prefix(2)), let minute = Int(parts[3].dropFirst(2).prefix(2)),
              let second = Int(parts[3].suffix(2))
        else { return nil }

        var components = DateComponents()
        (components.year, components.month, components.day) = (year, month, day)
        (components.hour, components.minute, components.second) = (hour, minute, second)
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func value(after label: String, in line: String) -> String? {
        guard line.hasPrefix(label) else { return nil }
        let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func run(_ arguments: [String]) async -> String? {
        guard case .success(let output) = await Subprocess.run("/usr/sbin/diskutil", arguments, timeout: 30), output.status == 0 else { return nil }
        return output.text
    }
}
