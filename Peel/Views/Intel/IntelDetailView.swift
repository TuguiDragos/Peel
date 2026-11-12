import AppKit
import PeelCore
import SwiftUI

struct IntelDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(PluginLibrary.self) private var plugins
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @Environment(PackageLibrary.self) private var packages
    @Environment(HomebrewLibrary.self) private var homebrew
    /// The package that installed a Java runtime, whose page can move it.
    @State private var receipt: PackageReceipt.ID?
    let finding: IntelFinding

    /// When `app` was last opened, for an app or a bundle inside one. Read from the list, which follows it, since
    /// a new date is no reason to scan again.
    private func lastOpened(of app: InstalledApp?) -> Date? {
        switch finding.kind {
        case .app, .insideApp: app?.lastUsedDate
        case .plugin, .driver, .backgroundItem, .commandLineTool, .javaRuntime: nil
        }
    }

    var body: some View {
        // Found once for the whole page: it walks every app.
        let app = AppCatalog.app(holding: finding.url, among: library.apps)
        Form {
            Section {
                header
                    .listRowSeparator(.hidden)
            }

            Section {
                Text(finding.explanation(onAppleSilicon: HostArchitecture.isAppleSilicon))
                    .font(.callout)
                if #available(macOS 27, *), HostArchitecture.isAppleSilicon, finding.loadsThroughAnApp {
                    Text("macOS 27 opens an app natively even if you set it to open using Rosetta.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // Where nothing loads it, Rosetta would change nothing, so nothing here sends the person to install it.
                if finding.noLongerLoaded == nil, !HostArchitecture.isAppleSilicon {
                    Text("On an Apple silicon Mac it would need Rosetta.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if finding.noLongerLoaded == nil {
                    if Rosetta.isInstalled {
                        // After macOS 27, Apple keeps Rosetta only for older games, which is why this says "most"
                        // rather than "all" (developer.apple.com/news, Rosetta).
                        Text("macOS 27 is the last release that runs most Intel software through Rosetta. Apple keeps it for older games.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        // A Mac that had Rosetta does not get it back after upgrading to macOS 27. Without it, Intel
                        // software does not run at all, so the text must not say it runs through Rosetta.
                        Text(finding.withoutRosetta)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if !finding.kind.offersRosettaWhenOpened {
                            CopyableLines(
                                caption: Text("Run this in Terminal to install Rosetta, then follow its instructions."),
                                lines: [Rosetta.installCommand]
                            )
                        }
                    }
                    // The list also names Intel apps that are only installed, so it matters without Rosetta too.
                    if #available(macOS 27, *) {
                        HStack(spacing: 8) {
                            Text("The Intel-based Apps list in System Settings > General > About names the apps macOS 28 won’t run. Peel also looks inside apps and at plug-ins and drivers, which that list may leave out.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(DeviceInfo.aboutURL)
                            }
                        }
                    }
                }
            } header: {
                Text("Why It Matters")
            }

            Section {
                LabeledContent("Where") {
                    Text(verbatim: finding.url.abbreviatedPath)
                        .textSelection(.enabled)
                        .help(Text(verbatim: finding.url.fullPath))
                    ShowInFinderButton(url: finding.url)
                }
                .labeledContentStyle(.oneLine)
                LabeledContent("Size") {
                    Text(finding.size.byteCount).monospacedDigit()
                }
                if !finding.backgroundItems.isEmpty {
                    LabeledContent("Background Items") {
                        Text(verbatim: finding.backgroundItems.formatted(.list(type: .and)))
                            .textSelection(.enabled)
                    }
                }
                if let lastOpened = lastOpened(of: app) {
                    LabeledContent {
                        Text(lastOpened, format: .relative(presentation: .named))
                    } label: {
                        finding.kind == .insideApp ? Text("App last opened") : Text("Last opened")
                    }
                }
                if let app, let status = library.shownUpdateStatus(of: app) {
                    LabeledContent("Updates") {
                        UpdateStatusBadge(
                            app: app,
                            status: status,
                            isChecking: library.appsCheckingForUpdates.contains(app.id),
                            failure: library.updateFailures[app.id],
                            keptSince: library.keptUpToDate(of: app),
                            cannotCheck: library.whyItCannotCheck(app),
                            brew: homebrew.wordForTerminal
                        )
                    }
                }
            } header: {
                Text("Details")
            }

            if app == nil, !finding.isOnThePlugInsPage, finding.job == nil, receipt == nil {
                Section {
                    Text(advice)
                        .font(.callout)
                } header: {
                    Text("What to Do About It")
                }
            } else {
                Section {
                } header: {
                    HeadingWithActions {
                        heading("What to Do About It", advice)
                    } actions: {
                        review(of: app)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: finding.url) {
            guard finding.kind == .javaRuntime else { return }
            receipt = await PackageReceipts.receipts(installing: finding.url).first?.id
        }
        .navigationTitle(Text(verbatim: finding.name))
        .toolbar(removing: .title)
    }

    /// The button that leads to the page where this can be dealt with.
    @ViewBuilder
    private func review(of app: InstalledApp?) -> some View {
        if let app {
            let button = Button("Review in Applications") {
                library.selection = [app.id]
                // Selecting the app does not switch tools by itself, so Applications is requested too.
                Navigator.shared.requestedTool = .applications
            }
            // A part inside the app never goes alone, so removing the app isn't the step to lead with.
            if finding.kind == .insideApp {
                button
            } else {
                button.buttonStyle(.borderedProminent)
            }
        } else if finding.isOnThePlugInsPage {
            Button("Review in Plug-ins") {
                plugins.selection = finding.url
                Navigator.shared.requestedTool = .plugins
            }
            .buttonStyle(.borderedProminent)
        } else if let receipt {
            Button("Review in Package Receipts") {
                packages.selection = receipt
                Navigator.shared.requestedTool = .packages
            }
            .buttonStyle(.borderedProminent)
        } else if let job = finding.job {
            Button("Review in Background Items") {
                backgroundItems.selection = job
                Navigator.shared.requestedTool = .backgroundItems
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// The advice in the note beside the What to Do About It heading. A driver, a tool in `/usr/local`, or a plug-in
    /// the Plug-ins page doesn't list is left to the software that installed it, which knows what else goes with it.
    private var advice: LocalizedStringResource {
        switch finding.kind {
        case .driver, .commandLineTool:
            "Peel only reports here. The software that installed it may have an uninstaller of its own."
        case .app:
            "Peel only reports here. To remove it, go to Applications, where you see everything that goes with the app."
        case .insideApp:
            "Peel only reports here. This part comes with the app and can’t be removed on its own. An update of the app may replace it."
        case .plugin:
            finding.isOnThePlugInsPage
                ? "Peel only reports here. To remove it, go to Plug-ins."
                : "Peel only reports here. The software that installed it may have an uninstaller of its own."
        case .backgroundItem:
            "Peel only reports here. Background Items moves a job’s configuration file, not the program it runs: that goes with the software that installed it."
        case .javaRuntime:
            receipt == nil
                ? "Peel only reports here. A Java runtime is its folder: to remove it, move the folder to the Trash in Finder, which asks for an administrator’s password where only an administrator can change it."
                : "Peel only reports here. A package installed this Java runtime, so Package Receipts can move it, and History can put it back."
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            AppIcon(url: finding.url)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: finding.name)
                    .pageTitle()
                    .help(Text(verbatim: finding.name))
                if finding.owner != nil, let subtitle = finding.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                FlowLayout {
                    NoteBadge(
                        title: Text(finding.badge.title), systemImage: "cpu",
                        name: String(localized: finding.badge.title),
                        detail: Text(finding.badge.detail)
                    )
                    Badge(
                        title: Text(finding.pluginCategory?.title ?? finding.kind.title),
                        systemImage: finding.kind.systemImage
                    )
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
