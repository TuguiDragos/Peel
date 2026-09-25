import PeelCore
import SwiftUI

struct PackageList: View {
    @Environment(PackageLibrary.self) private var packages
    @State private var searchText = ""
    @State private var isRescanning = false

    var body: some View {
        @Bindable var packages = packages
        let filtered = filteredReceipts

        List(filtered, selection: $packages.selection) { receipt in
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.identifier)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        if receipt.nothingLeftOnDisk {
                            Text("Receipt only")
                        } else if receipt.holdsNothingToRemove {
                            Text("Nothing Peel moves")
                        }
                        if let version = receipt.version {
                            Text(verbatim: version)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if !receipt.nothingLeftOnDisk, !receipt.holdsNothingToRemove {
                    Text(receipt.total.text)
                        .rowFigure()
                }
            }
            .padding(.vertical, 2)
        }
        .scanState(phase(filtered), isRescanning: isRescanning, scan: packages.scanRun) {
            if packages.couldNotAsk {
                ContentUnavailableView(
                    "macOS Didn’t Answer",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Peel asked macOS what was installed with a package and got no answer. This list says nothing about what is on this Mac.")
                )
            } else if packages.receipts?.isEmpty == true {
                ContentUnavailableView(
                    "No Package Receipts",
                    systemImage: "shippingbox",
                    description: Text("Software installed with an installer package, other than Apple’s, will appear here.")
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
            guard packages.receipts == nil, !packages.isScanning, !packages.scanRun.wasStopped else { return }
            await packages.refresh()
        }
        .rescanOnExclusionChange("PackageList") { await packages.refresh() }
    }

    private func phase(_ filtered: [PackageReceipt]) -> ScanPhase {
        if packages.receipts == nil { return packages.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if packages.couldNotAsk { return .message }
        if packages.receipts?.isEmpty == true { return .message }
        if filtered.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    private var filteredReceipts: [PackageReceipt] {
        let receipts = packages.receipts ?? []
        guard !searchText.isEmpty else { return receipts }
        return receipts.filter { SearchText.matches($0.identifier, searchText) }
    }
}
