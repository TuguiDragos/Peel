import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// Which `brew` Peel runs: the one where Homebrew installs itself, or one the person chose for a Homebrew in a
/// folder of its own.
struct HomebrewSection: View {
    static let note: LocalizedStringResource = "Peel runs the `brew` in /opt/homebrew or /usr/local. If your Homebrew is elsewhere, choose its `brew`: Peel and `peel` then run that one, and its upgrades and uninstalls go to Terminal."

    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var choice = HomebrewChoice().load()
    @State private var isChoosing = false
    @State private var confirming: URL?
    @State private var refusal: HomebrewChoice.Refusal?
    @State private var whyNotSaved: FileProblem?

    var body: some View {
        let unrunnable = HomebrewChoice().unrunnable()
        let refused = Homebrew.refusedInAUsualPlace()
        let isUnreadable = unrunnable?.refusal == .unreadable
        let brew = unrunnable?.brew ?? refused?.brew ?? Homebrew.executableURL
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(
                        brew?.abbreviatedPath
                            ?? (isUnreadable ? String(localized: "Unknown") : String(localized: "Not found"))
                    )
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { isChoosing = true }
                    if choice != nil || isUnreadable {
                        Button("Use the Usual Places") { use(nil) }
                    }
                }
                .editingControls()
            } label: {
                Text(verbatim: "brew")
            }
            if let unrunnable {
                VStack(alignment: .leading, spacing: 4) {
                    NotedStatus(title: Text(ToolsTab.unrunnableBrew), note: Text(ToolsTab.unrunnableBrewNote))
                    unrunnable.refusal.explanation
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let refused {
                VStack(alignment: .leading, spacing: 4) {
                    StatusLabel(title: Text("Peel doesn’t run this `brew`."))
                    refused.refusal.explanation
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let whyNotSaved {
                StatusLabel(title: Text(notSaved(whyNotSaved)))
            }
        } header: {
            titled("Homebrew", Self.note)
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
            Button("OK") {}
        } message: {
            refusal?.alertMessage ?? Text(verbatim: "")
        }
        .alert("Use this brew?", isPresented: isConfirming, presenting: confirming) { brew in
            Button("Use It") { use(brew) }
            Button("Cancel", role: .cancel) {}
        } message: { brew in
            Text("Peel runs \(brew.abbreviatedPath) whenever it asks Homebrew something, and so does `peel`. Choose it only if it belongs to your Homebrew.")
        }
    }

    private func notSaved(_ why: FileProblem) -> AttributedString {
        why.said(after: AttributedString(localized: "Peel couldn’t save which `brew` to run."), about: HomebrewChoice().url)
    }

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private func use(_ brew: URL?) {
        whyNotSaved = HomebrewChoice().save(brew)
        choice = HomebrewChoice().load()
        Task { await homebrew.readAnotherBrew() }
    }
}

extension HomebrewChoice.Refusal {
    /// Why Peel does not run that `brew`, in a few words.
    var reason: LocalizedStringResource {
        switch self {
        case .notBrew: "Choose the file called `brew`, in the bin folder of your Homebrew."
        case .notAProgram: "It isn’t a program Peel can run."
        case .ownedByAnotherAccount: "Another account owns this `brew`"
        case .writableByEveryone: "Anyone on this Mac can change it, so Peel won’t run it."
        case .unreadable: "Peel cannot read which `brew` you chose"
        }
    }

    /// What more there is to know, for the circled i beside the reason.
    var more: LocalizedStringResource? {
        switch self {
        case .ownedByAnotherAccount(let owner?):
            "The account \(owner) owns it and could change what Peel runs, so Peel runs only a `brew` that your account or the system owns."
        case .ownedByAnotherAccount(nil):
            "That account could change what Peel runs, so Peel runs only a `brew` that your account or the system owns."
        case .unreadable: "It runs none until you choose it again or use the usual places."
        case .notBrew, .notAProgram, .writableByEveryone: nil
        }
    }

    /// The reason and what more there is, whole, for an alert, which has no circled i.
    var alertMessage: Text {
        more.map { Text("\(Text(reason))\n\n\(Text($0))") } ?? Text(reason)
    }

    var explanation: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(reason)
            if let more {
                InfoNote(about: Text(reason), detail: Text(more), isAlbum: false)
            }
        }
    }
}
