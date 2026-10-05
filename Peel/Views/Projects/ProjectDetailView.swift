import PeelCore
import SwiftUI

struct ProjectDetailView: View {
    @Environment(ProjectLibrary.self) private var projects
    let group: ProjectGroup

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            Section {
                ForEach(Array(group.artifacts.enumerated()), id: \.element.id) { index, artifact in
                    RemovalRow(
                        url: artifact.url,
                        icon: .symbol("shippingbox"),
                        detail: detail(for: artifact),
                        warning: warning(for: artifact),
                        size: artifact.size ?? 0,
                        isMeasured: artifact.size != nil,
                        isFirst: index == 0,
                        selection: projects, isSelected: projects.isSelected(artifact.url)
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    heading(
                        "What the Build Left",
                        "What a build makes again, and what it installed. What Peel isn’t sure about, such as a folder whose name could be anyone’s, is here unselected, with the reason beside it."
                    )
                } actions: {
                    SelectMenu(
                        list: group.artifacts.selectableRows,
                        place: Text(verbatim: group.project.lastPathComponent),
                        selection: projects
                    )
                }
            }

            Section {
                backupsCheckbox
                    .disabled(!projects.canMarkForBackups(group))
                    .listRowSeparator(.hidden)
                let failures = projects.backupMarkFailures(in: group)
                if !failures.isEmpty {
                    Text("^[\(failures.count) folder](inflect: true) wouldn’t take the mark, usually because it belongs to another account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if group.artifacts.contains(where: { projects.excludedFromAbove.contains($0.url) }) {
                    Text("Time Machine already leaves out some of these, through a folder above them or a rule of its own, so that part isn’t Peel’s to change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Backups")
            }
        }
        .dimmedWhileBusy(projects.isScanning)
        .safeAreaBar(edge: .bottom) {
            RemovalBar(
                page: group.page,
                isScanning: projects.isScanning,
                scan: projects.scanRun
            )
        }
        .fadesInColumn(whenRowsChange: group.artifacts.map(\.url))
        .navigationTitle(group.project.lastPathComponent)
        .toolbar(removing: .title)
    }

    /// A checkbox beside its words rather than a `Toggle` that is the row, as the list's other rows are.
    private var backupsCheckbox: some View {
        let isOn = Binding(
            get: { projects.isExcludedFromBackups(group) },
            set: { projects.setExcludedFromBackups($0, in: group) }
        )
        let explanation = String(localized: "Backups keep the project and skip the folders listed here, installed packages and .terraform included. A folder whose name could mean anything is still backed up. The mark sits on the folder itself: it moves with the folder, and a folder that a build deletes and makes again comes back without it.")
        return HStack(alignment: .checkboxTitleLine, spacing: 5) {
            NativeCheckbox(isOn: isOn, label: String(localized: "Leave these out of Time Machine"), hint: explanation)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leave these out of Time Machine")
                    .checkboxTitleLine()
                Text(verbatim: explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .checkboxTitle()
            .contentShape(.rect)
            .onTapGesture { isOn.wrappedValue.toggle() }
            // The checkbox's label already reads them.
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        PageHeader(systemImage: "folder") {
            Text(verbatim: group.project.lastPathComponent)
                .pageTitle()
                .help(Text(verbatim: group.project.lastPathComponent))
        } details: {
            Text(group.project.abbreviatedPath)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if group.lastChange == .recently {
                NoteBadge(
                    title: Text("Changed in the last 7 days"), systemImage: "hand.raised", tint: .secondary,
                    name: String(localized: "Changed in the last 7 days"),
                    detail: Text("Something in this project changed in the last 7 days, so none of it is selected for you.")
                )
            }
        } trailing: {
            // The size of all the folders listed, selected or not. The bar at the bottom shows the selection's size.
            TotalLabel(total: group.total, caption: Text("in here"))
        }
        .contextMenu {
            ItemMenu(url: group.project)
        }
    }

    private func detail(for artifact: ProjectArtifact) -> LocalizedStringResource {
        guard let tool = artifact.tool else { return "Marked as a cache by the tool that made it" }
        return "Made by \(tool)"
    }

    private func warning(for artifact: ProjectArtifact) -> String? {
        if let heldBack = artifact.heldBack {
            return String(localized: heldBack.explanation)
        }
        if artifact.isRecentlyActive {
            return String(localized: "Not selected: something in this project changed in the last 7 days.")
        }
        if artifact.isEnvironment {
            return artifact.name == ".terraform"
                ? String(localized: "Not selected: it holds your current workspace and the last backend configuration, which `terraform init` doesn’t bring back.")
                : String(localized: "Not selected: these are installed packages, not build output.")
        }
        if artifact.hasGenericName {
            return String(localized: "Not selected: a folder called \(artifact.name) could be anyone’s.")
        }
        if !artifact.lastActivityIsCertain {
            return String(localized: "Not selected: this project is too large for Peel to tell when it last changed.")
        }
        return nil
    }
}
