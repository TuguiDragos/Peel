import Accessibility
import AppKit
import PeelCore
import SwiftUI

/// Starts one of Peel's files that can't be read over: VoiceOver hears `startedOver` once it did, and an alert says
/// when the old file couldn't be set aside, which leaves everything as it was.
struct StartOverButton: View {
    let file: URL
    let startedOver: LocalizedStringResource
    let startOver: () async -> StartOver
    @State private var couldNotSetAside = false

    var body: some View {
        Button("Start Over") {
            Task {
                switch await startOver() {
                case .started: AccessibilityNotification.Announcement(AttributedString(localized: startedOver)).post()
                case .couldNotSetAside: couldNotSetAside = true
                case .notNeeded: break
                }
            }
        }
        .alert("Peel couldn’t set the old file aside", isPresented: $couldNotSetAside) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing changed. Check that Peel can write to its folder in Application Support, then try again.")
        }
    }
}
