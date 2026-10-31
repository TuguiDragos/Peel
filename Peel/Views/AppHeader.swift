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
    /// True when `AppLibrary.hasUpdate` is, since the page then shows the update in a panel of its own.
    var hasWaitingUpdate = false
    var lastCheck: Date?
    let cannotCheck: CannotCheck
    var total: SizeTotal?
    /// True when the app frees much less than its size, because most of it is shared with another copy.
    var sharesStorage = false
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
    }

    /// The line under the name: the bundle identifier and the installed version, then badges for anything unusual
    /// about the app and for the update status. It wraps when it doesn't fit.
    private var identity: some View {
        FlowLayout(spacing: 6) {
            HStack(spacing: 5) {
                if let identifier = app.bundleIdentifier {
                    Text(identifier)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let version = app.version {
                    if app.bundleIdentifier != nil {
                        Text(verbatim: "·")
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: version)
                }
            }
            .font(.subheadline.monospaced())
            .foregroundStyle(.secondary)

            if app.isFromAppStore {
                Badge(title: Text("App Store"), systemImage: "bag")
            }
            if app.isIntelOnly {
                NoteBadge(
                    title: Text("Intel only"), systemImage: "cpu",
                    name: String(localized: "Intel only"),
                    detail: Text("Built for Intel processors only. On Apple silicon it needs Rosetta.")
                )
            }
            if sharesStorage {
                NoteBadge(
                    title: Text("Shares storage"), systemImage: "link",
                    name: String(localized: "Shares storage"),
                    detail: Text("Most of this app’s files share their space on disk with another copy of it, such as one in the Trash, so moving it frees much less than its size.")
                )
            }
            if app.isSystemProtected {
                NoteBadge(
                    title: Text("Protected by macOS"), systemImage: "lock",
                    name: String(localized: "Protected by macOS"),
                    detail: Text("macOS keeps this app, so it stays where it is.")
                )
            }
            if !hasWaitingUpdate {
                UpdateStatusBadge(
                    app: app,
                    status: updateStatus,
                    isChecking: isCheckingForUpdates,
                    lastCheck: lastCheck,
                    cannotCheck: cannotCheck
                )
            }
        }
        .motion(value: hasWaitingUpdate)
    }
}
