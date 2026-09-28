import AppKit
import PeelCore
import SwiftUI

struct PluginDetailView: View {
    @Environment(PluginLibrary.self) private var plugins
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var isConfirmingRemoval = false
    @Environment(RemovalOutcome.self) private var outcome
    let plugin: Plugin

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    AppIcon(url: plugin.url)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: plugin.name)
                            .pageTitle()
                            .help(Text(verbatim: plugin.name))
                        FlowLayout(spacing: 6) {
                            Badge(title: Text(plugin.category.title), systemImage: "powerplug", tint: .secondary)
                            if plugin.isInstalledForAllUsers {
                                NoteBadge(
                                    title: Text("All users"), systemImage: "person.2", tint: .secondary,
                                    name: String(localized: "All users"),
                                    detail: Text("It’s in /Library, so every account on this Mac has it.")
                                )
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section {
                if let identifier = plugin.bundleIdentifier {
                    LabeledContent("Identifier") {
                        Text(verbatim: identifier)
                            .textSelection(.enabled)
                            .help(Text(verbatim: identifier))
                    }
                    .labeledContentStyle(.oneLine)
                }
                if let version = plugin.version {
                    LabeledContent("Version") {
                        Text(verbatim: version)
                    }
                }
                LabeledContent("Size") {
                    Text(plugin.size.byteCount)
                        .monospacedDigit()
                }
                LabeledContent("Location") {
                    Text(verbatim: plugin.url.abbreviatedPath)
                        .textSelection(.enabled)
                        .help(Text(verbatim: plugin.url.path(percentEncoded: false)))
                }
                .labeledContentStyle(.oneLine)
            }

            if isLocked {
                Section {
                    HelperRequiredBanner()
                }
            }

            Section {
                RemovalsHeldBanner()
                if let refusal = plugin.refusal {
                    Text(refusal.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([plugin.url])
                    }
                    Spacer()
                    Button("Move to Trash", systemImage: "trash") {
                        isConfirmingRemoval = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isLocked || plugin.refusal != nil || plugins.isRemoving || plugins.isScanning
                            || !exclusions.exclusions.isKnown || history.isUnreadable
                    )
                }
            }
        }
        .formStyle(.grouped)
        .dimmedWhileBusy(plugins.isScanning)
        .navigationTitle(plugin.name)
        .toolbar(removing: .title)
        .confirmationDialog(Text.movingToTrash(plugin.name, SizeTotal([plugin.size])), isPresented: $isConfirmingRemoval) {
            Button("Move to Trash") {
                Task {
                    let result = await plugins.moveToTrash(plugin) { result in
                        await history.record(result, tool: .plugins, source: plugin.name, sizes: [URL: Int64](measured: [(plugin.url, plugin.size)]))
                    }
                    outcome.report(result)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apps that use it may stop working.")
        }
    }

    private var isLocked: Bool {
        plugin.requiresPrivileges && plugin.refusal == nil && !helper.canAct
    }
}
