import PeelCore
import SwiftUI

struct HomebrewDetailView: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(AppLibrary.self) private var library
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var isConfirmingUninstall = false
    let package: HomebrewPackage

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: package.kind == .cask ? "macwindow" : "terminal")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: package.name)
                            .font(.title.bold())
                            .titleLine()
                            .textSelection(.enabled)
                            .help(Text(verbatim: package.name))
                        if let summary = package.summary {
                            Text(verbatim: summary)
                                .foregroundStyle(.secondary)
                        }
                        FlowLayout(spacing: 6) {
                            Badge(title: Text(package.kind == .cask ? "Cask" : "Formula"), systemImage: "mug", tint: .secondary)
                            if let version = package.installedVersion {
                                Badge(title: Text("Version \(version)"), systemImage: "number", tint: .secondary)
                            }
                            if package.isOutdated, let latest = package.latestVersion {
                                Badge(title: Text("Update available: \(latest)"), systemImage: "arrow.down.circle", tint: .blue)
                            }
                            if package.isPinned {
                                NoteBadge(
                                    title: Text("Pinned"), systemImage: "pin", tint: .secondary,
                                    name: String(localized: "Pinned"),
                                    detail: Text("Homebrew keeps a pinned package at its version when it upgrades the rest. Run `brew unpin` to let it upgrade again.")
                                )
                            }
                            if !package.isInstalledOnRequest {
                                NoteBadge(
                                    title: Text("Dependency"), systemImage: "link", tint: .secondary,
                                    name: String(localized: "Dependency"),
                                    detail: Text("Homebrew installed this because another package needs it.")
                                )
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            if let retirement = package.retirement {
                Notice(
                    title: retirement.title,
                    detail: retirement.explanation(now: .now),
                    kind: .caution,
                    systemImage: "exclamationmark.triangle.fill"
                ) {}
            }

            Section {
                if let homepage = package.homepage {
                    LabeledContent("Homepage") {
                        Link(destination: homepage) {
                            Text(verbatim: homepage.host() ?? homepage.absoluteString)
                                .minimumTarget()
                        }
                    }
                }
                if !package.dependencies.isEmpty {
                    LabeledContent("Dependencies") {
                        Text(verbatim: package.dependencies.formatted(.list(type: .and)))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                HStack {
                    if package.isOutdated {
                        if package.upgradeNeedsAnAdministrator {
                            CopyButton(text: "brew upgrade --cask \(package.fullName)", title: "Copy Upgrade Command")
                        } else {
                            Button("Upgrade", systemImage: "arrow.down.circle") {
                                Task { await homebrew.run(.upgrade(package.id)) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(package.isPinned)
                        }
                    }
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running Homebrew…")
                            .foregroundStyle(.secondary)
                    } else if let uninstallRefusal {
                        Label { Text(uninstallRefusal) } icon: { Image(systemName: "hand.raised.fill") }
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isUninstalledInTerminal {
                        CopyButton(text: "brew uninstall --cask \(package.fullName)", title: "Copy Uninstall Command")
                    } else {
                        Button("Uninstall", systemImage: "trash", role: .destructive) {
                            isConfirmingUninstall = true
                        }
                        .disabled(uninstallRefusal != nil)
                    }
                }
                .disabled(homebrew.runningCommand != nil)
                if (package.isOutdated && package.upgradeNeedsAnAdministrator) || isUninstalledInTerminal {
                    Text(needsTerminal)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(package.name)
        .toolbar(removing: .title)
        .confirmationDialog("Uninstall \(package.name)?", isPresented: $isConfirmingUninstall) {
            Button("Uninstall", role: .destructive) {
                // Checks again, since the exclusions can change while the dialog is open.
                guard uninstallRefusal == nil else { return }
                Task { await homebrew.run(.uninstall(package.id)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew deletes the package for good: nothing goes to the Trash, and History can’t put it back. It won’t do this while another package needs it, and it also removes every formula nothing needs anymore, whichever package brought it in.")
        }
    }

    /// Said where Peel hands a cask's command to Terminal: `brew` asks for an administrator's password with `sudo`,
    /// which needs a terminal, and Peel runs it without one.
    private let needsTerminal: LocalizedStringResource = "Homebrew needs an administrator’s password for this, and only Terminal can ask for it. Copy the command, then run it in Terminal."

    /// A cask whose uninstall needs an administrator is offered as a command, unless it may not be uninstalled at all.
    private var isUninstalledInTerminal: Bool {
        package.uninstallNeedsAnAdministrator && uninstallRefusal == nil
    }

    /// Why Uninstall is unavailable, or nil when it's allowed. `brew uninstall` deletes permanently, outside
    /// `TrashService` and `RemovalGuard`, so this is where the exclusions are checked.
    private var uninstallRefusal: LocalizedStringResource? {
        if exclusions.exclusions.isUnreadable { return "Exclusions can’t be read: see Settings" }
        if !exclusions.exclusions.hasBeenRead { return "Checking…" }
        let apps = library.apps.filter { library.cask(for: $0)?.id == package.id }
        return exclusions.exclusions.excludes(package, apps: apps, prefix: homebrew.installation?.prefix) ? "Excluded in Settings" : nil
    }

    private var isRunning: Bool {
        switch homebrew.runningCommand {
        case .upgrade(let id), .uninstall(let id): id == package.id
        case .upgradeAll: package.isOutdated && package.joinsUpgradeAll
        case .update, .cleanup, .health, .vulnerabilities, nil: false
        }
    }
}
