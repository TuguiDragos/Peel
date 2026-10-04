import AppKit
import os
import PeelCore
import QuartzCore
import SwiftUI

/// Counts hitches while `PEEL_MEASURE=<name>` is set: main thread turns longer than a frame, and missed frames.
/// Peel appends to `~/Library/Logs/Peel/<name>` (`MeasureFile`) how long after exec its first frame came, then a
/// report (`Hitches`) on every SIGUSR1 and when it quits. Long turns also go to the log as Points of Interest events.
/// It is in every build, not only Debug, because Release timings are the ones that count. Its display link wakes
/// Peel every frame, so leave it off when measuring idle CPU.
final class FrameWatch: NSObject {
    static let shared = ProcessInfo.processInfo.environment["PEEL_MEASURE"]
        .flatMap { MeasureFile(named: $0) }
        .map { FrameWatch(file: $0) }

    private let file: MeasureFile
    private var hitches = Hitches()
    private var busySince: CFTimeInterval?
    private var link: CADisplayLink?
    private var observer: CFRunLoopObserver?
    private var request: (any DispatchSourceSignal)?
    private var sight: (any NSObjectProtocol)?
    private var hasDrawn = false

    private init(file: MeasureFile) {
        self.file = file
    }

    /// Starts on a view in the window: that view's display link first fires when the window's first frame is due.
    fileprivate func start(on view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        // The display asks no frames for a window out of sight (minimized, hidden, or covered), which is no hitch.
        let window = view.window
        sight = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let window, !window.occlusionState.contains(.visible) else { return }
                self?.hitches.pause()
            }
        }
        guard observer == nil else { return }
        watchTheMainThread()
        reportWhenAsked()
    }

    fileprivate func stop() {
        link?.invalidate()
        link = nil
        sight.map(NotificationCenter.default.removeObserver)
        sight = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        if !hasDrawn {
            hasDrawn = true
            if let started = Self.processStart() {
                file.append([String(format: "first frame: %.1f ms after exec", (Date().timeIntervalSince1970 - started) * 1000)])
            }
        }
        hitches.frame(at: link.timestamp, due: link.targetTimestamp)
    }

    /// Times each turn of the main run loop, from waking up to going back to sleep.
    private func watchTheMainThread() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.turn(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    private func turn(_ activity: CFRunLoopActivity) {
        let now = CACurrentMediaTime()
        guard activity == .beforeWaiting else {
            busySince = now
            return
        }
        guard let busySince else { return }
        self.busySince = nil
        if hitches.turn(lasting: now - busySince) {
            Marks.moments.emitEvent("Long main thread turn", "\(Int((now - busySince) * 1000)) ms")
        }
    }

    /// Writes a report and starts a new stretch on each `kill -USR1 <pid>`, and writes one more when Peel quits. A
    /// script can send the signal before and after one action to measure only that action.
    private func reportWhenAsked() {
        // By default SIGUSR1 ends the process. A dispatch source doesn't change that (`dispatch_source_create(3)`).
        signal(SIGUSR1, SIG_IGN)
        let request = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        request.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.report() }
        }
        request.resume()
        self.request = request
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    private func report() {
        file.append(hitches.report)
        hitches = Hitches()
    }

    /// Returns when the kernel started this process, in seconds since 1970. Nothing the process times itself can be
    /// earlier, so the first frame is timed from the real start.
    private static func processStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
    }
}

extension View {
    /// Runs `FrameWatch` in the window this view is in, when `PEEL_MEASURE` is set.
    func measuresFrames() -> some View {
        background {
            if let watch = FrameWatch.shared {
                FrameWatchAnchor(watch: watch)
            }
        }
    }
}

private struct FrameWatchAnchor: NSViewRepresentable {
    let watch: FrameWatch

    func makeNSView(context: Context) -> Anchor {
        Anchor(watch: watch)
    }

    func updateNSView(_ nsView: Anchor, context: Context) {}

    final class Anchor: NSView {
        let watch: FrameWatch

        init(watch: FrameWatch) {
            self.watch = watch
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                watch.stop()
            } else {
                watch.start(on: self)
            }
        }
    }
}
