import Darwin
@testable import PeelCore
import Testing

/// What a test of this Mac's own state needs, so a Mac without it reports the test skipped, never passed.
extension Trait where Self == ConditionTrait {
    static var homebrewOnThisMac: Self {
        .enabled("Homebrew is on this Mac") { Homebrew.executableURL != nil }
    }

    static var homebrewWithItsDefinitions: Self {
        .enabled("Homebrew is on this Mac with its own copy of its definitions") {
            guard Homebrew.executableURL != nil else { return false }
            return await Homebrew.hasLocalDefinitions()
        }
    }

    static var anotherAccountRunsAnApp: Self {
        .enabled("Another account or the system runs an app on this Mac") {
            await MainActor.run {
                RunningCopies.current.contains { kill($0.identifier, 0) != 0 && errno == EPERM && $0.bundleURL != nil }
            }
        }
    }
}
