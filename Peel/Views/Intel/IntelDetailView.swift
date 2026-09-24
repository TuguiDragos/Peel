import AppKit
import PeelCore
import SwiftUI

struct IntelDetailView: View {
    @Environment(AppLibrary.self) private var library
    let finding: IntelFinding

    private var app: InstalledApp? {
        library.apps.first { $0.url == finding.url || finding.url.path(percentEncoded: false).hasPrefix($0.url.path(percentEncoded: false) + "/") }
    }

    var body: some View {
        Form {
            Section {
                header
                    .listRowSeparator(.hidden)
            }

            Section {
                Text(finding.kind.explanation(onAppleSilicon: HostArchitecture.isAppleSilicon))
                    .font(.callout)
                if !HostArchitecture.isAppleSilicon {
                    Text("On an Apple silicon Mac it would need Rosetta.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if Rosetta.isInstalled {
                    // After macOS 27, Apple keeps Rosetta only for older games, which is why this says "most"
                    // rather than "all" (developer.apple.com/news, Rosetta).
                    Text("macOS 27 is the last release that runs most Intel software through Rosetta. Apple keeps it for older games.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if #available(macOS 27, *) {
                        Text("The Intel-based Apps list in System Settings > General > About names the apps macOS 28 won’t run. Peel also looks inside apps and at plug-ins and drivers, which that list may leave out.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // A Mac that had Rosetta does not get it back after upgrading to macOS 27. Without it, Intel
                    // software does not run at all, so the text must not say it runs through Rosetta.
                    Text("Rosetta isn’t installed on this Mac, so this doesn’t run at all. macOS offers to install it the first time you open an Intel app, and macOS 27 is the last release that runs most Intel software through it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Why It Matters")
            }

            Section {
                LabeledContent("Where") {
                    Text(verbatim: finding.url.abbreviatedPath)
                        .textSelection(.enabled)
                        .help(Text(verbatim: finding.url.path(percentEncoded: false)))
                }
                .labeledContentStyle(.oneLine)
                LabeledContent("Size") {
                    Text(finding.size.byteCount).monospacedDigit()
                }
                if let lastUsedDate = finding.lastUsedDate {
                    LabeledContent("Last opened") {
                        Text(lastUsedDate, format: .relative(presentation: .named))
                    }
                }
                if let app, let status = library.shownUpdateStatus(of: app) {
                    LabeledContent("Updates") {
                        UpdateStatusBadge(app: app, status: status, isChecking: library.appsCheckingForUpdates.contains(app.id))
                    }
                }
            } header: {
                Text("Details")
            }

            Section {
                HStack {
                    // Show in Finder is centered when alone, and goes first when Review in Applications is beside it.
                    if app == nil {
                        Spacer()
                    }
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([finding.url])
                    }
                    Spacer()
                    if let app {
                        Button("Review in Applications", systemImage: "square.grid.2x2") {
                            library.selection = [app.id]
                            // Selecting the app does not switch tools by itself, so Applications is requested too.
                            Navigator.shared.requestedTool = .applications
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                heading("What to Do About It", advice)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: finding.name))
        .toolbar(removing: .title)
    }

    /// The advice in the note beside the What to Do About It heading. A driver or a tool in `/usr/local` is
    /// left to the software that installed it, which knows what else goes with it.
    private var advice: LocalizedStringResource {
        switch finding.kind {
        case .driver, .commandLineTool:
            "Peel only reports here. The software that installed it may have an uninstaller of its own."
        case .app, .insideApp:
            "Peel only reports here. To remove it, go to Applications, where you see everything that goes with the app."
        case .plugin:
            "Peel only reports here. To remove it, go to Plug-ins."
        case .backgroundItem:
            "Peel only reports here. Background Items moves a job’s configuration file, not the program it runs: that goes with the software that installed it."
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            AppIcon(url: finding.url)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: finding.name)
                    .font(.title.bold())
                    .titleLine()
                    .help(Text(verbatim: finding.name))
                if let owner = finding.owner {
                    Text("in \(owner)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                FlowLayout {
                    NoteBadge(
                        title: Text("Intel only"), systemImage: "cpu", tint: .secondary,
                        name: String(localized: "Intel only"),
                        detail: Text("Built for Intel processors only, so on Apple silicon it runs through Rosetta.")
                    )
                    Badge(title: Text(finding.kind.title), systemImage: finding.kind.systemImage)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
