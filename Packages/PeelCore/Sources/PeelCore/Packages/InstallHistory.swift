import Foundation

/// The names macOS gives the packages it installed, from the history System Information shows under Installations.
enum InstallHistory {
    /// What an installer called itself, for each package it installed.
    struct Entry: Equatable {
        let name: String
        /// Nil where the history leaves it empty.
        let version: String?
    }

    /// The newest entry for each package identifier in `Library/Receipts/InstallHistory.plist` on `volume`.
    static func entries(onVolume volume: URL) -> [String: Entry] {
        let url = volume.appending(path: "Library/Receipts/InstallHistory.plist")
        guard let data = BoundedRead.data(at: url, maximum: 16 * 1_048_576),
              let entries = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]]
        else { return [:] }
        var newest: [String: (entry: Entry, date: Date)] = [:]
        for entry in entries {
            guard let name = entry["displayName"] as? String, !name.isEmpty,
                  let identifiers = entry["packageIdentifiers"] as? [String]
            else { continue }
            let date = entry["date"] as? Date ?? .distantPast
            let version = (entry["displayVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            for identifier in identifiers where date >= newest[identifier]?.date ?? .distantPast {
                newest[identifier] = (Entry(name: name, version: version), date)
            }
        }
        return newest.mapValues(\.entry)
    }
}
