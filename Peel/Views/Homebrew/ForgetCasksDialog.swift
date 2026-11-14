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
                Button(homebrew.forgettable(casks).count == 1 ? "Forget Cask" : "Forget All") { forget(casks) }
                Button("Cancel", role: .cancel) {}
            } message: { casks in
                let forgotten = homebrew.forgettable(casks)
                let said = forgotten.count == 1
                    ? Text("Its Homebrew receipt goes to the Trash with the links Homebrew made into it in its command and completion folders, so Homebrew stops listing it. History can put it back.")
                    : Text("Their Homebrew receipts go to the Trash with the links Homebrew made into them in its command and completion folders, so Homebrew stops listing them. History can put them back.")
                if forgotten.count < casks.count {
                    Text("\(said)\n\n\(Text("A cask excluded in Settings stays listed."))")
                } else {
                    said
                }
            }
    }

    /// Names or counts only the casks Forget moves: the exclusions keep the rest.
    private var title: Text {
        guard let casks else { return Text(verbatim: "") }
        let forgotten = homebrew.forgettable(casks)
        guard forgotten.count > 1 else { return Text("Forget \((forgotten.first ?? casks.first)?.name ?? "")?") }
        return Text(verbatim: String(inflecting: "Forget ^[\(forgotten.count) cask](inflect: true)?"))
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { casks != nil }, set: { if !$0 { casks = nil } })
    }

    private func forget(_ casks: [HomebrewPackage]) {
        Task {
            let asked = HomebrewLibrary.source(of: casks, after: TrashResult())
            let result = await history.moving(tool: .homebrew, source: asked.source, sourceKey: asked.key) {
                await homebrew.forget(casks) { result in
                    var sizes: [URL: Int64] = [:]
                    for item in result.trashed {
                        sizes[item.originalURL] = await FileSize.reclaimableSize(of: item.trashedURL)
                    }
                    let named = HomebrewLibrary.source(of: casks, after: result)
                    await history.record(
                        result, tool: .homebrew, source: named.source, sourceKey: named.key, sizes: sizes
                    )
                }
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
