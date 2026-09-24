import SwiftUI

/// When busy work shows: not in its first 150 ms, and once shown, for at least 400 ms, so quick work never
/// flickers.
enum Busy {
    static let beforeShowing = Duration.milliseconds(150)
    static let leastVisible = Duration.milliseconds(400)
    /// How far a page fades while it is at work, whichever work it is.
    static let dimmed = 0.4
}

/// Passes `content` whether the busy state shows, following `isBusy` on the `Busy` timing.
struct BusyShown<Content: View>: View {
    let isBusy: Bool
    @ViewBuilder let content: (Bool) -> Content
    @State private var isShown = false
    @State private var shownAt: ContinuousClock.Instant?

    var body: some View {
        content(isShown)
            .task(id: isBusy) {
                if isBusy {
                    try? await Task.sleep(for: Busy.beforeShowing)
                    guard !Task.isCancelled, !isShown else { return }
                    shownAt = .now
                    isShown = true
                } else if let shownAt {
                    let visible = ContinuousClock.now - shownAt
                    if visible < Busy.leastVisible {
                        try? await Task.sleep(for: Busy.leastVisible - visible)
                    }
                    guard !Task.isCancelled else { return }
                    self.shownAt = nil
                    isShown = false
                }
            }
    }
}

extension View {
    /// Dims this and takes its clicks while `isBusy` holds, on the `Busy` timing. The removal bar refuses to move
    /// anything during a scan, so the first 150 ms need no lock.
    func dimmedWhileBusy(_ isBusy: Bool) -> some View {
        BusyShown(isBusy: isBusy) { isShown in
            self
                .opacity(isShown ? Busy.dimmed : 1)
                .disabled(isShown)
                .motion(value: isShown)
        }
    }
}
