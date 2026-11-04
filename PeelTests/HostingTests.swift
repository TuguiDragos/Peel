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
        // AppKit records whether a status item is hidden in Peel's own preferences, which the Mac's Peel reads.
        #expect(!NSApp.windows.contains { $0.className == "NSStatusBarWindow" })
    }

    @Test func theHostNeverQuitsByItself() {
        #expect(NSApp.delegate?.applicationShouldTerminateAfterLastWindowClosed?(NSApp) == false)
    }
}
