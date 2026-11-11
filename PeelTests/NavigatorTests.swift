import Foundation
@testable import Peel
import Testing

@MainActor
struct NavigatorTests {
    @Test func aRequestFromOutsideWaitsUnderASheetAndWhileSomethingWaitsForAQuit() {
        let navigator = Navigator.shared
        let waiter = NSObject()

        #expect(navigator.mayApplyRequests(windowHasASheet: false))
        #expect(!navigator.mayApplyRequests(windowHasASheet: true))
        navigator.noteWaitingForAQuit(waiter, true)
        #expect(!navigator.mayApplyRequests(windowHasASheet: false))
        navigator.noteWaitingForAQuit(waiter, false)
        #expect(navigator.mayApplyRequests(windowHasASheet: false))
    }

    @Test func appsOpenedTogetherAreTakenTogether() {
        let navigator = Navigator.shared
        let editor = URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory)
        let viewer = URL(filePath: "/Applications/Viewer.app", directoryHint: .isDirectory)

        navigator.open(editor)
        navigator.open(viewer)

        #expect(navigator.takeOpenedApps() == [editor, viewer])
        #expect(navigator.takeOpenedApps().isEmpty)
    }
}
