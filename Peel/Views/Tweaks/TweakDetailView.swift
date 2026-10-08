import PeelCore
import SwiftUI

struct TweakDetailContent: View {
    @Environment(TweakLibrary.self) private var tweaks
    let group: Tweak.Group

    var body: some View {
        Form {
            Section {
                ForEach(tweaks.tweaks(in: group)) { tweak in
                    TweakRow(tweak: tweak)
                }
            } footer: {
                if tweaks.isWaitingForLogOut(group) {
                    Text("One of these takes effect the next time you log out and back in.")
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 6)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct TweakRow: View {
    @Environment(TweakLibrary.self) private var tweaks
    let tweak: Tweak
    @State private var nameProblem: ScreenshotName.Problem?

    var body: some View {
        let state = tweaks.state(of: tweak)
        let parent = tweak.onlyWhile.flatMap { id in TweakCatalog.all.first { $0.id == id } }
        let works = parent.map { tweaks.isOn($0, state: tweaks.state(of: $0)) } ?? true
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(tweak.words.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(works ? .primary : .tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoNote(
                        name: String(localized: tweak.words.title),
                        detail: Text(verbatim: note),
                        footnote: Text(verbatim: "\(tweak.domain) \(tweak.key)"),
                        caution: tweak.words.caution.map { Text($0) }
                    )
                }
                // A folder tweak holds a path rather than on or off, so the path is the row's second line.
                if tweak.kind == .folder, let path = state.text {
                    Text(verbatim: path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if !works, let whileOff = parent?.words.whileOff {
                    Text(whileOff)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let nameProblem {
                    Text(nameProblem.message)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let restart = tweak.restart.note {
                    // Shown on the row, not only in the note: some switches restart Finder or the Dock at once,
                    // and the user should know that before using one.
                    Text(restart)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            standing(state)
            control(state, works: works)
        }
        .padding(.vertical, 4)
        // A switch that works only under another sits a step in from it, right below it.
        .padding(.leading, parent == nil ? 0 : 20)
    }

    /// The note the circled i opens: what the tweak does, how the change takes effect, and whether macOS has its
    /// own control for the setting. Each sentence gets its own paragraph instead of being joined with a space,
    /// since Japanese and Chinese put no space between sentences.
    private var note: String {
        var paragraphs = [String(localized: tweak.words.detail)]
        if let restart = tweak.restart.sentence {
            paragraphs.append(String(localized: restart))
        }
        if tweak.hasASystemControl {
            paragraphs.append(String(localized: "macOS has its own control for this, so it can change back."))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// A label for a setting Peel can't change: one locked by a configuration profile, or one whose last write
    /// macOS refused.
    @ViewBuilder
    private func standing(_ state: TweakState) -> some View {
        if state.isManaged {
            Label("Locked by a profile", systemImage: "lock")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        } else if tweaks.refused.contains(tweak.id) {
            // Explains why the switch went back after macOS refused the write.
            Label("macOS refused it", systemImage: "exclamationmark.triangle")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func control(_ state: TweakState, works: Bool) -> some View {
        switch tweak.kind {
        case .aSwitch, .aSwitchForThisAppAlone:
            let isOn = Binding(
                get: { tweaks.isOn(tweak, state: state) },
                set: { tweaks.set(tweak, on: $0) }
            )
            if #available(macOS 27, *) {
                RowSwitch(title: Text(tweak.words.title), isOn: isOn)
                    .disabled(state.isManaged || !works)
            } else {
                Toggle(isOn: isOn) { EmptyView() }
                    .labelsHidden()
                    .accessibilityRepresentation {
                        Toggle(isOn: isOn) { Text(tweak.words.title) }
                    }
                    .disabled(state.isManaged || !works)
            }
        case .folder:
            // The folder row has no switch to turn off, so Put Back is how the user undoes Peel's change.
            // It fades in and out, since it takes room in the row as it comes and goes.
            Group {
                if tweaks.isChangedByPeel(tweak) {
                    Button("Put Back") {
                        Task { await tweaks.reset(tweak) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isManaged)
                    .accessibilityLabel(Text("Put back the screenshot folder"))
                    .transition(.opacity)
                }
                Button("Choose…") {
                    Task { await tweaks.chooseScreenshotFolder(for: tweak) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.isManaged)
                .accessibilityLabel(Text("Choose the folder for screenshots"))
            }
            .motion(value: tweaks.isChangedByPeel(tweak))
        case .name:
            TweakNameField(tweak: tweak, state: state, problem: $nameProblem)
        }
    }
}

private struct TweakNameField: View {
    @Environment(TweakLibrary.self) private var tweaks
    let tweak: Tweak
    let state: TweakState
    @Binding var problem: ScreenshotName.Problem?
    @State private var draft: String?
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let putsBack = !isEdited && tweaks.isChangedByPeel(tweak)
        Group {
            TextField(text: text, prompt: ScreenshotName.macOSDefault.map { Text(verbatim: $0) }) {
                Text(tweak.words.title)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onDisappear(perform: commit)
            // Both titles take room, so the button keeps the width of the longer one and the field stays put.
            Button {
                if putsBack {
                    Task { await tweaks.reset(tweak) }
                } else {
                    commit()
                }
            } label: {
                ZStack {
                    Text("Save").opacity(putsBack ? 0 : 1)
                    Text("Put Back").opacity(putsBack ? 1 : 0)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!putsBack && !isEdited)
            .accessibilityLabel(putsBack ? Text("Put back the screenshot name") : Text("Save the screenshot name"))
            .motion(value: putsBack)
        }
        .disabled(state.isManaged)
    }

    private var isEdited: Bool {
        draft.map { $0.trimmingCharacters(in: .whitespaces) != state.text ?? "" } ?? false
    }

    private var text: Binding<String> {
        Binding(
            get: { draft ?? state.text ?? "" },
            set: {
                draft = $0
                problem = nil
            }
        )
    }

    private func commit() {
        guard let draft, !isSaving else { return }
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard name != state.text ?? "" else {
            self.draft = nil
            return
        }
        if let found = ScreenshotName.problem(with: name) {
            problem = found
            return
        }
        isSaving = true
        Task {
            await tweaks.rename(tweak, to: name)
            self.draft = nil
            isSaving = false
        }
    }
}

extension ScreenshotName.Problem {
    var message: LocalizedStringResource {
        switch self {
        case .separator: "A name can’t have a slash or a colon in it."
        case .hidden: "A name can’t start with a period, or the screenshots would be hidden."
        case .tooLong: "That name is too long for a file name."
        }
    }
}
