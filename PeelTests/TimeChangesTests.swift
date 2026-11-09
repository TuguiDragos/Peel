import AppKit
@testable import Peel
import Testing

@MainActor
struct TimeChangesTests {
    @Test func countsEachJumpOfTheTimeThatAScheduleKnowsNothingOf() {
        let center = NotificationCenter(), workspace = NotificationCenter()
        let changes = TimeChanges(center: center, workspace: workspace)
        center.post(name: .NSCalendarDayChanged, object: nil)
        #expect(changes.revision == 1)
        center.post(name: .NSSystemClockDidChange, object: nil)
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(changes.revision == 4)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(changes.revision == 4)
    }
}
