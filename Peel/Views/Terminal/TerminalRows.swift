import PeelCore
import SwiftUI

struct TerminalSwitchRow: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let footnote: String?
    var caption: LocalizedStringResource?
    let isOn: Binding<Bool>
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDisabled ? .tertiary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoNote(
                        name: String(localized: title),
                        detail: Text(detail),
                        footnote: footnote.map { Text(verbatim: $0) }
                    )
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .accessibilityRepresentation {
                    Toggle(isOn: isOn) { Text(title) }
                }
                .disabled(isDisabled)
        }
        .padding(.vertical, 4)
    }
}

struct PromptPreview: View {
    let prompt: Prompt
    let theme: TerminalTheme?
    var user = NSUserName()
    var host = Prompt.hostName()

    private static let systemColors: [Color] = [.black, .red, .green, .yellow, .blue, .purple, .cyan, .white]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(path: "~", branch: nil, failed: false, command: "cd Projects/peel")
            line(path: "~/Projects/peel", branch: "main", failed: false, command: "swift build")
            line(path: "~/Projects/peel", branch: "main", failed: true, command: nil)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.map { Color(terminal: $0.background) } ?? Color(nsColor: .textBackgroundColor),
            in: .rect(cornerRadius: 8)
        )
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
        .accessibilityHidden(true)
    }

    private func line(path: String, branch: String?, failed: Bool, command: String?) -> some View {
        var text = prompt.sample(user: user, host: host, path: path, branch: branch, failed: failed)
            .reduce(into: AttributedString()) { text, segment in
                var run = AttributedString(segment.text)
                run.foregroundColor = color(segment.color)
                text += run
            }
        if let command {
            var run = AttributedString(command)
            run.foregroundColor = color(nil)
            text += run
        } else {
            var cursor = AttributedString(" ")
            cursor.backgroundColor = theme.map { Color(terminal: $0.cursor) } ?? .primary
            text += cursor
        }
        return Text(text)
            .fixedSize()
    }

    private func color(_ index: Int?) -> Color {
        guard let index else { return theme.map { Color(terminal: $0.text) } ?? .primary }
        if let theme, theme.ansi.indices.contains(index) {
            return Color(terminal: theme.ansi[index])
        }
        return Self.systemColors[index % 8]
    }
}
