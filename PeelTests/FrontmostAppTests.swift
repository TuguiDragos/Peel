@testable import Peel
import Testing

@MainActor
struct FrontmostAppTests {
    @Test func remembersThatSystemSettingsWasInFront() {
        let frontmost = FrontmostApp(observing: false)

        frontmost.note("org.example.other")
        let before = frontmost.hasShownSystemSettings
        frontmost.note("com.apple.systempreferences")
        frontmost.note("org.example.other")

        #expect(!before)
        #expect(frontmost.hasShownSystemSettings)
        #expect(frontmost.bundleIdentifier == "org.example.other")
    }
}
