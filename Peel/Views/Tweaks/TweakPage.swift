import AppKit
import PeelCore
import SwiftUI

/// The Tweaks page, with a tab in the title bar for each group of tweaks, as in Settings.
struct TweakPage: View {
    @Environment(TweakLibrary.self) private var tweaks
    @State private var isConfirmingTurnAllOff = false

    static let tabBarWidth = TabBar.width(of: Tweak.Group.onTweaksPage.map { String(localized: $0.title) })

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
        .edgeBar(.top) {
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
        .edgeBar(.bottom) {
            TurnAllOffBar(
                explanation: explanation, isEnabled: !tweaks.peelsChanges.isEmpty && !tweaks.isTurningAllOff
            ) {
                isConfirmingTurnAllOff = true
            }
        }
        .alert(Text(verbatim: question), isPresented: $isConfirmingTurnAllOff) {
            Button("Turn All Off") {
                Task { await tweaks.turnAllOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They go back to how they were before Peel, and what you set yourself stays as it is. Parts of macOS, like the Dock or Finder, may restart, which stops anything Finder is copying.")
        }
        .navigationTitle(Text(Tool.tweaks.title))
        .task {
            tweaks.refresh()
        }
        .onDisappear {
            tweaks.forgetNotices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tweaks.refresh()
        }
    }

    private var explanation: LocalizedStringResource {
        let count = tweaks.peelsChanges.count
        return count == 0
            ? "Each of these is a setting macOS already has, and Peel hasn’t changed any of them."
            : "Turn All Off puts back the ^[\(count) setting](inflect: true) Peel changed, and leaves what you set yourself as it is."
    }

    /// An alert's title shows inflection markup as written, so the count is inflected first.
    private var question: String {
        String(inflecting: "Put back the ^[\(tweaks.peelsChanges.count) setting](inflect: true) Peel changed?")
    }
}

private struct SleepNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusLabel(title: Text("This Mac can’t sleep"), tint: .accentColor)
                .font(.headline)
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
