import Foundation
import Testing

struct PrivateDatabaseTests {
    /// What macOS records about privacy is not API, and from macOS 27 apps can't read it: App Management is learned
    /// from what a removal shows, on every macOS.
    @Test func noCodeReadsThePrivacyDatabase() throws {
        let name = "com.apple." + "TCC"
        let readers = try LineLengthTests.swiftFiles().filter {
            try String(contentsOf: $0, encoding: .utf8).contains(name)
        }
        #expect(readers.isEmpty, "\(readers.map(\.lastPathComponent))")
    }
}
