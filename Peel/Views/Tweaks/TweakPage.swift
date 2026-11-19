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
                explanation: Self.explanation(changed: tweaks.peelsChanges.count),
                hasSomethingOn: !tweaks.peelsChanges.isEmpty,
                isEnabled: !tweaks.isTurningAllOff
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
            if #available(macOS 27, *) {
                Text("They go back to how they were before Peel, and what you set yourself stays as it is. Parts of macOS, like the Dock or Finder, may restart.")
            } else {
                Text("They go back to how they were before Peel, and what you set yourself stays as it is. Parts of macOS, like the Dock or Finder, may restart, which stops anything Finder is copying.")
            }
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

    static func explanation(changed count: Int) -> LocalizedStringResource {
        "Peel changed ^[\(count) setting](inflect: true)."
    }

    /// An alert's title shows inflection markup as written, so the count is inflected first.
    private var question: String {
        String(inflecting: "Put back the ^[\(tweaks.peelsChanges.count) setting](inflect: true) Peel changed?")
    }
}

struct SleepNotice: View {
    @Environment(HelperModel.self) private var helper

    /// What to do with the command, said above it. An account that isn't an administrator's reads who runs it below.
    static func howToUndo(needsAnAdministrator: Bool) -> LocalizedStringResource {
        needsAnAdministrator
            ? "To let it sleep again, run this command in Terminal."
            : "To let it sleep again, run this command in Terminal. It asks for your password."
    }

    static let whyItCannotSleep: LocalizedStringResource =
        "Something turned sleep off, even with the lid closed. It stays after a restart, and System Settings does not show it."

    var body: some View {
        let needsAnAdministrator = AdministratorCommand.needsAnAdministrator(
            SleepSetting.undoCommand, isAdministrator: helper.isAdministrator
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                StatusLabel(title: Text("This Mac can’t sleep"), tint: .accentColor)
                    .font(.headline)
                InfoNote(about: Text("This Mac can’t sleep"), detail: Text(Self.whyItCannotSleep), isAlbum: false)
            }
            Text(Self.howToUndo(needsAnAdministrator: needsAnAdministrator))
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
            if needsAnAdministrator {
                AdministratorCommand.note
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
