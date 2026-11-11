@testable import Peel
import PeelCore

extension HelperModel {
    /// A model of a helper that isn't installed, whose checks ask neither macOS nor the helper.
    static func notAsking() -> HelperModel {
        HelperModel(status: .notRegistered, reading: {
            Reading(status: .notRegistered, isAdministrator: true, isResponding: nil, isRegisteredByAnotherCopy: false)
        })
    }
}
