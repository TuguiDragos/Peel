import PeelCore
import SwiftUI

struct HomebrewDetailView: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(AppLibrary.self) private var library
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(PeelUpdater.self) private var updater
    @State private var isConfirmingUninstall = false
    /// What uses this formula, read when Uninstall is pressed. Nil for a cask, whose apps are asked to quit.
    @State private var inUse: FormulaInUse?
    @State private var leftInTheSystem: LeftInTheSystem?
    @State private var commandToRunFirst: CommandToRunFirst?
    @State private var isConfirmingUpgrade = false
    @State private var casksToForget: [HomebrewPackage]?
    /// What macOS said of the system extensions the cask's apps carry, with the apps it was asked about.
    @State private var extensionsAnswer: (apps: [URL], removedElsewhere: RemovedElsewhere?)?
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
                            .pageTitle()
                            .textSelection(.enabled)
                            .help(Text(verbatim: package.name))
                        if let summary = package.summary {
                            Text(verbatim: summary)
                                .foregroundStyle(.secondary)
                        }
                        FlowLayout(spacing: 6) {
                            Badge(title: Text(package.kind == .cask ? "Cask" : "Formula"), systemImage: "mug")
                            if let version = package.installedVersion {
                                Badge(title: Text("Version \(version)"), systemImage: "number")
                            }
                            if package.waitsForAnUpgrade, let latest = package.latestVersion {
                                Badge(title: Text("Update available: \(latest)"), systemImage: "arrow.down.circle", tint: .blue)
                            }
                            if let advisory {
                                Badge(
                                    title: Text("^[\(advisory.vulnerabilities.count) known vulnerability](inflect: true)"),
                                    systemImage: advisory.highestSeverity.symbol,
                                    tint: advisory.highestSeverity.color
                                )
                            }
                            if package.isPinned {
                                NoteBadge(
                                    title: Text("Pinned"), systemImage: "pin",
                                    name: String(localized: "Pinned"),
                                    detail: Text("Homebrew keeps a pinned package at its version when it upgrades the rest. Run `brew unpin` to let it upgrade again.")
                                )
                            }
                            if !package.isInstalledOnRequest {
                                NoteBadge(
                                    title: Text("Dependency"), systemImage: "link",
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

            if package.isMissingWhatItInstalled, package.appTargets.isEmpty {
                Notice(
                    title: Text("The Packages Are Already Gone"),
                    detail: Text("Homebrew still lists this cask, but the packages it installed aren’t on this Mac anymore, so Homebrew can’t upgrade it. Forget Cask moves the cask’s Homebrew receipt to the Trash, so Homebrew stops listing it, and History can put it back."),
                    kind: .note
                ) {}
            } else if package.isStoppedMidUpgrade {
                Notice(
                    title: Text("The Upgrade Was Stopped"),
                    detail: Text("Homebrew was stopped while it upgraded this cask, so its app is still in Homebrew’s folder rather than where it belongs. Reinstalling the cask in Terminal puts it back."),
                    kind: .caution
                ) {
                    CopyButton(text: "brew reinstall --cask \(package.fullName)", title: "Copy Reinstall Command")
                }
            } else if package.isMissingWhatItInstalled {
                Notice(
                    title: Text("The App Is Already Gone"),
                    detail: Text("Homebrew still lists this cask, but its app isn’t where Homebrew put it anymore, so Homebrew can’t upgrade it. Forget Cask moves the cask’s Homebrew receipt to the Trash, so Homebrew stops listing it, and History can put it back."),
                    kind: .note
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
                if let reason = homebrew.whyItCantChange {
                    HStack(spacing: 8) {
                        Text(reason.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let command = reason.command {
                            Spacer(minLength: 8)
                            CopyButton(text: command)
                        }
                    }
                } else {
                    if package.isMissingWhatItInstalled {
                        RemovalsHeldBanner()
                    }
                    if package.waitsForAnUpgrade, package.isPeelItself {
                        Text("Peel updates itself, so it isn’t upgraded from here: Homebrew would have to quit Peel first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if package.waitsForAnUpgrade, homebrew.overrides.contains(.cleansUp), upgradeRefusal == nil {
                        Text(HomebrewLibrary.cleansUp)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if (package.waitsForAnUpgrade && package.upgradeNeedsAnAdministrator && !package.isPeelItself
                        && upgradeRefusal == nil) || isUninstalledInTerminal {
                        Text(needsTerminal)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if homebrew.whyItCantChange == nil {
                PageActions {
                    if isUninstalledInTerminal {
                        CopyButton(
                            text: Homebrew.terminalCommand(
                                "brew uninstall --cask \(package.fullName)", keeping: homebrew.keptFormulaeNow
                            ),
                            title: "Copy Uninstall Command"
                        )
                    } else {
                        Button("Uninstall", role: .destructive) {
                            Task {
                                await readWhatUsesIt()
                                leftInTheSystem = LeftInTheSystem.of(package)
                                commandToRunFirst = CommandToRunFirst.of(package)
                                isConfirmingUninstall = true
                            }
                        }
                        .disabled(uninstallRefusal != nil)
                    }
                    stateAndUpgrade
                }
                .disabled(
                    homebrew.runningCommand != nil || homebrew.isForgetting || homebrew.quittingToUpgrade.isWaiting
                        || homebrew.quittingToUninstall.isWaiting
                )
            }

            if let (version, notes) = caskNotes {
                Section {
                    ReleaseNotesView(notes: notes, version: version)
                } header: {
                    Text("What’s New in \(version)")
                }
            }

            if let advisory {
                HomebrewVulnerabilitySections(advisory: advisory, package: package)
            }
        }
        .formStyle(.grouped)
        .dimmedWhileBusy(homebrew.isReadingWhatChanged)
        .navigationTitle(package.name)
        .toolbar(removing: .title)
        // Asked first, as Upgrade All is: an upgrade can run for a long time while Homebrew builds on this Mac.
        .confirmationDialog("Upgrade \(package.name)?", isPresented: $isConfirmingUpgrade) {
            Button("Upgrade") {
                // Checks again, since the exclusions can change while the dialog is open.
                guard upgradeRefusal == nil else { return }
                upgrade()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can take a long time, since Homebrew builds some packages on this Mac. Its progress shows on this page as it works, and you can stop it there.")
        }
        .forgetCasksDialog(for: $casksToForget)
        .task(id: library.apps(of: package).filter(\.carriesSystemExtensions).map(\.url)) {
            let carrying = library.apps(of: package).filter(\.carriesSystemExtensions)
            guard !carrying.isEmpty else { return }
            let found = await RemovedElsewhere.first(among: carrying)
            extensionsAnswer = (carrying.map(\.url), found)
        }
        .confirmationDialog("Uninstall \(package.name)?", isPresented: $isConfirmingUninstall) {
            Button("Uninstall", role: .destructive) {
                // Checks again, since the exclusions can change while the dialog is open.
                guard uninstallRefusal == nil else { return }
                uninstall()
            }
            if let command = inUse?.stopCommand {
                Button("Copy Stop Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            uninstallMessage
        }
    }

    /// What is under way or in the way, and the step that brings the package up to date.
    private var stateAndUpgrade: some View {
        HStack {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("Running Homebrew…")
                    .foregroundStyle(.secondary)
            } else if let uninstallRefusal {
                Label { Text(uninstallRefusal) } icon: { Image(systemName: "hand.raised.fill") }
                    .foregroundStyle(.secondary)
            }
            if package.isMissingWhatItInstalled {
                Button("Forget Cask") { casksToForget = [package] }
                    .buttonStyle(.borderedProminent)
                    .disabled(!history.mayMove)
                    .help(Text(verbatim: history.holdingReason?.explanation ?? ""))
            } else if package.waitsForAnUpgrade {
                if package.isPeelItself {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updater.canCheckForUpdates)
                } else if upgradeRefusal == nil,
                          package.upgradeNeedsAnAdministrator || homebrew.overrides.contains(.cleansUp) {
                    let kind = package.kind == .cask ? "--cask" : "--formula"
                    CopyButton(
                        text: Homebrew.terminalCommand(
                            "brew upgrade \(kind) \(package.fullName)", keeping: homebrew.keptFormulaeNow
                        ),
                        title: "Copy Upgrade Command"
                    )
                } else {
                    Button("Upgrade") {
                        isConfirmingUpgrade = true
                    }
                    .buttonStyle(.borderedProminent)
                    // A cask's apps, which have to quit first, are known only once they are matched.
                    .disabled(
                        package.isPinned || package.kind == .cask && !library.knowsHomebrewsApps
                            || upgradeRefusal != nil
                    )
                    .help(upgradeRefusal.map { Text($0) } ?? Text(verbatim: ""))
                }
            }
        }
    }

    private func readWhatUsesIt() async {
        guard package.kind == .formula, let cellar = homebrew.installation?.cellar else {
            inUse = nil
            return
        }
        inUse = await FormulaInUse.of(formula: package.name, cellar: cellar)
    }

    private var uninstallMessage: Text {
        let deletes = homebrew.overrides.contains(.keepsDependencies)
            ? Text("Homebrew deletes the package for good: nothing goes to the Trash, and History can’t put it back. It won’t do this while another package needs it.")
            : Text("Homebrew deletes the package for good: nothing goes to the Trash, and History can’t put it back. It won’t do this while another package needs it, and it also removes every formula nothing needs anymore, whichever package brought it in.")
        let deletesAndLeaves = whatStays.map { Text("\(deletes)\n\n\($0)") } ?? deletes
        return whatUsesIt.map { Text("\($0)\n\n\(deletesAndLeaves)") } ?? deletesAndLeaves
    }

    /// What Homebrew leaves of a package, which it says nothing of before it deletes the rest.
    private var whatStays: Text? {
        var lines: [Text] = []
        if let folders = inUse?.dataFolders, !folders.isEmpty {
            let places = folders.map(\.abbreviatedPath).formatted(.list(type: .and))
            lines.append(Text("Homebrew leaves \(places), with any data or settings the formula kept there."))
        }
        if let root = TrustedRoot.of(package) {
            lines.append(Text("\(package.name) added a root certificate to the certificates this Mac trusts, and Homebrew leaves it trusted."))
            lines.append(root.step(in: package.name))
        }
        if let first = commandToRunFirst {
            lines.append(first.note(for: package.name))
        }
        if let left = leftInTheSystem {
            lines.append(left.whatStays(after: package.name))
            lines.append(left.step)
        }
        guard let first = lines.first else { return nil }
        return lines.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }

    /// What Homebrew won't look at before it deletes a formula, said before it does.
    private var whatUsesIt: Text? {
        guard let inUse else { return nil }
        let programs = inUse.programs.formatted(.list(type: .and))
        return switch (inUse.programs.isEmpty, inUse.stopCommand) {
        case (true, nil): nil
        case (false, nil):
            Text("It is in use by \(programs). Homebrew deletes it even so, so quit what uses it first.")
        case (false, let command?):
            Text("It is in use by \(programs), and `brew services` keeps a job for it. Homebrew deletes it even so and leaves the job behind, so stop it first: `\(command)`")
        case (true, let command?):
            Text("`brew services` keeps a job for it. Homebrew leaves the job behind with nothing to run, so stop it first: `\(command)`")
        }
    }

    private func upgrade() {
        let quit = QuitBeforeHomebrew([package], library: library)
        homebrew.quittingToUpgrade.check(quit.processes) {
            // Asked again once its apps have quit, since the exclusions can change meanwhile.
            guard upgradeRefusal == nil else { return }
            Task { await homebrew.run(.upgrade(package.id), reopening: quit.reopen) }
        }
    }

    private func uninstall() {
        let quit = QuitBeforeHomebrew([package], library: library)
        homebrew.quittingToUninstall.check(quit.processes) {
            // Asked again once its apps have quit, since the exclusions can change meanwhile.
            guard uninstallRefusal == nil else { return }
            Task { await homebrew.run(.uninstall(package.id)) }
        }
    }

    private var advisory: HomebrewAdvisory? {
        homebrew.advisory(for: package)
    }

    /// What is new in the version Homebrew offers for a cask, as the app it installed says.
    private var caskNotes: (String, ReleaseNotes)? {
        guard package.kind == .cask, package.waitsForAnUpgrade,
              let app = library.apps.first(where: { library.cask(for: $0)?.id == package.id }),
              let notes = library.releaseNotes(of: app),
              let version = library.updateStatuses[app.id]?.displayVersion
        else { return nil }
        return (version, notes)
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
        // Until then the cask's apps aren't known, and with them neither are the rules their own pages follow.
        if !library.knowsHomebrewsApps { return "Checking…" }
        let apps = library.apps(of: package)
        // Homebrew deletes the app, so an app its own page never removes is never uninstalled from here either.
        if let removedElsewhere = apps.lazy.compactMap(\.removedElsewhere).first { return removedElsewhere.explanation }
        let carrying = apps.filter(\.carriesSystemExtensions).map(\.url)
        if !carrying.isEmpty {
            guard let extensionsAnswer, extensionsAnswer.apps == carrying else { return "Checking…" }
            if let removedElsewhere = extensionsAnswer.removedElsewhere { return removedElsewhere.explanation }
        }
        return upgradeRefusal
    }

    private var upgradeRefusal: LocalizedStringResource? {
        homebrew.exclusionRefusal(of: package)
    }

    private var isRunning: Bool {
        if homebrew.casksBeingForgotten.contains(package.id) { return true }
        return switch homebrew.commandHomebrewRuns {
        case .upgrade(let id), .uninstall(let id): id == package.id
        case .upgradeAll: homebrew.upgradable.contains { $0.id == package.id }
        case .update, .cleanup, .clearOlderDownloads, .clearEveryDownload, .repairTaps, .health, .vulnerabilities, nil:
            false
        }
    }
}
