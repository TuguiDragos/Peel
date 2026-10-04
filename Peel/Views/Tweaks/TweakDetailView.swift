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

    var body: some View {
        let state = tweaks.state(of: tweak)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(tweak.words.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoNote(
                        name: String(localized: tweak.words.title),
                        detail: Text(note),
                        footnote: Text(verbatim: "\(tweak.domain) \(tweak.key)"),
                        isMarked: tweak.words.caution != nil
                    )
                }
                // A folder tweak holds a path rather than on or off, so the path is the row's second line.
                if let path = state.path {
                    Text(verbatim: path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            control(state)
        }
        .padding(.vertical, 4)
    }

    /// The note the circled i opens: what the tweak does, any caution (in the accent color), how the change
    /// takes effect, and whether macOS has its own control for the setting.
    private var note: AttributedString {
        var text = AttributedString(String(localized: tweak.words.detail))
        if let caution = tweak.words.caution {
            var marked = AttributedString("\n\n\(String(localized: caution))")
            marked.foregroundColor = Color.accentColor
            text += marked
        }
        // Each sentence gets its own paragraph instead of being joined with a space, since Japanese and
        // Chinese put no space between sentences.
        var paragraphs: [String] = []
        if let restart = tweak.restart.sentence {
            paragraphs.append(String(localized: restart))
        }
        if tweak.hasASystemControl {
            paragraphs.append(String(localized: "macOS has its own control for this, so it can change back."))
        }
        if !paragraphs.isEmpty {
            text += AttributedString("\n\n" + paragraphs.joined(separator: "\n\n"))
        }
        return text
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
    private func control(_ state: TweakState) -> some View {
        switch tweak.kind {
        case .aSwitch, .aSwitchForThisAppAlone:
            let isOn = Binding(
                get: { tweaks.isOn(tweak, state: state) },
                set: { tweaks.set(tweak, on: $0) }
            )
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .accessibilityRepresentation {
                    Toggle(isOn: isOn) { Text(tweak.words.title) }
                }
                .disabled(state.isManaged)
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
        }
    }
}
