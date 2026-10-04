import Foundation
import PeelPrivileged

extension URL {
    /// The path from `home` down to this item, or nil when the item is not inside `home`.
    func path(below home: URL) -> String? {
        let names = PathComponents.of(path(percentEncoded: false))
        let homeNames = PathComponents.of(home.path(percentEncoded: false))
        guard names.count > homeNames.count, names.starts(with: homeNames) else { return nil }
        return names.dropFirst(homeNames.count).joined(separator: "/")
    }
}
