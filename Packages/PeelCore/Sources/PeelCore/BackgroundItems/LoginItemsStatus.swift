import Foundation
import ServiceManagement

public enum LoginItemsStatus: Sendable, Hashable {
    case allowed
    /// Turned off by the person, or waiting for their approval (`SMAppService.h`).
    case turnedOff
    case notListedYet
    case notFound
    case unknown

    /// An answer Peel doesn't know is no leave to run the job.
    public var letsItRun: Bool {
        switch self {
        case .allowed, .notListedYet, .notFound: true
        case .turnedOff, .unknown: false
        }
    }

    /// Nil for a job with no file in a folder launchd reads by itself, the only ones macOS answers for.
    static func of(_ item: BackgroundItem) -> LoginItemsStatus? {
        guard let plist = item.plistURL, item.source == .userLibrary || item.source == .systemLibrary else {
            return nil
        }
        if let standIn { return standIn(plist) }
        return switch SMAppService.statusForLegacyPlist(at: plist) {
        case .enabled: .allowed
        case .requiresApproval: .turnedOff
        case .notRegistered: .notListedYet
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    /// For a test: no test can turn a job off in System Settings.
    @TaskLocal static var standIn: (@Sendable (URL) -> LoginItemsStatus)?
}
