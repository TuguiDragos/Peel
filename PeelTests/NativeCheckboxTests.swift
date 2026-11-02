import AppKit
@testable import Peel
import SwiftUI
import Testing

@Observable
private final class Choice {
    var isOn = false
    var isMixed = false
}

@MainActor
struct NativeCheckboxTests {
    private struct Row: View {
        let choice: Choice

        var body: some View {
            NativeCheckbox(
                isOn: Binding(get: { choice.isOn }, set: { choice.isOn = $0 }),
                label: "An item",
                isMixed: choice.isMixed
            )
        }
    }

    private func button(in view: NSView) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton ?? button(in: subview) { return button }
        }
        return nil
    }

    private func shown(_ choice: Choice) throws -> (NSWindow, NSButton) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let host = NSHostingView(rootView: Row(choice: choice))
        window.contentView = host
        window.layoutIfNeeded()
        return (window, try #require(button(in: host)))
    }

    private func settle(_ window: NSWindow, until isDone: () -> Bool) async {
        for _ in 0..<200 where !isDone() {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func theCheckmarkChangesOnceSwiftUIHasFinishedUpdating() async throws {
        let choice = Choice()
        let (window, button) = try shown(choice)
        var stacks: [[String]] = []
        let watch = try #require(button.cell).observe(\.state) { _, _ in
            MainActor.assumeIsolated { stacks.append(Thread.callStackSymbols) }
        }
        defer { watch.invalidate() }

        choice.isOn = true
        await settle(window) { button.state == .on }
        choice.isOn = false
        await settle(window) { button.state == .off }

        #expect(stacks.count == 2)
        #expect(!stacks.joined().contains { $0.contains("AttributeGraph") })
    }

    @Test func aStateWaitsForTheNextLayoutAndTheLastOneAskedForIsShown() {
        let host = NativeCheckbox.Host()
        host.show(.on)
        #expect(host.button.state == .off)
        host.show(.mixed)
        host.layout()
        #expect(host.button.state == .mixed)
        #expect(host.button.allowsMixedState)
    }

    @Test func aLayoutLeavesWhatAClickChangedAlone() {
        let host = NativeCheckbox.Host()
        host.show(.on)
        host.show(.off)
        host.button.state = .on
        host.layout()
        #expect(host.button.state == .on)
    }

    @Test func aNewCheckboxShowsItsStateFromTheStart() throws {
        let on = Choice()
        on.isOn = true
        #expect(try shown(on).1.state == .on)
        let mixed = Choice()
        mixed.isMixed = true
        let (_, button) = try shown(mixed)
        #expect(button.state == .mixed)
        #expect(button.allowsMixedState)
    }

    @Test func aMixedCheckboxLeavesTheMixedStateWhenItGoes() async throws {
        let choice = Choice()
        choice.isMixed = true
        let (window, button) = try shown(choice)
        choice.isMixed = false
        choice.isOn = true
        await settle(window) { button.state == .on }
        #expect(button.state == .on)
        #expect(!button.allowsMixedState)
    }
}
