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
                if let owner = item.owner {
                    LabeledContent("Comes with") { Text(verbatim: owner) }
                }
                if let team = item.teamIdentifier {
                    LabeledContent("Signed by") {
                        Text(verbatim: team)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
                LabeledContent {
                    Text(item.election.title)
                } label: {
                    heading("State", item.election.explanation)
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
                    HStack(spacing: 8) {
                        Text(url.abbreviatedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Show in Finder", systemImage: "arrow.up.forward.app")
                                .minimumTarget()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(Text("Show in Finder"))
                    }
                } header: {
                    Text("Where")
                }
            }

            Section {
            } header: {
                HStack(spacing: 8) {
                    heading("Turning It On and Off", explanation)
                    Spacer(minLength: 8)
                    Button {
                        NSWorkspace.shared.open(AppExtensions.settingsURL)
                    } label: {
                        Text("Open System Settings")
                            .minimumTarget()
                    }
                    .buttonStyle(.borderless)
                    // In a form, a button in a section header is drawn lighter than the header's title (a list draws
                    // them alike), so the button is set to the title's weight.
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

    private var explanation: LocalizedStringResource {
        switch item.kind {
        case .appExtension:
            "Peel doesn’t turn extensions on or off: macOS does. Removing one means removing the app it came with."
        case .systemExtension:
            "macOS keeps its own copy of this, apart from the app, and removes it only when the app goes to the Trash in Finder, sometimes at the next restart. So Peel leaves that app to Finder."
        }
    }
}
