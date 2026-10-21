import AppKit
import CoreGraphics
@testable import Peel
import Testing

struct HostingTests {
    @Test func peelShowsNothingWhileItHostsThem() {
        #expect(PeelApp.isHostingTests)
        #expect(NSApp.activationPolicy() == .prohibited)
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = windows.filter {
            $0[kCGWindowOwnerPID as String] as? pid_t == ProcessInfo.processInfo.processIdentifier
        }
        #expect(own.isEmpty)
    }
}
