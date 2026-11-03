import PeelCore
import SwiftUI

/// Edits the file of one of this account's launch agents as text. Saving moves the file as it is to the Trash, where
/// History can put it back, writes the text in its place, and loads the job again when launchd had it.
struct LaunchAgentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @Environment(RemovalHistoryStore.self) private var history
    let item: BackgroundItem
    @State private var file: LaunchAgentFile?
    @State private var openingProblem: LaunchAgentFile.Problem?
    @State private var text = ""
    /// Why the last Save changed nothing, shown until the text changes.
    @State private var savingProblem: LaunchAgentFile.Problem?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit \(item.label)")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("When you save, Peel moves the file as it is to the Trash, where History can put it back, and writes this in its place. If the job is loaded, Peel loads it again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if file != nil {
                    PlainTextEditor(text: $text, label: String(localized: "Contents of \(fileName)"))
                } else {
                    ZStack {
                        if openingProblem == nil {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let problem = shownProblem {
                    StatusLabel(title: Text(verbatim: problem))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            footer
        }
        .frame(width: 680, height: 540)
        // Escape closes a sheet even while its buttons are off.
        .interactiveDismissDisabled(isSaving)
        .task { await open() }
        .onChange(of: text) { savingProblem = nil }
    }

    private var fileName: String { item.plistURL?.lastPathComponent ?? item.label }

    private var shownProblem: String? {
        if let openingProblem { return openingProblem.explanation(label: item.label, url: item.plistURL) }
        if let savingProblem { return savingProblem.explanation(label: item.label, url: item.plistURL) }
        guard let file, text != file.text else { return nil }
        return file.problem(in: text)?.explanation(label: item.label, url: file.url)
    }

    private var canSave: Bool {
        guard let file, text != file.text, file.problem(in: text) == nil else { return false }
        return !isSaving && history.mayMove && !backgroundItems.runningActionItemIDs.contains(item.id)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 8)
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
            if file != nil {
                // Not the default action, so Return in the text never saves.
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func open() async {
        switch await LaunchAgentFile.open(item) {
        case .success(let opened):
            text = opened.text
            file = opened
        case .failure(let problem):
            openingProblem = problem
        }
    }

    private func save() {
        guard let file else { return }
        let text = text
        isSaving = true
        Task {
            // Read before the move: afterwards nothing is at that path to measure.
            var sizes: [URL: Int64] = [:]
            sizes[file.url] = await FileSize.reclaimableSize(of: file.url)
            let outcome = await history.moving(tool: .backgroundItems, source: item.label, sizes: sizes) {
                await backgroundItems.save(text, editing: file, of: item) { moved in
                    await history.record(moved, tool: .backgroundItems, source: item.label, sizes: sizes)
                }
            }
            isSaving = false
            switch outcome {
            case .saved?, .oldFileInTheTrash?: dismiss()
            case .unchanged(let problem, _)?: savingProblem = problem
            case nil: break
            }
        }
    }
}

@MainActor
extension LaunchAgentFile.Problem {
    /// What the editor says of the problem, for the job `label` names in the file at `url`.
    func explanation(label: String, url: URL?) -> String {
        switch self {
        case .cannotBeEdited: String(localized: "Peel edits only the agents in your own LaunchAgents folder.")
        case .notAPlainFile:
            String(localized: "It’s a link or not a plain file, so Peel doesn’t edit it here. Edit the file it leads to.")
        case .notYours: String(localized: "Another account owns this file, so Peel doesn’t edit it.")
        case .tooLarge:
            String(localized: "This file is larger than 1 MB, more than a job’s file holds, so Peel doesn’t open it.")
        case .unreadable: String(localized: "Peel couldn’t read this file.")
        case .changed: String(localized: "The file changed since Peel read it. Close this and open it again.")
        case .notAPropertyList(let line?): String(localized: "This isn’t a valid property list. Look at line \(line).")
        case .notAPropertyList(nil): String(localized: "This isn’t a valid property list.")
        case .notADictionary: String(localized: "A job’s file holds a dictionary at its top.")
        case .labelChanged: String(localized: "The Label has to stay \(label).")
        case .noProgram: String(localized: "Add Program or ProgramArguments, which say what the job runs.")
        case .programIsNotText: String(localized: "Program has to be the path of what the job runs.")
        case .argumentsAreNotText: String(localized: "ProgramArguments has to be a list of words, the program first.")
        case .notMoved(let reason):
            String(localized: "The file couldn’t move to the Trash, so nothing changed.") + "\n\n" + reason.explanation
        case .notWritten(let error):
            String(localized: "Peel couldn’t write the new file, so it put the old one back.")
                + Self.saying(error, of: url)
        case .incomplete(let error):
            String(localized: "Peel couldn’t write all of the new file. Move it to the Trash, then put the old one back from History.")
                + Self.saying(error, of: url)
        }
    }

    /// What the list says once the old file is in the Trash and the new one isn't whole in its place.
    func explanationWithTheOldFileInTheTrash(url: URL) -> String {
        guard case .notWritten(let error) = self else { return explanation(label: "", url: url) }
        return String(localized: "Peel couldn’t write the new file. The old one is in the Trash, where History can put it back.")
            + Self.saying(error, of: url)
    }

    private static func saying(_ error: SystemError, of url: URL?) -> String {
        url.map { "\n\n" + error.description(of: $0) } ?? ""
    }
}
