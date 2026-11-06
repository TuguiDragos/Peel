import AppKit
import SwiftUI

/// Where Peel starts: Peel itself, or, for the PeelTests scheme, a host that only runs the tests, which only a
/// Debug build carries.
@main
enum Launch {
    static func main() {
        #if DEBUG
        if PeelApp.isHostingTests {
            TestHost.main()
            return
        }
        #endif
        PeelApp.main()
    }
}

#if DEBUG
/// The app the tests of Peel's models run in. It builds none of Peel's scenes, so nothing of Peel's starts or shows,
/// and AppKit records nothing under Peel's name, such as whether its menu bar item is hidden.
struct TestHost: App {
    @NSApplicationDelegateAdaptor(TestHostDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class TestHostDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
    }

    /// AppKit asks this with no window open, and the test runner ends the host once the tests are done.
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        false
    }
}
#endif
