import PeelCore
import SwiftUI

struct RescanButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isRunning: Bool
    var isDisabled = false
    var title: LocalizedStringResource = "Rescan"
    /// The page's scan. While it runs, the button turns into Stop, as Safari's Reload does. Nil where the work
    /// can't be stopped halfway, such as a Spotlight query or reading one file. Stop is not offered while the
    /// button is disabled: the scan after a move to the Trash takes the moved rows off the list, and stopping
    /// it would leave them listed.
    var scan: ScanRun?
    let action: () async -> Void

    /// Set as soon as the work starts, so the button can't be pressed twice. `isRunning` is what the button shows.
    @State private var isWorking = false
    @State private var shownAt: ContinuousClock.Instant?
    @State private var id = UUID()

    var body: some View {
        // On the shared busy timing, so a very short scan doesn't flash the button into Stop and back.
        BusyShown(isBusy: scan?.isRunning == true && !isDisabled) { isStoppable in
            if isStoppable, let scan {
                Button("Stop", systemImage: "xmark") { scan.stop() }
                    .help(Text("Stop the scan"))
            } else {
                Button(String(localized: title), systemImage: "arrow.clockwise") {
                    Task { await run() }
                }
                .symbolEffect(.rotate.clockwise, options: .repeat(.continuous), isActive: isRunning && !reduceMotion)
                .help(Text(title))
                .disabled(isWorking || isDisabled || scan?.isRunning == true)
            }
        }
        .onAppear(perform: offer)
        .onChange(of: isWorking) { offer() }
        .onChange(of: isDisabled) { offer() }
        .onChange(of: scan?.isRunning) { offer() }
        .onDisappear { PageCommands.shared.withdraw(from: id) }
    }

    private func offer() {
        let isScanning = scan?.isRunning == true
        PageCommands.shared.offer(
            rescan: MenuCommand(title: title, isEnabled: !isWorking && !isDisabled && !isScanning) {
                Task { await run() }
            },
            stop: scan.map { scan in MenuCommand(title: "Stop", isEnabled: isScanning && !isDisabled) { scan.stop() } },
            from: id
        )
    }

    /// Runs the action on the busy timing: the spinning symbol appears only after `Busy.beforeShowing`, and
    /// once shown it stays at least `Busy.leastVisible`. A scan that ends sooner never shows it, and frees the
    /// button (and Command-R) at once.
    private func run() async {
        isWorking = true
        let reveal = Task {
            try? await Task.sleep(for: Busy.beforeShowing)
            guard !Task.isCancelled else { return }
            shownAt = .now
            isRunning = true
        }
        await action()
        reveal.cancel()
        if let shownAt {
            let visible = ContinuousClock.now - shownAt
            if visible < Busy.leastVisible {
                try? await Task.sleep(for: Busy.leastVisible - visible)
            }
        }
        shownAt = nil
        isRunning = false
        isWorking = false
    }
}
