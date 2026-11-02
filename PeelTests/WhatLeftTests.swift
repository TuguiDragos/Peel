import AppKit
@testable import Peel
import PeelCore
import SwiftUI
import Testing

@MainActor
struct WhatLeftTests {
    private final class Looks {
        var count = 0
    }

    private func settle(_ host: NSView, until isDone: () -> Bool) async {
        for _ in 0..<200 where !isDone() {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aPageLooksForWhatLeftWhenItAppearsAndWhenPeelComesForward() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
        let looks = Looks()
        let host = NSHostingView(rootView: Color.clear.leavesOutWhatLeft { looks.count += 1 }.environment(history))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered,
            defer: true
        )
        window.contentView = host
        await settle(host) { looks.count == 1 }
        #expect(looks.count == 1)

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        await settle(host) { looks.count == 2 }

        #expect(looks.count == 2)
    }
}
