import FoundationModels
import PeelCore

extension AppleIntelligence {
    /// Whether Apple Intelligence is turned on, as Foundation Models says: on too while its models are still coming.
    nonisolated static func isOn(_ availability: SystemLanguageModel.Availability) -> Bool {
        switch availability {
        case .available: true
        case .unavailable(let reason): reason == .modelNotReady
        }
    }

    /// Asks a system service, so it is read away from the main thread.
    @concurrent
    nonisolated static func isOnNow() async -> Bool {
        isOn(SystemLanguageModel.default.availability)
    }
}
