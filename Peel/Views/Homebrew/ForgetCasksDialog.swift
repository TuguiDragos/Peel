import PeelCore
import SwiftUI

/// The dialog that asks before forgetting casks whose apps are gone, on the Homebrew page and on a cask's own page.
/// Their receipts go to the Trash and are recorded in History, like any other removal.
struct ForgetCasksDialog: ViewModifier {
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(RemovalOutcome.self) private var outcome
    @Binding var casks: [HomebrewPackage]?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: isAsking, presenting: casks) { casks in
                Button(casks.count == 1 ? "Forget Cask" : "Forget All") { forget(casks) }
                Button("Cancel", role: .cancel) {}
            } message: { casks in
                casks.count == 1
                    ? Text("Its Homebrew receipt goes to the Trash with the links Homebrew made into it, so Homebrew stops listing it. History can put it back.")
                    : Text("Their Homebrew receipts go to the Trash with the links Homebrew made into them, so Homebrew stops listing them. History can put them back.")
            }
    }

    private var title: Text {
        guard let casks else { return Text(verbatim: "") }
        guard casks.count > 1 else { return Text("Forget \(casks.first?.name ?? "")?") }
        return Text(verbatim: String(inflecting: "Forget ^[\(casks.count) cask](inflect: true)?"))
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { casks != nil }, set: { if !$0 { casks = nil } })
    }

    private func forget(_ casks: [HomebrewPackage]) {
        Task {
            let named = HomebrewLibrary.source(of: casks)
            let result = await homebrew.forget(casks) { result in
                var sizes: [URL: Int64] = [:]
                for item in result.trashed {
                    sizes[item.originalURL] = await FileSize.reclaimableSize(of: item.trashedURL)
                }
                await history.record(result, tool: .homebrew, source: named.source, sourceKey: named.key, sizes: sizes)
            }
            if let result { outcome.report(result) }
        }
    }
}

extension View {
    func forgetCasksDialog(for casks: Binding<[HomebrewPackage]?>) -> some View {
        modifier(ForgetCasksDialog(casks: casks))
    }
}
