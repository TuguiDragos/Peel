import PeelCore
import SwiftUI

/// The dialog that asks before forgetting a package receipt, used on the package's page and on the page of
/// the app it installed. The receipt goes to the Trash and is recorded in History, like any other removal.
struct ForgetReceiptDialog: ViewModifier {
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(RemovalOutcome.self) private var outcome
    @Binding var receipt: PackageReceipt?
    /// Forgets the receipt, records it with the closure it is given, then scans the receipts again, keeping its page
    /// busy until all three are done. History is written first, because a scan can take a while and History is how
    /// the user puts the receipt back.
    let forget: (PackageReceipt, _ record: (TrashResult) async -> Void) async -> TrashResult

    func body(content: Content) -> some View {
        content
            .confirmationDialog(Text("Forget the receipt of \(receipt?.identifier ?? "")?"), isPresented: isAsking, presenting: receipt) { receipt in
                Button("Forget Receipt") {
                    Task {
                        let result = await forget(receipt) { result in
                            var sizes: [URL: Int64] = [:]
                            for item in result.trashed {
                                sizes[item.originalURL] = await FileSize.reclaimableSize(of: item.trashedURL)
                            }
                            await history.record(result, tool: .packages, source: receipt.identifier, sizes: sizes)
                        }
                        outcome.report(result)
                    }
                }
                // While what the package installed is still here, Return keeps the receipt, so the message is read.
                if receipt.installedApps.isEmpty {
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("Cancel", role: .cancel) {}
                        .keyboardShortcut(.defaultAction)
                }
            } message: { receipt in
                if receipt.installedApps.isEmpty {
                    Text("The receipt goes to the Trash, so macOS no longer counts the package as installed. What it installed stays where it is.")
                } else {
                    Text("The receipt goes to the Trash. What the package installed stays and keeps working, but macOS, installers that check the receipt, and Peel stop knowing the package installed it, so Peel can no longer list what it put on this Mac.")
                }
            }
    }

    private var isAsking: Binding<Bool> {
        Binding(
            get: { receipt != nil },
            set: { if !$0 { receipt = nil } }
        )
    }
}

extension View {
    func forgetReceiptDialog(
        for receipt: Binding<PackageReceipt?>,
        forget: @escaping (PackageReceipt, _ record: (TrashResult) async -> Void) async -> TrashResult
    ) -> some View {
        modifier(ForgetReceiptDialog(receipt: receipt, forget: forget))
    }
}
