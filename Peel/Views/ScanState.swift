import PeelCore
import SwiftUI

/// What a tool's column shows: a scan in progress, a stopped scan, a message, or its content.
enum ScanPhase: Equatable {
    case scanning(ScanWork)
    /// The first scan was stopped, so nothing is listed and nothing is known about what is on the Mac.
    case stopped
    /// The tool's own message, shown in place of the list.
    case message
    case content
}

/// What a scan is doing, which sets the spinner's label: walking the disk, running a Spotlight query, or
/// updating Homebrew.
enum ScanWork: Equatable {
    case walk
    case spotlight
    case homebrewUpdate
}

extension View {
    /// Shows a column's scan state: dims the list while a rescan runs, and fades between the spinner, a message,
    /// and the list. Pass `fadesInResults: false` where a header or a search field stays on screen through the scan:
    /// the fade covers the whole column, and the list rebuilt under it takes the field's focus. `scan` provides the
    /// count of items read.
    func scanState(
        _ phase: ScanPhase,
        isRescanning: Bool = false,
        fadesInResults: Bool = true,
        scan: ScanRun? = nil,
        @ViewBuilder message: () -> some View
    ) -> some View {
        modifier(ScanStateModifier(phase: phase, isRescanning: isRescanning, fadesInResults: fadesInResults, scan: scan, message: message()))
    }

    /// The same, for a page with no message of its own.
    func scanState(_ phase: ScanPhase, isRescanning: Bool = false, fadesInResults: Bool = true, scan: ScanRun? = nil) -> some View {
        scanState(phase, isRescanning: isRescanning, fadesInResults: fadesInResults, scan: scan) { EmptyView() }
    }
}

private struct ScanStateModifier<Message: View>: ViewModifier {
    let phase: ScanPhase
    let isRescanning: Bool
    let fadesInResults: Bool
    let scan: ScanRun?
    let message: Message

    func body(content: Content) -> some View {
        content
            // Rebuilds the list when the first scan ends, under the fade that follows. Rows inserted all at once
            // into an empty `List` after a section header keep the table's default height and are never measured.
            .id(fadesInResults && isScanning)
            // Only the dim and the overlay are animated. The column's own layout, its search field included, changes
            // at once: a text field laid out under an animation gets a size SwiftUI reports as invalid every frame.
            .animation(Motion.step.animation) { $0.opacity(isRescanning ? Busy.dimmed : 1) }
            .overlay {
                Group {
                    switch phase {
                    case .scanning(let work):
                        ProgressView {
                            switch work {
                            case .walk: WalkLabel(scan: scan)
                            case .spotlight: Text("Searching…")
                            case .homebrewUpdate: Text("Updating Homebrew…")
                            }
                        }
                    case .stopped:
                        StoppedScan()
                    case .message:
                        message
                    case .content:
                        EmptyView()
                    }
                }
                .motion(.step, value: phase)
            }
            // SwiftUI doesn't fade in rows built in the update that shows them, so the whole column fades instead.
            .fadesInColumn(on: fadesInResults && isScanning)
    }

    private var isScanning: Bool {
        if case .scanning = phase { true } else { false }
    }
}

/// The spinner's label for a walk of the disk: how many items it has read or, while macOS asks the user about
/// other apps' data, that the scan waits for the answer.
private struct WalkLabel: View {
    @Environment(HomeModel.self) private var home
    let scan: ScanRun?

    var body: some View {
        if AppDataQuestion.isAsked(frontmost: FrontmostApp.shared.bundleIdentifier, hasFullDiskAccess: home.states[.fullDiskAccess] == .on) {
            Text("macOS is asking whether Peel may access data from other apps. The scan continues once you answer.")
        } else {
            ReadSoFar(scan: scan)
        }
    }
}

/// How many items a scan has read. It is a view of its own because the count changes ten times a second, and
/// only this view is redrawn for it. It shows nothing until an item is read, since the spinner already says a
/// scan is running.
struct ReadSoFar: View {
    let scan: ScanRun?

    var body: some View {
        if let read = scan?.itemsRead, read > 0 {
            Text("Looked at ^[\(read) item](inflect: true)")
                .monospacedDigit()
        }
    }
}

/// What a page shows when its first scan was stopped. Scan Again runs the toolbar's Rescan command, so the two
/// always do the same thing.
private struct StoppedScan: View {
    var body: some View {
        ContentUnavailableView {
            Label("Scan Stopped", systemImage: "xmark.circle")
        } description: {
            Text("Peel stopped before it had looked everywhere, so nothing is listed.")
        } actions: {
            let rescan = PageCommands.shared.rescan
            Button("Scan Again") { rescan?.perform() }
                .disabled(rescan?.isEnabled != true)
        }
    }
}
