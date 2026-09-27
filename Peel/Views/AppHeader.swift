import PeelCore
import SwiftUI

/// The app the page is about, and what can be done to it short of removing it.
///
/// The actions sit under the name, where they read as belonging to the app. Each is a single control, so a
/// section for each would make a column of headings with one row under each.
struct AppHeader<Actions: View>: View {
    let app: InstalledApp
    let updateStatus: UpdateStatus?
    let isCheckingForUpdates: Bool
    /// The version a waiting update would bring. The caller passes it only when `AppLibrary.hasUpdate` is true.
    var waitingVersion: String?
    var lastCheck: Date?
    var total: SizeTotal?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIcon(url: app.url)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .pageTitle()
                        .help(Text(verbatim: app.name))
                    identity
                }
                actions
            }
            Spacer(minLength: 12)
            if let total, total.known > 0 || !total.isComplete {
                TotalLabel(total: total, caption: Text("to remove"))
                    .accessibilityLabel(Text("\(total.text) can be moved to the Trash"))
            }
        }
        .padding(.bottom, 8)
    }

    /// The line under the name: the bundle identifier, the installed version, and where an update would take
    /// it, then badges for anything unusual about the app and for the update status. It wraps when it doesn't fit.
    private var identity: some View {
        FlowLayout(spacing: 6) {
            HStack(spacing: 5) {
                Text(app.bundleIdentifier)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let version = app.version {
                    Text(verbatim: "·")
                        .accessibilityHidden(true)
                    if let waitingVersion {
                        Text(verbatim: "\(version) → \(waitingVersion)")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(Text("\(version), update available: \(waitingVersion)"))
                    } else {
                        Text(verbatim: version)
                    }
                }
            }
            .font(.subheadline.monospaced())
            .foregroundStyle(.secondary)

            if app.isFromAppStore {
                Badge(title: Text("App Store"), systemImage: "bag", tint: .secondary)
            }
            if app.isIntelOnly {
                NoteBadge(
                    title: Text("Intel only"), systemImage: "cpu", tint: .secondary,
                    name: String(localized: "Intel only"),
                    detail: Text("Built for Intel processors only, so on Apple silicon it runs through Rosetta.")
                )
            }
            if app.isSystemProtected {
                NoteBadge(
                    title: Text("Protected by macOS"), systemImage: "lock", tint: .secondary,
                    name: String(localized: "Protected by macOS"),
                    detail: Text("macOS keeps this app, so it stays where it is.")
                )
            }
            // A waiting update already shows beside the version, so the status badge shows only when
            // there is none.
            if waitingVersion == nil {
                UpdateStatusBadge(
                    app: app,
                    status: updateStatus,
                    isChecking: isCheckingForUpdates,
                    lastCheck: lastCheck
                )
            }
        }
        .motion(value: waitingVersion)
    }
}
