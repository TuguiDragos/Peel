import PeelCore
import SwiftUI

struct UpdateStatusBadge: View {
    let app: InstalledApp
    let status: UpdateStatus?
    let isChecking: Bool
    /// When a check last got an answer, which is what the note for a failed check tells the user.
    var lastCheck: Date?
    var failure: UpdateFailure?
    /// The day an Up to date nothing renews anymore was found (`AppLibrary.keptUpToDate`).
    var keptSince: Date?
    let cannotCheck: CannotCheck
    /// The word that runs the person's Homebrew in Terminal (`Homebrew.wordForTerminal`).
    let brew: String

    var body: some View {
        BusyShown(isBusy: isChecking) { isShown in
            badge(isChecking: isShown)
                .motion(value: isShown)
                .motion(value: status)
        }
    }

    @ViewBuilder
    private func badge(isChecking: Bool) -> some View {
        if isChecking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking for updates…")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        } else if let status {
            switch status {
            case .updateAvailable:
                Badge(title: Text("Update available: \(status.displayVersion ?? "")"), systemImage: "arrow.down.circle", tint: .blue)
            case .upToDate:
                if let keptSince {
                    Badge(
                        title: Text("Up to date as of \(keptSince, format: .dateTime.day().month(.abbreviated).year())"),
                        systemImage: "checkmark.circle",
                        tint: .green
                    )
                } else if let lastCheck {
                    upToDate.help(Text("Peel last checked \(lastCheck, format: .relative(presentation: .named))."))
                } else {
                    upToDate
                }
            case .unsupported:
                NoteBadge(
                    title: Text("Can’t check for updates"),
                    systemImage: "questionmark.circle",
                    name: String(localized: "Can’t check for updates"),
                    detail: unsupportedReason,
                    label: Text("Why Peel can’t check \(app.name) for updates")
                )
            case .failed:
                NoteBadge(
                    title: Text("Update check failed"),
                    systemImage: "exclamationmark.triangle",
                    tint: .orange,
                    name: String(localized: "Update check failed"),
                    detail: failureReason,
                    label: Text("Why the update check for \(app.name) failed")
                )
            }
        }
    }

    private var upToDate: some View {
        Badge(title: Text("Up to date"), systemImage: "checkmark.circle", tint: .green)
    }

    /// Why Peel can't check this app. Several reasons share the one badge, so the note says which applies. The
    /// preferred update source is never the reason: an app not sold by the App Store is checked through its
    /// own feed whatever that setting says.
    private var unsupportedReason: Text {
        Text(Self.reason(cannotCheck, name: app.name, brew: brew))
    }

    /// Why Peel can't check the app named `name`, with `brew` the word that runs the person's Homebrew in Terminal.
    static func reason(_ cannotCheck: CannotCheck, name: String, brew: String) -> LocalizedStringResource {
        switch cannotCheck {
        case .homebrewCannotTell(let silence):
            switch silence.reason {
            case .notCheckedRecently:
                if let checked = silence.cask.lastUpdateCheck {
                    "Only Homebrew can say whether \(name) is up to date, and it last checked \(checked, format: .relative(presentation: .named)). Peel trusts that answer for a day. Update Homebrew on the Homebrew page, or run `\("\(brew) update")` in Terminal."
                } else {
                    "Only Homebrew can say whether \(name) is up to date, but Peel cannot tell when it last checked. Update Homebrew on the Homebrew page, or run `\("\(brew) update")` in Terminal."
                }
            case .installsTheNewest:
                "Homebrew installs whatever is newest each time, so it has no version to compare with this copy. Look for an update inside \(name)."
            case .leftToTheApp:
                "Homebrew leaves apps that update themselves to their own updates, so it does not compare their versions. Look for an update inside \(name)."
            case .disabled:
                "Homebrew has disabled \(name) and no longer upgrades it. Look for an update inside the app or on the website of its maker."
            }
        case .cameWithMacOS:
            "\(name) came with macOS. Software Update is what keeps it current, so Peel has nothing to ask."
        case .cameFromSetapp:
            "\(name) came from Setapp. Setapp is what keeps it current, so Peel has nothing to ask."
        case .namesNoVersion:
            "\(name) doesn’t say which version it is, so Peel has nothing to compare an update with. Look for an update inside the app."
        case .notInTheAppStore:
            "The App Store gives Peel no version of \(name) to compare, as for an app it no longer sells or does not sell in your region. The App Store app knows when there is an update."
        case .namesNoFeed:
            "\(name) does not say where it updates from in a way Peel can read. Look for an update inside the app. Peel does not ask Apple about every app, since that would send Apple a list of what you have."
        }
    }

    private var failureReason: Text {
        Text(verbatim: [
            failure?.explanation(about: app.name)
                ?? String(localized: "Peel asked whether \(app.name) has an update and got no answer it could read."),
            lastCheck.map { checked in
                String(localized: "The last answer Peel could read came \(checked.formatted(.relative(presentation: .named))).")
            },
            String(localized: "Peel asks again at the next check."),
        ].compactMap(\.self).joined(separator: " "))
    }
}
