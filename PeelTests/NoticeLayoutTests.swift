import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
private final class Frames {
    var panel = CGRect.zero
    var buttons: [String: CGRect] = [:]
}

private extension View {
    func measured(into frames: Frames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("page")) } action: { frames.panel = $0 }
            .coordinateSpace(.named("page"))
    }
}

@MainActor
private func button(_ title: String, into frames: Frames) -> some View {
    Button(title) {}
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("page")) } action: { frames.buttons[title] = $0 }
}

@MainActor
private func laidOut(_ view: some View, width: CGFloat, frames: Frames, buttons: Int) async -> Frames {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
        backing: .buffered, defer: true
    )
    window.contentView = NSHostingView(rootView: view.frame(width: width))
    for _ in 0..<200 where frames.buttons.count < buttons || frames.panel.isEmpty {
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(5))
    }
    return frames
}

private let paragraph = "Peel couldn’t look inside /Library/Bluetooth, /Library/Trial and 16 more folders, so something "
    + "may be there that isn’t listed here. Give Peel Full Disk Access so it can read the folders macOS protects."

@MainActor
struct NoticeLayoutTests {
    private func notice(_ detail: String, width: CGFloat) async -> Frames {
        let frames = Frames()
        let view = Notice(title: Text(verbatim: "Some folders couldn’t be read"), detail: Text(verbatim: detail)) {
            button("Open System Settings", into: frames)
            button("Reopen Peel", into: frames)
        }
        .measured(into: frames)
        return await laidOut(view, width: width, frames: frames, buttons: 2)
    }

    @Test func inANarrowColumnTheButtonsShareOneLineAtTheRightEdge() async throws {
        let frames = await notice(
            "Peel couldn’t look inside /Library/Bluetooth and 16 more folders, so something may be there that isn’t listed.",
            width: 340
        )
        let settings = try #require(frames.buttons["Open System Settings"])
        let reopen = try #require(frames.buttons["Reopen Peel"])

        #expect(settings.minY == reopen.minY)
        #expect(settings.maxX < reopen.minX)
        #expect(abs(reopen.maxX - (frames.panel.maxX - 12)) < 1)
    }

    @Test func underALongTextTheButtonsStandBelowIt() async throws {
        let frames = await notice([paragraph, paragraph, paragraph].joined(separator: "\n\n"), width: 900)
        let settings = try #require(frames.buttons["Open System Settings"])
        let reopen = try #require(frames.buttons["Reopen Peel"])

        #expect(settings.minY == reopen.minY)
        #expect(abs(reopen.maxY - (frames.panel.maxY - 8)) < 1)
        #expect(abs(reopen.maxX - (frames.panel.maxX - 12)) < 1)
    }

    @Test func aShortNoticeKeepsItsButtonsBesideItsWords() async throws {
        let frames = await notice("Give Peel Full Disk Access.", width: 900)
        let reopen = try #require(frames.buttons["Reopen Peel"])

        #expect(reopen.height > frames.panel.height / 2)
        #expect(abs(reopen.maxX - (frames.panel.maxX - 12)) < 1)
    }

    @Test func aDetailWrapsBesideALongButtonRatherThanLeaveItALine() async throws {
        let frames = Frames()
        let view = Notice(
            title: Text(verbatim: "Peel couldn’t read your exclusions"),
            detail: Text(verbatim: "Peel removes nothing and puts nothing back until you start the list over in Settings.")
        ) {
            button("Open Peel Settings", into: frames)
        }
        .measured(into: frames)
        let open = try #require(await laidOut(view, width: 560, frames: frames, buttons: 1).buttons["Open Peel Settings"])

        #expect(abs(open.midY - frames.panel.midY) < 1)
        #expect(abs(open.maxX - (frames.panel.maxX - 12)) < 1)
    }
}

@MainActor
struct UpdatePanelLayoutTests {
    private func panel(_ detail: String, width: CGFloat) async -> Frames {
        let frames = Frames()
        let view = UpdatePanel(version: "2.0", notes: nil, link: nil) {
            Text(verbatim: detail)
        } action: {
            button("Open Tidewater", into: frames)
        }
        .measured(into: frames)
        return await laidOut(view, width: width, frames: frames, buttons: 1)
    }

    @Test func inANarrowColumnTheButtonStandsAtTheRightEdge() async throws {
        let frames = await panel("Tidewater updates itself. Open it and choose Check for Updates in its menu.", width: 340)
        let open = try #require(frames.buttons["Open Tidewater"])

        #expect(abs(open.maxX - (frames.panel.maxX - 12)) < 1)
    }

    @Test func homebrewsUpgradeKeepsItsButtonBesideItsWords() async throws {
        let frames = Frames()
        let view = UpdatePanel(version: "2.0", notes: nil, link: nil) {
            Text("Homebrew has it. Peel can run the upgrade for you.")
        } action: {
            Button(String(localized: AppPageHeader.homebrewUpgrade)) {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("page")) } action: {
                    frames.buttons["upgrade"] = $0
                }
        }
        .measured(into: frames)
        let upgrade = try #require(await laidOut(view, width: 500, frames: frames, buttons: 1).buttons["upgrade"])

        #expect(upgrade.minY < frames.panel.midY)
    }

    @Test func underALongTextTheButtonStandsBelowIt() async throws {
        let frames = await panel([paragraph, paragraph, paragraph].joined(separator: "\n\n"), width: 900)
        let open = try #require(frames.buttons["Open Tidewater"])

        #expect(abs(open.maxY - (frames.panel.maxY - 12)) < 1)
        #expect(abs(open.maxX - (frames.panel.maxX - 12)) < 1)
    }
}
