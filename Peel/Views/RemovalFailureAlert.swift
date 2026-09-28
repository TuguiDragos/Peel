import AppKit
import PeelCore
import SwiftUI

/// The alert every tool shows when a removal fails for some items: which ones, and why, with a button that
/// fixes the cause when there is one. It also reports the privacy resets worth telling about, since two
/// alerts cannot be up at once.
struct RemovalFailureAlert: ViewModifier {
    /// How many items the alert lists by path. The rest are only counted, to keep the alert short.
    static let mostListed = 4

    @Environment(RemovalOutcome.self) private var outcome
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresented) {
            if needsAppManagement {
                Button("Open System Settings") { NSWorkspace.shared.open(AppManagement.settingsURL) }
            }
            if needsHelper {
                Button("Open Peel Settings") { SettingsPane.helper.open(with: openSettings) }
            }
            if !outcome.failures.isEmpty {
                Button("Copy Details") { copyDetails() }
            }
            Button("OK", role: .cancel) {}
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
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty {
            return outcome.privacy.count == 1 ? Text("Privacy permissions weren’t reset.") : Text("Some privacy permissions weren’t reset.")
        }
        return outcome.movedCount == 0 ? Text("Nothing was moved to the Trash.") : Text("Some items couldn’t be moved to the Trash.")
    }

    private var message: String {
        var lines = quitLines + outcome.failures.prefix(Self.mostListed).map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }
        let rest = outcome.failures.count - lines.count
        if rest > 0 {
            lines.append(String(inflecting: "And ^[\(rest) more item](inflect: true)."))
        }
        lines += extraLines
        return lines.joined(separator: "\n\n")
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
        let lines = quitLines + outcome.failures.map { "\($0.url.path(percentEncoded: false))\n\($0.reason.explanation)" } + extraLines
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
            failure.reason == .notPermitted && failure.url.pathExtension.lowercased() == "app" && AppManagement.isRefusedForWantOfPermission(failure.url)
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
