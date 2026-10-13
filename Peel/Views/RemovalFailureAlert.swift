import AppKit
import PeelCore
import ServiceManagement
import SwiftUI

/// The alert every tool shows when a removal fails for some items: which ones, and why, with a button that
/// fixes the cause when there is one. It also reports the privacy resets worth telling about, the audio drivers that
/// wait for a restart, what stays for an administrator, and on macOS 27 the background items macOS still starts from
/// the Trash, since two alerts cannot be up at once.
struct RemovalFailureAlert: ViewModifier {
    /// How many items the alert lists by path. The rest are only counted, to keep the alert short.
    static let mostListed = 4

    @Environment(RemovalOutcome.self) private var outcome
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresented) {
            if needsAppManagement {
                Button("Open System Settings") { NSWorkspace.shared.open(AppManagement.settingsURL) }
            }
            if needsHelper {
                Button("Open Peel Settings") { SettingsPane.helper.open(with: openSettings) }
            }
            if #available(macOS 27, *), !outcome.appsStartingFromTheTrash.isEmpty {
                Button("Open Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
            }
            if outcome.leftForAnAdministrator > 0 {
                Button("Open Orphaned Files") {
                    orphans.selection = .forAnAdministrator
                    Navigator.shared.requestedTool = .orphans
                }
            }
            if !outcome.failures.isEmpty {
                Button("Copy Details") { copyDetails() }
            }
            // The alert reports, so Return closes it. Otherwise the first other button would be the default, and Return
            // would copy the details or open Settings.
            Button("OK", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(verbatim: message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { !outcome.isEmpty },
            set: { if !$0 { outcome.clear() } }
        )
    }

    private var title: Text {
        if #available(macOS 27, *), !outcome.appsStartingFromTheTrash.isEmpty, outcome.failures.isEmpty,
           outcome.appsToQuit.isEmpty, outcome.privacy.isEmpty {
            return outcome.driversAwaitingARestart.isEmpty
                ? Text("Empty the Trash to finish.")
                : Text("Restart your Mac and empty the Trash to finish.")
        }
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty, outcome.privacy.isEmpty,
           outcome.driversAwaitingARestart.isEmpty, outcome.leftForAnAdministrator > 0 {
            return Text("Some items stayed for an administrator.")
        }
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty, outcome.privacy.isEmpty {
            return Text("Restart your Mac to finish.")
        }
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty {
            return outcome.privacy.count == 1 ? Text("Privacy permissions weren’t reset.") : Text("Some privacy permissions weren’t reset.")
        }
        return outcome.movedCount == 0 ? Text("Nothing was moved to the Trash.") : Text("Some items couldn’t be moved to the Trash.")
    }

    private var message: String {
        let listed = outcome.failures.prefix(Self.mostListed)
        var lines = quitLines + listed.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }
        let rest = outcome.failures.count - listed.count
        if rest > 0 {
            lines.append(String(inflecting: "And ^[\(rest) more item](inflect: true)."))
        }
        lines += keptLines + driverLines + administratorLines + extraLines
        if #available(macOS 27, *) {
            lines += trashLines
        }
        return lines.joined(separator: "\n\n")
    }

    private var administratorLines: [String] {
        let count = outcome.leftForAnAdministrator
        guard count > 0 else { return [] }
        return count == 1
            ? [String(localized: "One item stayed because only an administrator can move it, and Peel’s helper isn’t allowed to. Orphaned Files lists it under Needs an Administrator, with how to remove it.")]
            : [String(inflecting: "^[\(count) item](inflect: true) stayed because only an administrator can move them, and Peel’s helper isn’t allowed to. Orphaned Files lists them under Needs an Administrator, with how to remove them.")]
    }

    private var driverLines: [String] {
        let drivers = outcome.driversAwaitingARestart
        guard !drivers.isEmpty else { return [] }
        let names = drivers.formatted(.list(type: .and))
        return drivers.count == 1
            ? [String(localized: "macOS keeps the audio driver \(names) running until you restart your Mac.")]
            : [String(localized: "macOS keeps the audio drivers \(names) running until you restart your Mac.")]
    }

    /// One line for the apps whose background items macOS still starts from the Trash at each login.
    private var trashLines: [String] {
        let apps = outcome.appsStartingFromTheTrash
        guard !apps.isEmpty else { return [] }
        let names = apps.formatted(.list(type: .and))
        return [String(localized: "macOS still starts the background items of \(names) from the Trash each time you log in, until you empty the Trash.")]
    }

    /// A line for each app that stayed, since its files, which wait for it, stayed too and are not listed.
    private var keptLines: [String] {
        outcome.keptTheirFiles.map { String(localized: "\($0) stayed, and so did its files.") }
    }

    private var extraLines: [String] {
        var lines: [String] = []
        if needsAppManagement {
            lines.append(String(localized: "If Peel isn’t allowed under App Management, macOS won’t let it move another developer’s app to the Trash."))
        }
        lines += privacyLines
        return lines
    }

    /// Copies every item with its full path, since the alert lists only the first few and its text can't be
    /// selected.
    private func copyDetails() {
        var lines = quitLines + outcome.failures.map { "\($0.url.path(percentEncoded: false))\n\($0.reason.explanation)" }
            + keptLines + driverLines + administratorLines + extraLines
        if #available(macOS 27, *) {
            lines += trashLines
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n\n"), forType: .string)
    }

    /// A line for each app whose tool kept what was selected for it, since the app was open.
    private var quitLines: [String] {
        outcome.appsToQuit.map { String(localized: "Quit \($0) before removing its files.") }
    }

    /// One line per privacy reset. When a single failed reset is all there is to report, the title already
    /// says so, and the line gives only the reason.
    private var privacyLines: [String] {
        outcome.privacy.map { privacy in
            guard let problem = privacy.result.explanation else {
                return String(localized: "\(privacy.app)’s privacy permissions were reset before the move.")
            }
            return outcome.failures.isEmpty && outcome.privacy.count == 1
                ? problem
                : String(localized: "\(privacy.app)’s privacy permissions weren’t reset. \(problem)")
        }
    }

    /// True when macOS refused to move an app although the user can write to its folder and nothing locks it.
    /// That refusal comes from App Management, which the user can allow in System Settings.
    private var needsAppManagement: Bool {
        outcome.failures.contains { failure in
            failure.reason == .notPermitted && failure.url.pathExtension.lowercased() == "app"
                && AppManagement.isRefusedForWantOfPermission(failure.url)
        }
    }

    private var needsHelper: Bool {
        outcome.failures.contains { $0.reason == .needsHelper }
    }
}

extension View {
    func removalFailureAlert() -> some View {
        modifier(RemovalFailureAlert())
    }
}
