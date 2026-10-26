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

    /// The first entries of a list, as many as an alert lists, and then how many items the others are.
    static func firstItems(_ entries: [String]) -> [String] {
        guard entries.count > mostListed else { return entries }
        return entries.prefix(mostListed) + [String(inflecting: "And ^[\(entries.count - mostListed) more item](inflect: true).")]
    }

    /// The first lines of a list of apps, as many as an alert lists, and then how many apps the others are.
    static func shortened(_ lines: [String]) -> [String] {
        guard lines.count > mostListed else { return lines }
        return lines.prefix(mostListed) + [String(inflecting: "And ^[\(lines.count - mostListed) more app](inflect: true).")]
    }

    /// Apps named in one sentence: the first ones, as many as an alert lists, and then how many the others are.
    static func listed(_ names: [String]) -> String {
        listed(names) { String(inflecting: "^[\($0) more app](inflect: true)") }
    }

    private static func listed(_ names: [String], others: (Int) -> String) -> String {
        guard names.count > mostListed else { return names.formatted(.list(type: .and)) }
        return (names.prefix(mostListed) + [others(names.count - mostListed)]).formatted(.list(type: .and))
    }

    @Environment(RemovalOutcome.self) private var outcome
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresented) {
            if Self.needsAppManagement(outcome) {
                Button("Open System Settings") { NSWorkspace.shared.open(AppManagement.settingsURL) }
            }
            if Self.needsHelper(outcome) {
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
            if Self.offersDetails(for: outcome) {
                Button("Copy Details") { Self.copyDetails(of: outcome) }
            }
            // The alert reports, so Return closes it. Otherwise the first other button would be the default, and Return
            // would copy the details or open Settings.
            Button("OK", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(verbatim: Self.message(for: outcome))
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { !outcome.isEmpty },
            set: { if !$0 { outcome.clear() } }
        )
    }

    private var title: Text {
        if outcome.historyCouldNotRecord {
            return Text("History couldn’t record this removal.")
        }
        if !outcome.putBackFailures.isEmpty, outcome.failures.isEmpty {
            return Text("Some items couldn’t be put back.")
        }
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
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty, outcome.privacy.isEmpty,
           outcome.driversAwaitingARestart.isEmpty, outcome.appsStartingFromTheTrash.isEmpty,
           !outcome.shellReferences.isEmpty {
            return Text("Your shell files still name what moved.")
        }
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty, outcome.privacy.isEmpty {
            return Text("Restart your Mac to finish.")
        }
        if outcome.failures.isEmpty, outcome.appsToQuit.isEmpty {
            return outcome.privacy.count == 1 ? Text("Privacy permissions weren’t reset.") : Text("Some privacy permissions weren’t reset.")
        }
        return outcome.movedCount == 0 ? Text("Nothing was moved to the Trash.") : Text("Some items couldn’t be moved to the Trash.")
    }

    static func message(for outcome: RemovalOutcome) -> String {
        var lines = historyLines(outcome)
            + firstItems(outcome.putBackFailures.map { "\($0.url.abbreviatedPath)\n\($0.failure.explanation)" })
            + shortened(quitLines(outcome))
            + firstItems(outcome.failures.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" })
        lines += shortened(keptLines(outcome)) + driverLines(outcome) + administratorLines(outcome)
            + shellLines(outcome) { Self.listed($0) { String(inflecting: "^[\($0) more line](inflect: true)") } }
            + appManagementLines(outcome) + shortened(privacyLines(outcome))
        if #available(macOS 27, *) {
            lines += trashLines(outcome, naming: Self.listed)
        }
        return lines.joined(separator: "\n\n")
    }

    private static func historyLines(_ outcome: RemovalOutcome) -> [String] {
        guard outcome.historyCouldNotRecord else { return [] }
        return [String(localized: "What moved is in the Trash: drag it back out in Finder if you need it.")]
    }

    private static func administratorLines(_ outcome: RemovalOutcome) -> [String] {
        let count = outcome.leftForAnAdministrator
        guard count > 0 else { return [] }
        return count == 1
            ? [String(localized: "One item stayed because only an administrator can move it, and Peel’s helper isn’t allowed to. Orphaned Files lists it under Needs an Administrator, with how to remove it.")]
            : [String(inflecting: "^[\(count) item](inflect: true) stayed because only an administrator can move them, and Peel’s helper isn’t allowed to. Orphaned Files lists them under Needs an Administrator, with how to remove them.")]
    }

    /// One line for the shell startup files that still name what moved: the person edits them, Peel never does.
    private static func shellLines(_ outcome: RemovalOutcome, naming: ([String]) -> String) -> [String] {
        let references = outcome.shellReferences
        guard !references.isEmpty else { return [] }
        let places = references.map { String(localized: "\($0.file.abbreviatedPath), line \($0.line)") }
        return [String(localized: "Your shell startup files still name what moved, at \(naming(places)). Peel reads these files and never changes them.")]
    }

    private static func driverLines(_ outcome: RemovalOutcome) -> [String] {
        let drivers = outcome.driversAwaitingARestart
        guard !drivers.isEmpty else { return [] }
        let names = drivers.formatted(.list(type: .and))
        return drivers.count == 1
            ? [String(localized: "macOS keeps the audio driver \(names) running until you restart your Mac.")]
            : [String(localized: "macOS keeps the audio drivers \(names) running until you restart your Mac.")]
    }

    /// One line for the apps whose background items macOS still starts from the Trash at each login.
    private static func trashLines(_ outcome: RemovalOutcome, naming: ([String]) -> String) -> [String] {
        let apps = outcome.appsStartingFromTheTrash
        guard !apps.isEmpty else { return [] }
        let names = naming(apps)
        return [String(localized: "macOS still starts the background items of \(names) from the Trash each time you log in, until you empty the Trash.")]
    }

    /// A line for each app that stayed, since its files, which wait for it, stayed too and are not listed.
    private static func keptLines(_ outcome: RemovalOutcome) -> [String] {
        outcome.keptTheirFiles.map { String(localized: "\($0) stayed, and so did its files.") }
    }

    private static func appManagementLines(_ outcome: RemovalOutcome) -> [String] {
        guard needsAppManagement(outcome) else { return [] }
        return [String(localized: "If Peel isn’t allowed under App Management, macOS won’t let it move another developer’s app to the Trash.")]
    }

    /// Offered for a failure, whose full path the alert shortens, and wherever the alert names only the first entries
    /// of a list, so every name it leaves out can still be read.
    static func offersDetails(for outcome: RemovalOutcome) -> Bool {
        !outcome.failures.isEmpty || !outcome.putBackFailures.isEmpty || message(for: outcome) != details(for: outcome)
    }

    /// Copies every item with its full path, since the alert lists only the first few and its text can't be
    /// selected.
    private static func copyDetails(of outcome: RemovalOutcome) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details(for: outcome), forType: .string)
    }

    static func details(for outcome: RemovalOutcome) -> String {
        var lines = historyLines(outcome)
            + outcome.putBackFailures.map { "\($0.url.path(percentEncoded: false))\n\($0.failure.explanation)" }
            + quitLines(outcome)
            + outcome.failures.map { "\($0.url.path(percentEncoded: false))\n\($0.reason.explanation)" }
            + keptLines(outcome) + driverLines(outcome) + administratorLines(outcome)
            + shellLines(outcome) { $0.formatted(.list(type: .and)) } + appManagementLines(outcome)
            + privacyLines(outcome)
        if #available(macOS 27, *) {
            lines += trashLines(outcome) { $0.formatted(.list(type: .and)) }
        }
        return lines.joined(separator: "\n\n")
    }

    /// A line for each app whose tool kept what was selected for it, since the app was open.
    private static func quitLines(_ outcome: RemovalOutcome) -> [String] {
        outcome.appsToQuit.map { String(localized: "Quit \($0) before removing its files.") }
    }

    /// One line per privacy reset. When a single failed reset is all there is to report, the title already
    /// says so, and the line gives only the reason.
    private static func privacyLines(_ outcome: RemovalOutcome) -> [String] {
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
    private static func needsAppManagement(_ outcome: RemovalOutcome) -> Bool {
        outcome.failures.contains { failure in
            failure.reason == .notPermitted && failure.url.pathExtension.lowercased() == "app"
                && AppManagement.isRefusedForWantOfPermission(failure.url)
        }
    }

    private static func needsHelper(_ outcome: RemovalOutcome) -> Bool {
        outcome.failures.contains { $0.reason == .needsHelper }
            || outcome.putBackFailures.contains { $0.failure == .needsHelper }
    }
}

extension View {
    func removalFailureAlert() -> some View {
        modifier(RemovalFailureAlert())
    }
}
