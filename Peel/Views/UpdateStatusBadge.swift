import PeelCore
import SwiftUI

struct UpdateStatusBadge: View {
    let app: InstalledApp
    let status: UpdateStatus?
    let isChecking: Bool
    /// When a check last got an answer, which is what the note for a failed check tells the user.
    var lastCheck: Date?
    let cannotCheck: CannotCheck

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
                if let lastCheck {
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
        switch cannotCheck {
        case .homebrewCannotTell(let silence):
            switch silence.reason {
            case .notCheckedRecently:
                if let checked = silence.cask.lastUpdateCheck {
                    Text("Only Homebrew can say whether \(app.name) is up to date, and Homebrew last checked for new versions \(checked, format: .relative(presentation: .named)). Peel counts what Homebrew says only for a day after it checks. Update Homebrew on the Homebrew page, or run `brew update` in Terminal, and Peel can tell again.")
                } else {
                    Text("Only Homebrew can say whether \(app.name) is up to date, but Peel can’t tell when Homebrew last checked for new versions, so it doesn’t count what Homebrew says.")
                }
            case .installsTheNewest:
                Text("Only Homebrew could say whether \(app.name) is up to date, but it installs whatever is newest each time, so it has no version to compare this copy with. Look for an update inside the app.")
            case .leftToTheApp:
                Text("Only Homebrew could say whether \(app.name) is up to date, but Homebrew’s settings leave apps that update themselves to their own updates, so it doesn’t compare their versions. Look for an update inside the app.")
            case .disabled:
                Text("Only Homebrew could say whether \(app.name) is up to date, but Homebrew has disabled it and no longer upgrades it. Look for an update inside the app, or on its maker’s website.")
            }
        case .cameWithMacOS:
            Text("\(app.name) came with macOS. Software Update is what keeps it current, so Peel has nothing to ask.")
        case .cameFromSetapp:
            Text("\(app.name) came from Setapp. Setapp is what keeps it current, so Peel has nothing to ask.")
        case .namesNoVersion:
            Text("\(app.name) doesn’t say which version it is, so Peel has nothing to compare an update with. Look for an update inside the app.")
        case .notInTheAppStore(store: nil):
            Text("The App Store gives Peel no version of \(app.name) to compare, as for an app it doesn’t sell in your Mac’s region or doesn’t sell anymore. The App Store app itself knows when there is an update.")
        case .notInTheAppStore:
            Text("The App Store \(app.name) came from gives Peel no version of it to compare, as for an app that store doesn’t sell anymore. The App Store app itself knows when there is an update.")
        case .namesNoFeed:
            Text("\(app.name) doesn’t say where it updates from in a way Peel can read. Peel reads an app’s update feed from the app’s own files, and asking Apple about every app instead would send Apple a list of what is installed on this Mac. Look for an update inside the app.")
        }
    }

    private var failureReason: Text {
        if let lastCheck {
            Text("Peel asked where \(app.name) updates from and got no answer it could read. The last answer came \(lastCheck, format: .relative(presentation: .named)). A feed that is down, moved, or behind a sign-in ends up here, and Peel asks again at the next check.")
        } else {
            Text("Peel asked where \(app.name) updates from and got no answer it could read. A feed that is down, moved, or behind a sign-in ends up here, and Peel asks again at the next check.")
        }
    }
}
