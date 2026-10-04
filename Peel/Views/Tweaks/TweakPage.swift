import AppKit
import PeelCore
import SwiftUI

/// The Tweaks page, with a tab in the title bar for each group of tweaks, as in Settings.
struct TweakPage: View {
    @Environment(TweakLibrary.self) private var tweaks
    @State private var isConfirmingTurnAllOff = false

    /// The width the tabs need in the title bar. On macOS 26 the toolbar draws them as one segmented control
    /// with equal segments: the widest title plus 23.5 points, or plus 27 at either end. The toolbar shows the
    /// control only while the column is 24 points wider than it, and otherwise moves it into the overflow menu.
    /// `ContentView` moves the sidebar aside when the window is too narrow for both.
    static let tabBarWidth: CGFloat = {
        let titles = Tweak.Group.onTweaksPage.map { String(localized: $0.title) }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = titles.indices.map { index in
            let end = index == 0 || index == titles.count - 1
            return ceil((titles[index] as NSString).size(withAttributes: [.font: font]).width + (end ? 27 : 23.5))
        }.max() ?? 0
        return CGFloat(titles.count) * widest + 24
    }()

    var body: some View {
        TabView {
            ForEach(Tweak.Group.onTweaksPage, id: \.self) { group in
                // Made from a title and a symbol, as in `SettingsTabs`. With a `label:` closure, the toolbar
                // lays the tabs out differently and makes them wider than their titles need.
                Tab(group.title, systemImage: group.systemImage) {
                    TweakDetailContent(group: group)
                }
            }
        }
        .safeAreaBar(edge: .top) {
            Group {
                if tweaks.isSleepDisabled {
                    SleepNotice()
                        .padding(.horizontal, 30)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .motion(.settle, .movement, value: tweaks.isSleepDisabled)
        }
        // Shown once for every tab, at the foot of the page, rather than under each group's section.
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Turn All Off") {
                    isConfirmingTurnAllOff = true
                }
                .buttonStyle(.glass)
                .disabled(!tweaks.hasSomethingOn || tweaks.isTurningAllOff)
                Text("Each of these is a setting macOS already has. Turning one off puts back what was there before Peel, or leaves it to macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    // The English sentence is 642 points wide at this size, so a narrower frame would wrap it.
                    .frame(maxWidth: 680)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .alert("Turn off all tweaks?", isPresented: $isConfirmingTurnAllOff) {
            Button("Turn All Off") {
                Task { await tweaks.turnAllOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Settings Peel changed go back to how they were, and the rest go back to macOS’s defaults. Parts of macOS, like the Dock, may restart.")
        }
        .navigationTitle(Text(Tool.tweaks.title))
        .task {
            tweaks.refresh()
        }
        .onDisappear {
            tweaks.forgetRefusals()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tweaks.refresh()
        }
    }
}

private struct SleepNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This Mac can’t sleep")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text("Something has turned sleep off altogether, even with the lid closed. It survives a restart and System Settings doesn’t show it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(verbatim: SleepSetting.undoCommand)
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
                CopyButton(text: SleepSetting.undoCommand)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
