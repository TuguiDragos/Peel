import Foundation
@testable import Peel
import Testing

@MainActor
struct KernelExtensionNotesTests {
    @Test func saysOnAppleSiliconHowToSetTheStartupDisksSecurityBack() {
        let restart = String(localized: "macOS changes the kernel extensions it loads only when the Mac restarts, so restart once this one is in the Trash.")
        let security = String(localized: "If you set the startup disk’s security to Reduced Security to install it, it stays that way until you choose Full Security again: in the Recovery app, choose Utilities > Startup Security Utility.")

        #expect(KernelExtensionNotes.lines(onAppleSilicon: false) == [restart])
        #expect(KernelExtensionNotes.lines(onAppleSilicon: true) == [restart, security])
    }
}
