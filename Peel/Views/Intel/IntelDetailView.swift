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
                    if DeviceInfo.listsIntelBasedApps {
                        HStack(spacing: 8) {
                            Text(Self.intelBasedAppsList)
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

            Section {
                let advice = advice
                HStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(advice.step)
                            .font(.body.weight(.semibold))
                        if let why = advice.why {
                            InfoNote(about: Text(advice.step), detail: Text(why), isAlbum: false)
                        }
                    }
                    Spacer(minLength: 8)
                    review(of: app)
                }
            } header: {
                Text("What to Do About It")
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

    /// The formula or cask that installed it, when the Homebrew page lists it: that page reads one Homebrew, which
    /// may be another than the one that installed it.
    private var packageOnTheHomebrewPage: HomebrewPackage.ID? {
        let installed: (name: String, kind: HomebrewPackage.Kind, prefix: URL)? =
            finding.formula.map { ($0.name, .formula, $0.prefix) } ?? finding.cask.map { ($0.token, .cask, $0.prefix) }
        guard let installed,
              homebrew.installation.map({ PathPattern.comparablePath(of: $0.prefix) })
                  == PathPattern.comparablePath(of: installed.prefix)
        else { return nil }
        return homebrew.packages?.first { $0.kind == installed.kind && $0.name == installed.name }?.id
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
        } else if let package = packageOnTheHomebrewPage {
            Button("Review in Homebrew") {
                homebrew.selection = .package(package)
                Navigator.shared.requestedTool = .homebrew
            }
            .buttonStyle(.borderedProminent)
        } else if let job = finding.job {
            Button("Review in Background Items") {
                backgroundItems.selection = job
                Navigator.shared.requestedTool = .backgroundItems
            }
            .buttonStyle(.borderedProminent)
        } else if finding.kind == .javaRuntime, finding.formula == nil {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([finding.url])
            }
            .buttonStyle(.borderedProminent)
        }
    }

    static let intelBasedAppsList: LocalizedStringResource = "System Settings > General > About > Intel-based Apps lists the apps macOS 28 will not run. Peel also looks inside apps and at plug-ins and drivers."

    /// What to do about a finding: the step, and why in a circled i beside it.
    struct Advice {
        let step: LocalizedStringResource
        var why: LocalizedStringResource?
    }

    private var advice: Advice {
        Self.advice(
            for: finding.kind, formula: finding.formula?.name, cask: finding.cask?.token,
            isOnThePlugInsPage: finding.isOnThePlugInsPage, hasReceipt: receipt != nil
        )
    }

    /// A driver, a tool in `/usr/local`, or a plug-in the Plug-ins page doesn't list is left to the software that
    /// installed it, which knows what else goes with it.
    static func advice(
        for kind: IntelFinding.Kind, formula: String?, cask: String?, isOnThePlugInsPage: Bool, hasReceipt: Bool
    ) -> Advice {
        let withItsSoftware = Advice(
            step: "Remove it with its software", why: "The software that installed it may have an uninstaller of its own."
        )
        switch kind {
        case .commandLineTool where formula != nil:
            return Advice(
                step: "Installed by Homebrew", why: "It goes when Homebrew uninstalls the formula \(formula ?? "")."
            )
        case .commandLineTool where cask != nil:
            return Advice(step: "Installed by Homebrew", why: "It goes when Homebrew uninstalls the cask \(cask ?? "").")
        case .driver, .commandLineTool:
            return withItsSoftware
        case .app:
            return Advice(step: "Remove it in Applications", why: "There you see everything that goes with the app.")
        case .insideApp:
            return Advice(
                step: "Comes with its app", why: "It cannot be removed on its own. An update of the app may replace it."
            )
        case .plugin:
            return isOnThePlugInsPage ? Advice(step: "Remove it in Plug-ins") : withItsSoftware
        case .backgroundItem:
            return Advice(
                step: "Remove it with its software",
                why: "Background Items moves only the file of the job, not the program it runs."
            )
        case .javaRuntime where formula != nil:
            return Advice(
                step: "Remove it with Homebrew",
                why: "Homebrew installed it with the formula \(formula ?? ""), so uninstall that formula rather than moving the folder."
            )
        case .javaRuntime where hasReceipt:
            return Advice(
                step: "Remove it in Package Receipts",
                why: "A package installed it, so Package Receipts can move it and History can put it back."
            )
        case .javaRuntime:
            return Advice(
                step: "Remove it in Finder",
                why: "A Java runtime is its folder. Finder asks for an administrator password where needed."
            )
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
