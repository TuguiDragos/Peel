import PeelCore
import SwiftUI

struct PackageList: View {
    @Environment(PackageLibrary.self) private var packages
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HelperModel.self) private var helper
    @State private var searchText = ""
    @State private var isRescanning = false
    @State private var receiptsToForget: [PackageReceipt]?

    static let noAnswer: LocalizedStringResource = "Peel asked macOS which packages are installed and got no answer, so it can’t list them. Rescan to try again."

    var body: some View {
        @Bindable var packages = packages
        let filtered = filteredReceipts
        let receiptsOnly = filtered.filter(\.nothingLeftOnDisk)
        let forAllUsers = PackageReceipt.sayingForAllUsers(packages.receipts ?? [])

        List(selection: $packages.selection) {
            if !receiptsOnly.isEmpty {
                Section {
                    ForEach(receiptsOnly) { row(for: $0, sayingForAllUsers: forAllUsers.contains($0.id)) }
                } header: {
                    SectionHeaderLine {
                        heading(
                            "Receipt Only",
                            "macOS still counts these packages as installed, but nothing on their receipts is left on this Mac. Forgetting their receipts moves them to the Trash, and History can put them back."
                        )
                    } count: {
                        Text("^[\(receiptsOnly.count) package](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } actions: {
                        Button { receiptsToForget = receiptsOnly } label: {
                            Text("Forget All")
                                .minimumTarget()
                        }
                        .buttonStyle(.borderless)
                        .disabled(packages.isWorking || waitsForTheHelper(toForget: receiptsOnly) || !history.mayMove)
                        .help(forgetAllHelp(for: receiptsOnly))
                    }
                }
            }
            Section {
                ForEach(filtered.filter { !$0.nothingLeftOnDisk }) {
                    row(for: $0, sayingForAllUsers: forAllUsers.contains($0.id))
                }
            } header: {
                if !receiptsOnly.isEmpty {
                    Text("Installed Packages")
                }
            }
        }
        .accessibilityLabel(Text(Tool.packages.title))
        .forgetReceiptsDialog(for: $receiptsToForget)
        .scanState(phase(filtered), isRescanning: isRescanning, scan: packages.scanRun) {
            if packages.couldNotAsk {
                ContentUnavailableView(
                    "macOS Didn’t Answer",
                    systemImage: "exclamationmark.triangle",
                    description: Text(Self.noAnswer)
                )
            } else if packages.receipts?.isEmpty == true {
                ContentUnavailableView(
                    "No Package Receipts",
                    systemImage: "shippingbox",
                    description: Text("Software installed on the startup disk with an installer package, other than Apple’s, will appear here.")
                )
            } else if filtered.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .columnSearch(text: $searchText, prompt: "Search Package Receipts", when: packages.receipts?.isEmpty == false)
        .fadesInColumn(whenRowsChange: packages.receipts?.map(\.id))
        .navigationTitle(Text(Tool.packages.title))
        .announcesScan(
            packages.isScanning,
            found: packages.summary,
            couldNotLook: packages.couldNotAsk ? "macOS Didn’t Answer" : nil,
            wasStopped: packages.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: packages.isWorking, scan: packages.scanRun) {
                    await packages.refresh()
                }
            }
        }
        .task {
            guard packages.receipts == nil else {
                await packages.refreshIfReceiptsChanged()
                return
            }
            guard !packages.scanRun.isWaitedFor, !packages.scanRun.wasStopped else { return }
            await packages.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await packages.refreshIfReceiptsChanged() }
        }
        .onChange(of: history.revision) {
            Task { await packages.refreshIfReceiptsChanged() }
        }
        .rescanOnExclusionChange("PackageList") { await packages.refresh() }
        .rescanAfterPutBack(.packages) { await packages.refresh() }
    }

    private func phase(_ filtered: [PackageReceipt]) -> ScanPhase {
        if packages.receipts == nil { return packages.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if packages.couldNotAsk { return .message }
        if packages.receipts?.isEmpty == true { return .message }
        if filtered.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    private func row(for receipt: PackageReceipt, sayingForAllUsers: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.identifier)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let name = receipt.name {
                        Text(verbatim: name)
                    }
                    if receipt.nothingLeftOnDisk {
                        Text("Receipt only")
                    } else if !receipt.installedApps.isEmpty {
                        Text("Still installed")
                    } else if receipt.holdsNothingToRemove {
                        Text("Nothing Peel moves")
                    }
                    if let version = receipt.shownVersion {
                        Text("Version \(version)")
                    }
                    if sayingForAllUsers {
                        Text("All users")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if !receipt.nothingLeftOnDisk, !receipt.holdsNothingToRemove,
               let figure = receipt.figure(canUseHelper: helper.canAct) {
                Text(figure.text)
                    .rowFigure()
            }
        }
        .padding(.vertical, 2)
        .tag(receipt.id)
    }

    private func waitsForTheHelper(toForget receipts: [PackageReceipt]) -> Bool {
        !helper.canAct && receipts.contains { PackageActions.forgettingNeedsTheHelper($0) }
    }

    private func forgetAllHelp(for receipts: [PackageReceipt]) -> Text {
        guard !waitsForTheHelper(toForget: receipts) else {
            return Text(helper.standing.whyItCannotAct(registeredByAnotherCopy: helper.isRegisteredByAnotherCopy))
        }
        return Text(verbatim: history.holdingReason?.explanation ?? "")
    }

    private var filteredReceipts: [PackageReceipt] {
        let receipts = packages.receipts ?? []
        guard !searchText.isEmpty else { return receipts }
        return receipts.filter { $0.matches(searchText) }
    }
}
