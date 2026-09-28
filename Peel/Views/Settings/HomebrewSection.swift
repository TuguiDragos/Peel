import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// Which `brew` Peel runs: the one where Homebrew installs itself, or one the person chose for a Homebrew in a
/// folder of its own.
struct HomebrewSection: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var choice = HomebrewChoice().load()
    @State private var isChoosing = false
    @State private var confirming: URL?
    @State private var refusal: HomebrewChoice.Refusal?
    @State private var couldNotSave = false

    var body: some View {
        Section {
            LabeledContent {
                Text(Homebrew.executableURL?.abbreviatedPath ?? String(localized: "Not found"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } label: {
                Text(verbatim: "brew")
            }
            if couldNotSave {
                WarningLabel(title: Text("Peel couldn’t save which `brew` to run."))
            }
            HStack {
                Button("Choose…") { isChoosing = true }
                Spacer()
                if choice != nil {
                    Button("Use the Usual Places") { use(nil) }
                }
            }
            .editingControls()
        } header: {
            titled("Homebrew", "Peel runs the `brew` in /opt/homebrew or /usr/local. If your Homebrew is in a folder of its own, such as /opt/brew, choose its `brew`, and Peel and `peel` run that one.")
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.item]) { result in
            guard let url = try? result.get() else { return }
            if let why = HomebrewChoice.refusal(of: url) {
                refusal = why
            } else {
                confirming = url
            }
        }
        .fileDialogDefaultDirectory(URL(filePath: "/opt", directoryHint: .isDirectory))
        .alert("Peel can’t run this file.", isPresented: isShowingRefusal) {
            Button("OK", role: .cancel) {}
        } message: {
            refusalMessage
        }
        .alert("Run this brew for Homebrew?", isPresented: isConfirming, presenting: confirming) { brew in
            Button("Use It") { use(brew) }
            Button("Cancel", role: .cancel) {}
        } message: { brew in
            Text("Peel runs \(brew.abbreviatedPath) whenever it asks Homebrew something, and so does `peel`. Choose it only if it belongs to your Homebrew.")
        }
    }

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var refusalMessage: Text {
        switch refusal {
        case .notBrew: Text("Choose the file called `brew`, in the bin folder of your Homebrew.")
        case .notAProgram: Text("It isn’t a program Peel can run.")
        case .ownedByAnotherAccount: Text("It belongs to another account, which could change what it runs.")
        case .writableByEveryone: Text("Anyone on this Mac can change it, so Peel won’t run it.")
        case nil: Text(verbatim: "")
        }
    }

    private func use(_ brew: URL?) {
        couldNotSave = !HomebrewChoice().save(brew)
        choice = HomebrewChoice().load()
        Task { await homebrew.refresh() }
    }
}
