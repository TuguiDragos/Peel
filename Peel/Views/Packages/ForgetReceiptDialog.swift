import PeelCore
import SwiftUI

/// The dialog that asks before forgetting a package receipt, used on the package's page and on the page of
/// the app it installed. The receipt goes to the Trash and is recorded in History, like any other removal.
struct ForgetReceiptDialog: ViewModifier {
    @Environment(RemovalHistoryStore.self) private var history
    @Binding var receipt: PackageReceipt?
    /// Forgets the receipt, records it with the closure it is given, then scans the receipts again, keeping its page
    /// busy until all three are done. History is written first, because a scan can take a while and History is how
    /// the user puts the receipt back.
    let forget: (PackageReceipt, _ record: (TrashResult) async -> Void) async -> TrashResult
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(Text("Forget the receipt of \(receipt?.identifier ?? "")?"), isPresented: isAsking, presenting: receipt) { receipt in
                Button("Forget Receipt") {
                    Task {
                        let result = await forget(receipt) { result in
                            var sizes: [URL: Int64] = [:]
                            for item in result.trashed {
                                sizes[item.originalURL] = await FileSize.allocatedSize(of: item.trashedURL)
                            }
                            await history.record(result, tool: .packages, source: receipt.identifier, sizes: sizes)
                        }
                        if !result.failures.isEmpty {
                            failure = result.failures.map { $0.url.abbreviatedPath }.joined(separator: "\n")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The receipt goes to the Trash, so macOS no longer counts the package as installed. What it installed stays where it is.")
            }
            .alert("The receipt couldn’t be moved to the Trash.", isPresented: isShowingFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: failure ?? "")
            }
    }

    private var isAsking: Binding<Bool> {
        Binding(
            get: { receipt != nil },
            set: { if !$0 { receipt = nil } }
        )
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
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
