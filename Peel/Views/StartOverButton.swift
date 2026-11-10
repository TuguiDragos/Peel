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
    @State private var notSetAside: FileProblem?

    var body: some View {
        Button("Start Over") {
            Task {
                switch await startOver() {
                case .started: AccessibilityNotification.Announcement(AttributedString(localized: startedOver)).post()
                case .couldNotSetAside(let why): notSetAside = why
                case .notNeeded: break
                }
            }
        }
        .alert(
            "Peel couldn’t set the old file aside",
            isPresented: Binding(get: { notSetAside != nil }, set: { if !$0 { notSetAside = nil } })
        ) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("OK") {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(verbatim: notSetAside.said(after: String(localized: "Nothing changed."), about: file))
        }
    }
}
