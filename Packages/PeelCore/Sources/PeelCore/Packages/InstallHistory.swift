import Foundation

/// The names macOS gives the packages it installed, from the history System Information shows under Installations.
enum InstallHistory {
    /// The newest name for each package identifier in `Library/Receipts/InstallHistory.plist` on `volume`.
    static func names(onVolume volume: URL) -> [String: String] {
        let url = volume.appending(path: "Library/Receipts/InstallHistory.plist")
        guard let data = BoundedRead.data(at: url, maximum: 16 * 1_048_576),
              let entries = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]]
        else { return [:] }
        var newest: [String: (name: String, date: Date)] = [:]
        for entry in entries {
            guard let name = entry["displayName"] as? String, !name.isEmpty,
                  let identifiers = entry["packageIdentifiers"] as? [String]
            else { continue }
            let date = entry["date"] as? Date ?? .distantPast
            for identifier in identifiers where date >= newest[identifier]?.date ?? .distantPast {
                newest[identifier] = (name, date)
            }
        }
        return newest.mapValues(\.name)
    }
}
