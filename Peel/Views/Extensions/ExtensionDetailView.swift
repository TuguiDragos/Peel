import AppKit
import PeelCore
import SwiftUI

struct ExtensionDetailView: View {
    let item: AppExtension

    var body: some View {
        Form {
            Section {
                header
                    .listRowSeparator(.hidden)
            }

            Section {
                LabeledContent("Identifier") {
                    Text(verbatim: item.identifier)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .help(Text(verbatim: item.identifier))
                }
                if let point = item.pointName {
                    LabeledContent("Plugs into") {
                        Text(verbatim: point)
                            .help(Text(verbatim: point))
                    }
                }
                if let owner = item.appName {
                    LabeledContent("Comes with") {
                        HStack(spacing: 8) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: owner)
                                if item.goneApp != nil {
                                    Text("No longer installed")
                                        .font(.caption)
                                }
                            }
                            if let app = item.appURL {
                                Button {
                                    Navigator.shared.requestedApp = app
                                    Navigator.shared.requestedTool = .applications
                                } label: {
                                    Label("Review in Applications", systemImage: "square.grid.2x2")
                                        .minimumTarget()
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help(Text("Review in Applications"))
                            }
                        }
                    }
                }
                if let team = item.teamIdentifier {
                    LabeledContent("Signed by") {
                        Text(verbatim: team)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if item.showsItsState {
                    LabeledContent {
                        Text(item.election.title)
                    } label: {
                        heading("State", item.election.explanation)
                    }
                }
                if let reported = item.reportedState {
                    LabeledContent("macOS calls it") {
                        Text(verbatim: reported)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .help(Text(verbatim: reported))
                    }
                }
            } header: {
                Text("What It Is")
            }
            .labeledContentStyle(.oneLine)

            if let url = item.url {
                Section {
                    // Not in Finder: moved alone, an extension breaks its app, or leaves macOS a record with no copy.
                    Text(url.abbreviatedPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(Text(verbatim: url.path(percentEncoded: false)))
                } header: {
                    Text("Where")
                }
            }

            Section {
            } header: {
                HStack(spacing: 8) {
                    heading("Turning It On and Off", explanation)
                    Spacer(minLength: 8)
                    switchButton
                        .buttonStyle(.borderless)
                        // In a form, a button in a section header is drawn lighter than the header's title (a list
                        // draws them alike), so the button is set to the title's weight.
                        .fontWeight(.semibold)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: item.name))
        .toolbar(removing: .title)
    }

    private var header: some View {
        PageHeader(systemImage: item.kind.systemImage) {
            Text(verbatim: item.name)
                .pageTitle()
                .help(Text(verbatim: item.name))
        } details: {
            FlowLayout {
                NoteBadge(
                    title: Text(item.kind.title), systemImage: item.kind.systemImage,
                    name: String(localized: item.kind.title),
                    detail: Text(kindNote)
                )
                NoteBadge(
                    title: Text("Read only"), systemImage: "hand.raised",
                    name: String(localized: "Read only"),
                    detail: Text(explanation)
                )
            }
        }
    }

    private var kindNote: LocalizedStringResource {
        switch item.kind {
        case .appExtension: "It came inside an app, and it goes when that app goes."
        case .systemExtension: "macOS installed this apart from the app that brought it, and keeps its own copy."
        }
    }

    @ViewBuilder
    private var switchButton: some View {
        switch item.turnedOnAndOffIn {
        case .systemSettings:
            Button {
                NSWorkspace.shared.open(AppExtensions.settingsURL)
            } label: {
                Text("Open System Settings")
                    .minimumTarget()
            }
        case .safari:
            Button {
                if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                    NSWorkspace.shared.open(safari)
                }
            } label: {
                Text("Open Safari")
                    .minimumTarget()
            }
        case .widgetGallery, .nowhere:
            EmptyView()
        }
    }

    private var explanation: LocalizedStringResource {
        switch (item.kind, item.turnedOnAndOffIn) {
        case (.systemExtension, _): systemExtensionExplanation
        case (.appExtension, .systemSettings):
            "Peel doesn’t turn extensions on or off: macOS does. Removing one means removing the app it came with."
        case (.appExtension, .safari):
            "Peel doesn’t turn this on or off: Safari does, in Safari > Settings > Extensions, which also shows whether it is on. Removing it means removing the app it came with."
        case (.appExtension, .widgetGallery):
            "macOS doesn’t turn widgets on or off: they are added and removed with Edit Widgets, at the bottom of Notification Center or when you Control-click the wallpaper. Removing one for good means removing the app it came with."
        case (.appExtension, .nowhere):
            "Nothing turns this on or off: Shortcuts and Siri use it whenever someone asks for the app’s actions. Removing it means removing the app it came with."
        }
    }

    private var systemExtensionExplanation: LocalizedStringResource {
        // With its app gone, the advice for an installed app leads nowhere: Orphaned Files' words say what does.
        if item.goneApp != nil, let reason = item.leftAlone { return reason.explanation }
        if #available(macOS 27, *) {
            return item.systemSettingsDeletesIt
                ? "macOS keeps its own copy of this, apart from the app. Moving the app to the Trash in Finder asks macOS to remove it, and so does choosing Delete Extension from the More button beside it in System Settings > General > Login Items & Extensions > Network Extensions. So Peel leaves that app to Finder."
                : "macOS keeps its own copy of this, apart from the app, and moving the app to the Trash in Finder asks macOS to remove it, sometimes at the next restart. So Peel leaves that app to Finder."
        }
        return "macOS keeps its own copy of this, apart from the app, and removes it only when the app goes to the Trash in Finder, sometimes at the next restart. So Peel leaves that app to Finder."
    }
}
