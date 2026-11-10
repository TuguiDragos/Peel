import PeelPrivileged

extension SystemFolders {
    /// Whether macOS keeps an item called `fileName` for its own services in a folder of `kind`. A process keeps its
    /// caches, its HTTP storage and its temporary items under the same name.
    static func keeps(_ fileName: String, in kind: SearchLocation.Kind) -> Bool {
        let list: List? = switch kind {
        case .applicationSupport: .applicationSupport
        case .caches, .httpStorages, .temporaryItems: .caches
        case .logs: .logs
        case .preferences: .preferences
        case .webKit: .webKit
        case .cookies: .cookies
        case .library: .library
        default: nil
        }
        return list.map { holds(fileName, in: $0) } ?? false
    }
}
